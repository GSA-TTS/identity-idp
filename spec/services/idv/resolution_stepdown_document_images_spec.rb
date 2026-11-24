require 'rails_helper'

RSpec.describe Idv::ResolutionStepdownDocumentImages do
  let(:user) { create(:user, :fully_registered) }
  let(:service_provider) { create(:service_provider) }
  let(:document_capture_session) { create(:document_capture_session, user:) }
  let(:stepped_down_at) { 1.minute.ago }
  let(:stepdown_issuer) { service_provider.issuer }
  let(:biometric_sharing_consent_at) { Time.zone.now }
  let(:rails_session_id) { SecureRandom.uuid }
  let(:identity) do
    create(
      :service_provider_identity,
      user:,
      rails_session_id:,
      service_provider: service_provider.issuer,
      acr_values: Saml::Idp::Constants::IAL_VERIFIED_FACIAL_MATCH_REQUIRED_ACR,
      biometric_sharing_consent_at:,
    )
  end
  let!(:artifact) { create(:document_artifact, document_capture_session:, image_type: 'selfie') }

  subject(:document_images) do
    described_class.new(
      identity:,
      session_accessor: OutOfBandSessionAccessor.new(rails_session_id),
    )
  end

  before do
    allow(IdentityConfig.store).to receive(:idv_resolution_stepdown_allowed_issuers)
      .and_return([service_provider.issuer])
    allow(IdentityConfig.store).to receive(:document_images_sharing_enabled).and_return(true)
    allow(IdentityConfig.store).to receive(:document_images_sharing_service_providers)
      .and_return([service_provider.issuer])
    OutOfBandSessionAccessor.new(rails_session_id).put_idv_resolution_stepdown(
      issuer: stepdown_issuer,
      pii: { first_name: 'Jane' },
      document_capture_session_uuid: document_capture_session.uuid,
      stepped_down_at:,
    )
  end

  context 'when the user consented after stepping down' do
    it 'returns the images from the stepdown document capture session' do
      expect(document_images.artifacts).to eq([artifact])
    end

    context 'with document metadata' do
      before { create(:document_metadata, document_capture_session:) }

      it 'returns the document metadata' do
        expect(document_images.document_metadata).to include(document_number: '1234567890')
      end
    end
  end

  shared_examples 'no images' do
    it 'returns no images' do
      expect(document_images.artifacts).to eq([])
    end
  end

  context 'when the user did not consent' do
    let(:biometric_sharing_consent_at) { nil }

    it_behaves_like 'no images'

    it 'is still stepped down' do
      expect(document_images.stepped_down?).to eq(true)
    end
  end

  context 'when the consent predates the stepdown' do
    let(:biometric_sharing_consent_at) { 2.minutes.ago }
    it_behaves_like 'no images'
  end

  context 'when the stepdown is for another service provider' do
    let(:stepdown_issuer) { 'urn:gov:gsa:openidconnect:sp:other' }
    it_behaves_like 'no images'
  end

  context 'when the document capture session belongs to another user' do
    let(:document_capture_session) { create(:document_capture_session) }
    it_behaves_like 'no images'
  end

  context 'when the user has since verified their identity' do
    let(:user) { create(:user, :proofed) }
    it_behaves_like 'no images'
  end
end
