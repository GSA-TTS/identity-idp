# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Site key + OIDC PKCE + DPoP 3-PR stack flow', type: :request do
  let(:password) { RequestHelper::VALID_PASSWORD }
  let(:user) { create(:user, :with_authentication_app, password:) }
  let(:redirect_uri) { 'https://america.gov/auth/callback' }
  let(:service_provider) do
    create(
      :service_provider,
      :active,
      issuer: 'urn:gov:gsa:openidconnect:sp:america_gov_mock',
      pkce: true,
      ial: 1,
      redirect_uris: [redirect_uri],
    )
  end

  let(:dpop_key_device_1) { OpenSSL::PKey::EC.generate('prime256v1') }
  let(:dpop_key_device_2) { OpenSSL::PKey::EC.generate('prime256v1') }

  before do
    allow_site_keys_for(service_provider)
    allow(IdentityConfig.store).to receive(:openid_connect_redirect).and_return('server_side')
  end

  def pkce_pair
    verifier = SecureRandom.urlsafe_base64(32)
    challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
    [verifier, challenge]
  end

  def complete_2fa(target_user)
    travel 35.seconds
    totp_code = ROTP::TOTP.new(
      target_user.auth_app_configurations.first.otp_secret_key,
      interval: IdentityConfig.store.totp_code_interval,
    ).now
    post login_two_factor_authenticator_path, params: { code: totp_code }
  end

  # Follows Login.gov redirects from /openid_connect/authorize until the RP callback URL is reached,
  # handling password capture (#13802) and first-visit SP consent automatically.
  def complete_authorize_and_extract_code(
    authorize_params,
    user_password:,
    target_redirect: redirect_uri
  )
    visited_paths = []
    consent_html = nil
    get openid_connect_authorize_path, params: authorize_params

    10.times do
      break if response.redirect? && response.location.start_with?(target_redirect)

      follow_redirect! if response.redirect?
      visited_paths << request.path

      case request.path
      when capture_password_path
        post capture_password_path, params: { user: { password: user_password } }
      when sign_up_completed_path
        consent_html = response.body
        post sign_up_completed_path
      when user_authorization_confirmation_path
        post user_authorization_confirmation_path
      end
    end

    expect(response).to be_redirect
    expect(response.location).to start_with(target_redirect)
    code = Rack::Utils.parse_query(URI.parse(response.location).query).fetch('code')
    { code:, visited_paths:, consent_html: }
  end

  def authorize_params_for(
    client_dpop_key:,
    code_challenge:,
    issuer: service_provider.issuer,
    callback_uri: redirect_uri,
    scope: 'openid email site_key'
  )
    {
      client_id: issuer,
      response_type: 'code',
      acr_values: Saml::Idp::Constants::IAL_AUTH_ONLY_ACR,
      scope:,
      redirect_uri: callback_uri,
      state: SecureRandom.hex(16),
      nonce: SecureRandom.hex(16),
      code_challenge:,
      code_challenge_method: 'S256',
      dpop_jkt: dpop_thumbprint(client_dpop_key),
    }
  end

  def exchange_token_and_fetch_userinfo(code:, code_verifier:, client_dpop_key:)
    post api_openid_connect_token_path,
         params: {
           grant_type: 'authorization_code',
           code:,
           code_verifier:,
         },
         headers: {
           'DPoP' => build_dpop_proof(
             http_url: api_openid_connect_token_url,
             http_method: 'POST',
             key: client_dpop_key,
           ),
         }

    expect(response).to have_http_status(:ok)
    token_body = JSON.parse(response.body)
    expect(token_body['token_type']).to eq('DPoP')
    access_token = token_body.fetch('access_token')

    get api_openid_connect_userinfo_path,
        headers: {
          'Authorization' => "DPoP #{access_token}",
          'DPoP' => build_dpop_proof(
            http_url: api_openid_connect_userinfo_url,
            http_method: 'GET',
            key: client_dpop_key,
            access_token:,
          ),
        }

    expect(response).to have_http_status(:ok)
    { access_token:, userinfo: JSON.parse(response.body) }
  end

  def run_mock_rp_signin(
    client_dpop_key:,
    user_password: password,
    sp: service_provider,
    callback_uri: redirect_uri,
    scope: 'openid email site_key'
  )
    code_verifier, code_challenge = pkce_pair
    params = authorize_params_for(
      client_dpop_key:,
      code_challenge:,
      issuer: sp.issuer,
      callback_uri:,
      scope:,
    )

    get openid_connect_authorize_path, params: params
    expect(response).to redirect_to(new_user_session_url)

    post new_user_session_path, params: { user: { email: user.email, password: user_password } }
    complete_2fa(user)

    handoff = complete_authorize_and_extract_code(
      params,
      user_password:,
      target_redirect: callback_uri,
    )
    result = exchange_token_and_fetch_userinfo(
      code: handoff[:code],
      code_verifier:,
      client_dpop_key:,
    )
    result.merge(handoff.slice(:visited_paths, :consent_html))
  end

  # Opens the site_key compact JWE exactly as America.gov's browser would via ECDH-ES + AES-256-GCM.
  def open_site_key_jwe(sealed, recipient_key:, client_id: service_provider.issuer)
    header_b64, _cek, iv_b64, ct_b64, tag_b64 = sealed.split('.')
    header = JSON.parse(Base64.urlsafe_decode64(header_b64))
    epk = JWT::JWK.import(header['epk'].transform_keys(&:to_sym)).verify_key
    shared = recipient_key.dh_compute_key(epk.public_key)
    other = [header['enc'].bytesize].pack('N') + header['enc'] + [0].pack('N') +
            [client_id.bytesize].pack('N') + client_id + [256].pack('N')
    cek = OpenSSL::Digest::SHA256.digest([1].pack('N') + shared + other)[0, 32]
    cipher = OpenSSL::Cipher.new('aes-256-gcm').decrypt
    cipher.key = cek
    cipher.iv = Base64.urlsafe_decode64(iv_b64)
    cipher.auth_tag = Base64.urlsafe_decode64(tag_b64)
    cipher.auth_data = header_b64
    JSON.parse(cipher.update(Base64.urlsafe_decode64(ct_b64)) + cipher.final)
  end

  describe '3-PR stack (#13801, #13802, #13804)' do
    it 'creates, seals to DPoP, skips consent disclosure, and releases the key across devices' do
      device_1 = run_mock_rp_signin(client_dpop_key: dpop_key_device_1)

      expect(device_1[:consent_html]).to include(t('help_text.requested_attributes.email'))
      expect(device_1[:consent_html]).not_to include('Site Key')

      userinfo_1 = device_1[:userinfo]
      expect(userinfo_1['site_key']).to be_present
      expect(userinfo_1['site_key_public']).to eq(JSON.parse(user.reload.site_key.public_key))

      # Only Device 1's browser DPoP key + client_id can unseal the JWE
      private_jwk_1 = open_site_key_jwe(userinfo_1['site_key'], recipient_key: dpop_key_device_1)
      expect(private_jwk_1).to include(userinfo_1['site_key_public'])
      expect(private_jwk_1['d']).to be_present

      expect do
        open_site_key_jwe(userinfo_1['site_key'], recipient_key: dpop_key_device_2)
      end.to raise_error(OpenSSL::Cipher::CipherError)
      expect do
        open_site_key_jwe(
          userinfo_1['site_key'],
          recipient_key: dpop_key_device_1,
          client_id: 'urn:gov:gsa:openidconnect:sp:other_rp',
        )
      end.to raise_error(OpenSSL::Cipher::CipherError)

      # Device 2 signs in with a fresh browser session and fresh DPoP keypair
      reset!
      device_2 = run_mock_rp_signin(client_dpop_key: dpop_key_device_2)
      private_jwk_2 = open_site_key_jwe(
        device_2[:userinfo]['site_key'],
        recipient_key: dpop_key_device_2,
      )
      expect(private_jwk_2).to eq(private_jwk_1)
    end

    it 'prompts for password once when an SSO session requests site_key without a password' do
      device_1 = run_mock_rp_signin(client_dpop_key: dpop_key_device_1)
      expected_jwk = open_site_key_jwe(
        device_1[:userinfo]['site_key'],
        recipient_key: dpop_key_device_1,
      )

      # Fresh session where user signs in directly to Login.gov (not through listed SP)
      reset!
      post new_user_session_path, params: { user: { email: user.email, password: } }
      complete_2fa(user)

      code_verifier, code_challenge = pkce_pair
      params = authorize_params_for(client_dpop_key: dpop_key_device_2, code_challenge:)
      handoff = complete_authorize_and_extract_code(params, user_password: password)

      expect(handoff[:visited_paths]).to include(capture_password_path)
      device_2 = exchange_token_and_fetch_userinfo(
        code: handoff[:code],
        code_verifier:,
        client_dpop_key: dpop_key_device_2,
      )
      unsealed_2 = open_site_key_jwe(
        device_2[:userinfo]['site_key'],
        recipient_key: dpop_key_device_2,
      )
      expect(unsealed_2).to eq(expected_jwk)
    end

    it 'destroys the site key on password reset and issues a fresh key on the next SP sign-in' do
      device_1 = run_mock_rp_signin(client_dpop_key: dpop_key_device_1)
      old_public = device_1[:userinfo]['site_key_public']

      new_password = 'N3w Strong Passw0rd!'
      user.update!(reset_password_sent_at: Time.zone.now)
      expect(
        ResetPasswordForm.new(user:).submit(
          password: new_password,
          password_confirmation: new_password,
        ).success?,
      ).to eq(true)
      expect(user.reload.site_key).to be_nil

      reset!
      device_2 = run_mock_rp_signin(
        client_dpop_key: dpop_key_device_2,
        user_password: new_password,
      )
      expect(user.reload.site_key).to be_present
      expect(device_2[:userinfo]['site_key_public']).not_to eq(old_public)
    end

    it 'unlocks and rewraps a locked site key on auth-only password change' do
      device_1 = run_mock_rp_signin(client_dpop_key: dpop_key_device_1)
      expected_jwk = open_site_key_jwe(
        device_1[:userinfo]['site_key'],
        recipient_key: dpop_key_device_1,
      )

      # Auth-only user signs in directly to Login.gov (site key is locked in this session)
      reset!
      post new_user_session_path, params: { user: { email: user.email, password: } }
      complete_2fa(user)

      # Visiting /manage/password prompts for current password first so the key can be unwrapped
      get manage_password_path
      expect(response).to redirect_to(capture_password_url)

      post capture_password_path, params: { user: { password: } }
      expect(response).to redirect_to(manage_password_url)

      new_password = 'N3w Strong Passw0rd!'
      patch manage_password_path, params: {
        update_user_password_form: { password: new_password, password_confirmation: new_password },
      }
      expect(response).to redirect_to(account_path)

      # Next SP sign-in unlocks with the new password directly
      reset!
      device_2 = run_mock_rp_signin(
        client_dpop_key: dpop_key_device_2,
        user_password: new_password,
      )
      expect(device_2[:visited_paths]).not_to include(capture_password_path)
      unsealed_2 = open_site_key_jwe(
        device_2[:userinfo]['site_key'],
        recipient_key: dpop_key_device_2,
      )
      expect(unsealed_2).to eq(expected_jwk)
    end

    it 'omits site_key at /userinfo when another SP session replaced the key' do
      second_redirect_uri = 'https://other.gov/auth/callback'
      second_sp = create(
        :service_provider,
        :active,
        issuer: 'urn:gov:gsa:openidconnect:sp:other_gov_mock',
        pkce: true,
        ial: 1,
        redirect_uris: [second_redirect_uri],
      )
      allow(IdentityConfig.store).to receive(:site_key_allowed_issuers)
        .and_return([service_provider.issuer, second_sp.issuer])
      allow(IdentityConfig.store).to receive(:dpop_required_issuers)
        .and_return([service_provider.issuer, second_sp.issuer])

      # Device 1 signs into SP #1 and retains a live DPoP-bound access_token
      device_1 = run_mock_rp_signin(client_dpop_key: dpop_key_device_1)
      key_1_public = device_1[:userinfo]['site_key_public']

      # Device 2 resets password (destroying Key 1) and creates Key 2 via SP #2
      new_password = 'N3w Strong Passw0rd!'
      user.update!(reset_password_sent_at: Time.zone.now)
      expect(
        ResetPasswordForm.new(user:).submit(
          password: new_password,
          password_confirmation: new_password,
        ).success?,
      ).to eq(true)

      reset!
      device_2 = run_mock_rp_signin(
        client_dpop_key: dpop_key_device_2,
        user_password: new_password,
        sp: second_sp,
        callback_uri: second_redirect_uri,
      )
      expect(device_2[:userinfo]['site_key_public']).not_to eq(key_1_public)

      # Device 1's still-valid access_token calls /userinfo -> must omit stale site_key
      get api_openid_connect_userinfo_path,
          headers: {
            'Authorization' => "DPoP #{device_1[:access_token]}",
            'DPoP' => build_dpop_proof(
              http_url: api_openid_connect_userinfo_url,
              http_method: 'GET',
              key: dpop_key_device_1,
              access_token: device_1[:access_token],
            ),
          }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['email']).to eq(user.email)
      expect(body).not_to have_key('site_key')
      expect(body).not_to have_key('site_key_public')
    end
  end
end
