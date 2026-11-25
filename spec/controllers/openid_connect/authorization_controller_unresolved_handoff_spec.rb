require 'rails_helper'

RSpec.describe OpenidConnect::AuthorizationController, 'with an unresolved IdV handoff' do
  let(:client_id) { 'urn:gov:gsa:openidconnect:test' }
  let(:allowed_issuers) { [client_id] }
  let(:acr_values) { Saml::Idp::Constants::IAL_VERIFIED_FACIAL_MATCH_REQUIRED_ACR }
  let(:scope) { 'openid profile social_security_number' }
  let(:user) { create(:user, :fully_registered) }
  let(:handoff_issuer) { client_id }
  let(:authorized_at) { nil }
  let(:params) do
    {
      acr_values:,
      client_id:,
      nonce: SecureRandom.hex,
      prompt: 'select_account',
      redirect_uri: 'gov.gsa.openidconnect.test://result',
      response_type: 'code',
      scope:,
      state: SecureRandom.hex,
    }
  end

  before do
    allow(controller).to receive(:auth_count).and_return(2)
    allow(IdentityConfig.store).to receive(:openid_connect_redirect).and_return('server_side')
    allow(IdentityConfig.store).to receive(:idv_unresolved_handoff_allowed_issuers)
      .and_return(allowed_issuers)
    stub_sign_in(user)
    stub_analytics
    controller.user_session[Idv::UnresolvedHandoff::SESSION_KEY] = {
      'issuer' => handoff_issuer,
      'pii' => { 'first_name' => 'Jane', 'ssn' => '900123456' },
      'verification_status' => { 'identity_resolution' => 'failed' },
      'authorized_at' => authorized_at,
    }
  end

  subject(:action) { get :index, params: }

  let(:handoff) { controller.user_session[Idv::UnresolvedHandoff::SESSION_KEY] }
  let(:identity) { user.identities.find_by(service_provider: client_id) }

  it 'issues a code to the service provider once, linked and billed as IAL1' do
    action

    expect(response).to redirect_to(%r{\Agov.gsa.openidconnect.test://result\?code=})
    expect(handoff['authorized_at']).to be_present
    expect(identity.ial).to eq(1)
    expect(identity.verified_at).to be_nil
    expect(identity.rails_session_id).to eq(session.id.to_s)
    expect(SpReturnLog.find_by(issuer: client_id, user:).ial).to eq(1)
    expect(@analytics).to have_logged_event(:idv_unresolved_handoff_authorized, success: true)
    expect(user.reload.active_profile).to be_nil
  end

  shared_examples 'sends the user to verification' do
    it 'redirects to IdV' do
      action

      expect(response).to redirect_to(idv_url)
      expect(@analytics).not_to have_logged_event(:idv_unresolved_handoff_authorized)
    end
  end

  context 'when the handoff was already used' do
    let(:authorized_at) { Time.zone.now.iso8601 }

    it_behaves_like 'sends the user to verification'

    it 'clears the used handoff' do
      action

      expect(handoff).to be_nil
    end
  end

  context 'when the handoff is for another service provider' do
    let(:handoff_issuer) { 'urn:gov:gsa:openidconnect:sp:other' }
    it_behaves_like 'sends the user to verification'
  end

  context 'when the service provider is not allowlisted' do
    let(:allowed_issuers) { [] }
    it_behaves_like 'sends the user to verification'
  end

  context 'when facial match is not requested' do
    let(:acr_values) { Saml::Idp::Constants::IAL_VERIFIED_ACR }
    it_behaves_like 'sends the user to verification'
  end
end
