require 'rails_helper'

RSpec.describe OpenidConnectUserInfoPresenter, 'with an unresolved IdV handoff' do
  let(:rails_session_id) { SecureRandom.uuid }
  let(:scope) { 'openid email address phone profile social_security_number' }
  let(:service_provider) { create(:service_provider, ial: 2) }
  let(:allowed_issuers) { [service_provider.issuer] }
  let(:profiles) { [] }
  let(:user) { create(:user, profiles:) }
  let(:session_accessor) { OutOfBandSessionAccessor.new(rails_session_id) }
  let(:identity) do
    build(
      :service_provider_identity,
      rails_session_id:,
      user:,
      service_provider: service_provider.issuer,
      scope:,
      acr_values: Saml::Idp::Constants::IAL_VERIFIED_FACIAL_MATCH_REQUIRED_ACR,
      ial: 1,
      access_token: SecureRandom.urlsafe_base64,
    )
  end
  let(:handoff_issuer) { service_provider.issuer }
  let(:authorized_at) { Time.zone.now.iso8601 }
  let(:handoff) do
    {
      'issuer' => handoff_issuer,
      'pii' => {
        'first_name' => 'Jane',
        'last_name' => 'Doe',
        'dob' => '1980-01-01',
        'ssn' => '900123456',
        'address1' => '123 Main St',
        'city' => 'Nowhere',
        'state' => 'VA',
        'zipcode' => '00000',
      },
      'verification_status' => Idv::UnresolvedHandoff.verification_status(
        document_type: 'passport',
        source_check_vendor: 'dos:passport',
      ),
      'authorized_at' => authorized_at,
    }
  end

  before do
    allow(IdentityConfig.store).to receive(:idv_unresolved_handoff_allowed_issuers)
      .and_return(allowed_issuers)
    # A separate accessor: each one caches the session it first reads.
    OutOfBandSessionAccessor.new(rails_session_id).put_unresolved_idv_handoff(handoff)
  end

  subject(:user_info) do
    OpenidConnectUserInfoPresenter.new(identity, session_accessor:).user_info
  end

  it 'releases the handoff PII with the unresolved acr and verification status' do
    expect(user_info).to include(
      given_name: 'Jane',
      family_name: 'Doe',
      birthdate: '1980-01-01',
      social_security_number: '900123456',
      ial: Idv::UnresolvedHandoff::ACR,
      verified_at: nil,
    )
    expect(user_info[:address]).to include(street_address: '123 Main St', postal_code: '00000')
    expect(user_info[:verification_status]).to include('identity_resolution' => 'failed')
    expect(user_info[:phone]).to be_nil
  end

  it 'puts the unresolved acr in the ID token' do
    id_token = IdTokenBuilder.new(identity:, code: SecureRandom.hex).id_token
    payload, = JWT.decode(
      id_token, AppArtifacts.store.oidc_primary_public_key, true,
      algorithm: 'RS256'
    )

    expect(payload['acr']).to eq(Idv::UnresolvedHandoff::ACR)
    expect(payload['verification_status']).to include('identity_resolution' => 'failed')
  end

  shared_examples 'an ordinary unverified user' do
    it 'releases no PII, no verification status and no unresolved acr' do
      expect(user_info).not_to include(:given_name, :social_security_number, :verification_status)
      expect(user_info[:ial]).not_to eq(Idv::UnresolvedHandoff::ACR)
    end
  end

  context 'when the service provider is not allowlisted' do
    let(:allowed_issuers) { [] }
    it_behaves_like 'an ordinary unverified user'
  end

  context 'when the handoff belongs to another service provider' do
    let(:handoff_issuer) { 'urn:gov:gsa:openidconnect:sp:other' }
    it_behaves_like 'an ordinary unverified user'
  end

  context 'when the handoff was never authorized' do
    let(:authorized_at) { nil }
    it_behaves_like 'an ordinary unverified user'
  end

  context 'when the user has since verified their identity' do
    let(:profiles) { [create(:profile, :active, :verified, :facial_match_proof)] }

    it 'uses the verified profile instead' do
      expect(user_info).not_to include(:verification_status)
      expect(user_info[:ial]).not_to eq(Idv::UnresolvedHandoff::ACR)
    end
  end
end
