require 'rails_helper'

RSpec.describe Idv::UnresolvedHandoff do
  let(:issuer) { 'urn:gov:gsa:openidconnect:sp:passport' }
  let(:user_session) { {}.with_indifferent_access }
  let(:pii) do
    Idp::Constants::MOCK_IDV_APPLICANT_WITH_PASSPORT.merge(
      ssn: '900-12-3456',
      address1: '123 Main St',
      city: 'Nowhere',
      state: 'VA',
      zipcode: '00000',
    )
  end

  subject(:handoff) { described_class.new(user_session:) }

  def start!
    handoff.start!(
      issuer:,
      pii:,
      document_type: Idp::Constants::DocumentTypes::PASSPORT,
      source_check_vendor: 'dos:passport',
    )
  end

  describe '#start!' do
    it 'keeps only profile PII fields and the verification status' do
      start!
      data = user_session[described_class::SESSION_KEY]

      expect(data['issuer']).to eq(issuer)
      expect(data['pii'].keys).to all(
        satisfy { |key|
          Pii::Attributes.members.include?(key.to_sym)
        },
      )
      expect(data['pii']).to include('first_name', 'last_name', 'dob', 'ssn', 'address1')
      expect(data['pii']).not_to include('mrz', 'document_number')
      expect(data['verification_status']).to include(
        'identity_resolution' => 'failed',
        'self_asserted' => %w[social_security_number address],
      )
      expect(data['authorized_at']).to be_nil
    end

    it 'drops blank values, so an empty address line 2 adds no blank line' do
      pii[:address2] = ''
      start!

      expect(user_session[described_class::SESSION_KEY]['pii']).not_to include('address2')
    end
  end

  describe '#authorizable?' do
    it 'is true once, for the same issuer only' do
      start!

      expect(handoff.authorizable?('urn:other')).to eq(false)
      expect(handoff.authorizable?(issuer)).to eq(true)

      handoff.mark_authorized!

      expect(handoff.authorizable?(issuer)).to eq(false)
      expect(handoff.present_for?(issuer)).to eq(true)
    end

    it 'is false without a handoff' do
      expect(handoff.authorizable?(issuer)).to eq(false)
    end
  end

  describe '.authorized_data_from_user_session' do
    it 'returns data only after authorization, for the matching issuer' do
      start!
      expect(described_class.authorized_data_from_user_session(user_session, issuer:)).to be_nil

      handoff.mark_authorized!

      expect(described_class.authorized_data_from_user_session(user_session, issuer:))
        .to include('issuer' => issuer)
      expect(described_class.authorized_data_from_user_session(user_session, issuer: 'urn:other'))
        .to be_nil
      expect(described_class.authorized_data_from_user_session(nil, issuer:)).to be_nil
    end
  end

  describe 'session encryption' do
    it 'KMS-encrypts the handoff in the stored session' do
      start!
      session = { 'warden.user.user.session' => user_session.to_h }.deep_dup
      dumped = SessionEncryptor.new.dump(session)
      outer = SessionEncryptor.new.send(:outer_decrypt, MessagePack.unpack(dumped)['t'])
      outer = Zlib.gunzip(outer) if MessagePack.unpack(dumped)['c'] == 1

      expect(outer).not_to include(pii[:last_name])
      expect(outer).not_to include('900-12-3456')

      loaded = SessionEncryptor.new.load(dumped)
      expect(loaded.dig('warden.user.user.session', described_class::SESSION_KEY, 'pii', 'ssn'))
        .to eq('900-12-3456')
    end
  end
end
