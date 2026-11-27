require 'rails_helper'

RSpec.describe OutOfBandSessionAccessor do
  let(:session_uuid) { SecureRandom.uuid }
  let(:profile_id) { 123 }
  let(:document_capture_session_uuid) { SecureRandom.uuid }

  # This test uses a separate writer instance to write test data to the session store.
  # The OutOfBandSessionAccessor memoizes the data that it reads from the session.
  # Writes require reads to merge test data properly for subsequent writes.
  subject(:writer_instance) { described_class.new(session_uuid) }

  subject(:store) { described_class.new(session_uuid) }

  around do |ex|
    REDIS_POOL.with { |client| client.flushdb }
    ex.run
    REDIS_POOL.with { |client| client.flushdb }
  end

  describe '#ttl' do
    it 'returns the remaining time-to-live of the session data in redis' do
      store.put_pii(
        profile_id: profile_id,
        pii: { first_name: 'Fakey' },
        expiration: 5.minutes.in_seconds,
      )

      expect(store.ttl).to be_within(1).of(5.minutes.in_seconds)
    end
  end

  describe '#load_web_locale' do
    it 'loads the web_locale from the session' do
      writer_instance.put_locale('es')

      web_locale = store.load_web_locale
      expect(web_locale).to eq('es')
    end
  end

  describe '#load_pii' do
    it 'loads PII from the session' do
      writer_instance.put_pii(
        profile_id: profile_id,
        pii: { dob: '1970-01-01' },
        expiration: 5.minutes.in_seconds,
      )

      pii = store.load_pii(profile_id)
      expect(pii).to be_kind_of(Pii::Attributes)
      expect(pii.dob).to eq('1970-01-01')
    end
  end

  describe '#load_idv_resolution_stepdown_pii' do
    let(:issuer) { 'urn:gov:gsa:openidconnect:test' }
    let(:other_issuer) { 'urn:gov:gsa:openidconnect:other' }
    let(:stepdown_pii) do
      {
        first_name: 'Jane',
        last_name: 'Doe',
        dob: '1970-01-01',
        ssn: '666661234',
        address1: '123 Main St',
        city: 'Washington',
        state: 'DC',
        zipcode: '20001',
      }
    end

    it 'loads identity resolution stepdown data for the matching issuer' do
      writer_instance.put_idv_resolution_stepdown(
        issuer:,
        pii: stepdown_pii,
        expiration: 5.minutes.in_seconds,
        document_capture_session_uuid:,
      )

      stepdown = store.load_idv_resolution_stepdown_pii(issuer:)

      aggregate_failures do
        expect(stepdown).to be_kind_of(Pii::Attributes)
        expect(stepdown.first_name).to eq('Jane')
        expect(stepdown.ssn).to eq('666661234')
      end
    end

    it 'does not store raw PII in the user session' do
      writer_instance.put_idv_resolution_stepdown(
        issuer:,
        pii: stepdown_pii,
        document_capture_session_uuid:,
        expiration: 5.minutes.in_seconds,
      )

      raw_session = store.send(:session_data).dig(
        'warden.user.user.session',
        :idv_resolution_stepdown,
      )

      aggregate_failures do
        expect(raw_session).to have_key(:encrypted_pii)
        expect(raw_session).not_to have_key(:pii)
        expect(raw_session.to_s).not_to include('Jane')
        expect(raw_session.to_s).not_to include('666661234')
      end
    end

    it 'does not load malformed stepdown data without encrypted PII' do
      write_out_of_band_user_session(
        session_uuid:,
        user_session: {
          idv_resolution_stepdown: {
            issuer:,
            encrypted_pii: nil,
          },
        },
      )

      expect(store.load_idv_resolution_stepdown_pii(issuer:)).to be_nil
    end

    it 'does not load identity resolution stepdown data for another issuer' do
      writer_instance.put_idv_resolution_stepdown(
        issuer:,
        pii: stepdown_pii,
        expiration: 5.minutes.in_seconds,
        document_capture_session_uuid:,
      )

      expect(store.load_idv_resolution_stepdown_pii(issuer: other_issuer)).to be_nil
    end

    it 'does not load identity resolution stepdown data without a stored handoff' do
      writer_instance.put_locale('en')

      expect(store.load_idv_resolution_stepdown_pii(issuer:)).to be_nil
    end
  end

  describe '#load_idv_stepdown_time' do
    let(:issuer) { 'urn:gov:gsa:openidconnect:test' }
    let(:other_issuer) { 'urn:gov:gsa:openidconnect:other' }
    let(:stepdown_pii) { { first_name: 'Jane' } }
    let(:stepped_down_at) { Time.zone.parse('2026-11-27 12:00:00 UTC') }

    it 'loads the stepdown time' do
      writer_instance.put_idv_resolution_stepdown(
        issuer:,
        pii: stepdown_pii,
        document_capture_session_uuid:,
        stepped_down_at: stepped_down_at.iso8601,
        expiration: 5.minutes.in_seconds,
      )

      expect(store.load_idv_stepdown_time(issuer:)).to eq(stepped_down_at)
    end

    it 'does not load the stepdown time for another issuer' do
      writer_instance.put_idv_resolution_stepdown(
        issuer:,
        pii: stepdown_pii,
        document_capture_session_uuid:,
        stepped_down_at: stepped_down_at.iso8601,
        expiration: 5.minutes.in_seconds,
      )

      expect(store.load_idv_stepdown_time(issuer: other_issuer)).to be_nil
    end
  end

  describe '#load_stepdown_document_capture_session_uuid' do
    let(:issuer) { 'urn:gov:gsa:openidconnect:test' }
    let(:other_issuer) { 'urn:gov:gsa:openidconnect:other' }
    let(:stepdown_pii) { { first_name: 'Jane' } }

    it 'loads the stepdown document capture session uuid' do
      writer_instance.put_idv_resolution_stepdown(
        issuer:,
        pii: stepdown_pii,
        document_capture_session_uuid:,
        expiration: 5.minutes.in_seconds,
      )

      expect(store.load_stepdown_document_capture_session_uuid(issuer:))
        .to eq(document_capture_session_uuid)
    end

    it 'does not load the uuid for another issuer' do
      writer_instance.put_idv_resolution_stepdown(
        issuer:,
        pii: stepdown_pii,
        document_capture_session_uuid:,
        expiration: 5.minutes.in_seconds,
      )

      expect(store.load_stepdown_document_capture_session_uuid(issuer: other_issuer))
        .to be_nil
    end

    it 'does not load the uuid without a stored handoff' do
      writer_instance.put_locale('en')

      expect(store.load_stepdown_document_capture_session_uuid(issuer:)).to be_nil
    end
  end

  describe '#load_x509' do
    it 'loads X509 attributes from the session' do
      writer_instance.put_x509({ subject: 'O=US, OU=DoD, CN=John.Doe.1234' }, 5.minutes.in_seconds)

      x509 = store.load_x509
      expect(x509).to be_kind_of(X509::Attributes)
      expect(x509.subject).to eq('O=US, OU=DoD, CN=John.Doe.1234')
    end
  end

  describe '#authentication_event_at' do
    it 'loads the latest non-remember-device authentication event from the session' do
      authentication_event_at = Time.zone.parse('2026-07-01 12:00:00')
      write_out_of_band_user_session(
        session_uuid:,
        user_session: {
          auth_events: [
            {
              auth_method: TwoFactorAuthenticatable::AuthMethod::SMS,
              at: authentication_event_at,
            },
            {
              auth_method: TwoFactorAuthenticatable::AuthMethod::REMEMBER_DEVICE,
              at: Time.zone.now,
            },
          ],
        },
      )

      expect(store.authentication_event_at).to eq(authentication_event_at)
    end
  end

  describe '#destroy' do
    it 'destroys the session' do
      writer_instance.put_pii(
        profile_id: profile_id,
        pii: { first_name: 'Fakey' },
        expiration: 5.minutes.in_seconds,
      )
      store.destroy

      expect(store.load_pii(profile_id)).to be_nil
    end
  end
end
