require 'rails_helper'

RSpec.describe OpenidConnect::ProofingData do
  let(:rails_session_id) { SecureRandom.uuid }
  let(:service_provider) { create(:service_provider) }
  let(:issuer) { service_provider.issuer }
  let(:user) { create(:user, profiles: [profile].compact) }
  let(:profile) { create(:profile, :active, :verified) }
  let(:identity) do
    build(
      :service_provider_identity,
      user:,
      service_provider: issuer,
      service_provider_record: service_provider,
      rails_session_id:,
    )
  end
  let(:session_accessor) { OutOfBandSessionAccessor.new(rails_session_id) }
  let(:writer_session_accessor) { OutOfBandSessionAccessor.new(rails_session_id) }

  subject(:proofing_data) do
    described_class.new(identity:, session_accessor:)
  end

  describe '#pii' do
    context 'with an active profile' do
      before do
        writer_session_accessor.put_pii(
          profile_id: profile.id,
          pii: { first_name: 'John', ssn: '666661234' },
          expiration: 5.minutes.in_seconds,
        )
      end

      it 'returns profile PII' do
        expect(proofing_data.pii.first_name).to eq('John')
      end
    end

    context 'with identity resolution stepdown' do
      let(:profile) { nil }
      let(:document_capture_session) do
        create(:document_capture_session, user:, issuer:)
      end

      before do
        writer_session_accessor.put_idv_resolution_stepdown(
          issuer:,
          pii: { first_name: 'Jane', ssn: '666661234' },
          document_capture_session_uuid: document_capture_session.uuid,
          expiration: 5.minutes.in_seconds,
        )
      end

      it 'returns stepdown PII' do
        expect(proofing_data.pii.first_name).to eq('Jane')
      end
    end

    context 'without proofing data' do
      let(:profile) { nil }

      it 'returns blank PII' do
        expect(proofing_data.pii.first_name).to be_nil
      end
    end
  end

  describe '#stepdown?' do
    let(:profile) { nil }
    context 'with stepdown data for the issuer' do
      let(:document_capture_session) { create(:document_capture_session, issuer:, user:) }

      before do
        writer_session_accessor.put_idv_resolution_stepdown(
          issuer:,
          pii: { first_name: 'Jane' },
          document_capture_session_uuid: document_capture_session.uuid,
          expiration: 5.minutes.in_seconds,
        )
      end

      it 'returns true' do
        expect(proofing_data.stepdown?).to eq(true)
      end
    end

    context 'with stepdown data for another issuer' do
      before do
        writer_session_accessor.put_idv_resolution_stepdown(
          issuer: 'urn:gov:gsa:openidconnect:other',
          pii: { first_name: 'Jane' },
          document_capture_session_uuid: SecureRandom.uuid,
          expiration: 5.minutes.in_seconds,
        )
      end

      it 'returns false' do
        expect(proofing_data.stepdown?).to eq(false)
      end
    end
  end

  describe '#document_artifacts' do
    context 'with an active profile' do
      let!(:artifact) do
        create(
          :document_artifact,
          profile:,
          image_type: 'front',
          document_capture_session: create(:document_capture_session, user:),
        )
      end

      it 'returns profile artifacts' do
        expect(proofing_data.document_artifacts).to contain_exactly(artifact)
      end
    end

    context 'with identity resolution stepdown' do
      let(:profile) { nil }
      let(:document_capture_session) do
        create(:document_capture_session, user:, issuer:)
      end
      let!(:artifact) do
        create(
          :document_artifact,
          document_capture_session:,
          image_type: 'front',
        )
      end

      before do
        writer_session_accessor.put_idv_resolution_stepdown(
          issuer:,
          pii: { first_name: 'Jane' },
          document_capture_session_uuid: document_capture_session.uuid,
          expiration: 5.minutes.in_seconds,
        )
      end

      it 'returns document capture session artifacts' do
        expect(proofing_data.document_artifacts).to contain_exactly(artifact)
      end
    end
  end

  describe '#document_images_shareable?' do
    before do
      allow(IdentityConfig.store).to receive(:document_images_sharing_enabled).and_return(true)
      allow(IdentityConfig.store).to receive(:document_images_sharing_service_providers)
        .and_return(document_images_sharing_service_providers)
    end

    let(:document_images_sharing_service_providers) { [issuer] }

    context 'with an active profile' do
      before do
        identity.biometric_sharing_consent_at = profile.verified_at + 1.second
      end

      it 'returns true' do
        expect(proofing_data.document_images_shareable?).to eq(true)
      end

      context 'without biometric sharing consent' do
        before do
          identity.biometric_sharing_consent_at = nil
        end

        it 'returns false' do
          expect(proofing_data.document_images_shareable?).to eq(false)
        end
      end
    end

    context 'with identity resolution stepdown' do
      let(:profile) { nil }
      let(:stepped_down_at) { 2.hours.ago }
      let(:document_capture_session) do
        create(:document_capture_session, user:, issuer:)
      end

      before do
        identity.biometric_sharing_consent_at = 1.hour.ago
        writer_session_accessor.put_idv_resolution_stepdown(
          issuer:,
          pii: { first_name: 'Jane' },
          document_capture_session_uuid: document_capture_session.uuid,
          stepped_down_at: stepped_down_at.iso8601,
          expiration: 5.minutes.in_seconds,
        )
      end

      it 'returns true' do
        expect(proofing_data.document_images_shareable?).to eq(true)
      end

      context 'without biometric sharing consent' do
        before do
          identity.biometric_sharing_consent_at = nil
        end

        it 'returns false' do
          expect(proofing_data.document_images_shareable?).to eq(false)
        end
      end

      context 'with biometric sharing consent before stepdown' do
        before do
          identity.biometric_sharing_consent_at = 3.hours.ago
        end

        it 'returns false' do
          expect(proofing_data.document_images_shareable?).to eq(false)
        end
      end

      context 'without a matching document capture session' do
        let(:document_capture_session) do
          create(:document_capture_session, user:, issuer: 'urn:gov:gsa:openidconnect:other')
        end

        it 'returns false' do
          expect(proofing_data.document_images_shareable?).to eq(false)
        end
      end
    end

    context 'when the service provider is not allowlisted' do
      let(:document_images_sharing_service_providers) { [] }

      it 'returns false' do
        expect(proofing_data.document_images_shareable?).to eq(false)
      end
    end
  end

  describe '#document_metadata' do
    context 'with identity resolution stepdown' do
      let(:profile) { nil }
      let(:document_capture_session) do
        create(:document_capture_session, user:, issuer:)
      end

      before do
        writer_session_accessor.put_idv_resolution_stepdown(
          issuer:,
          pii: { first_name: 'Jane' },
          document_capture_session_uuid: document_capture_session.uuid,
          expiration: 5.minutes.in_seconds,
        )
        create(
          :document_metadata,
          document_capture_session:,
          document_data: { document_number: 'D-5' },
        )
      end

      it 'returns document capture session metadata' do
        expect(proofing_data.document_metadata).to eq(document_number: 'D-5')
      end
    end
  end
end
