require 'rails_helper'

RSpec.describe Idv::UnresolvedHandoffController do
  let(:user) { create(:user, :fully_registered) }
  let(:service_provider) { create(:service_provider, :active, ial: 2) }
  let(:allowed_issuers) { [service_provider.issuer] }
  let(:request_url) do
    "http://www.example.com/openid_connect/authorize?client_id=#{service_provider.issuer}"
  end
  let(:acr_values) { Saml::Idp::Constants::IAL_VERIFIED_FACIAL_MATCH_REQUIRED_ACR }
  let(:eligible) { true }

  before do
    allow(IdentityConfig.store).to receive(:idv_unresolved_handoff_allowed_issuers)
      .and_return(allowed_issuers)
    stub_sign_in(user)
    stub_analytics
    session[:sp] = { issuer: service_provider.issuer, request_url:, acr_values: }

    subject.idv_session.pii_from_doc = Pii::Passport.new(
      **Idp::Constants::MOCK_IDV_APPLICANT_WITH_PASSPORT.slice(*Pii::Passport.members),
    )
    subject.idv_session.ssn = '900-12-3456'
    subject.idv_session.updated_user_address = Pii::Address.new(
      address1: '123 Main St', address2: nil, city: 'Nowhere', state: 'VA', zipcode: '00000',
    )
    subject.idv_session.source_check_vendor = 'dos:passport'
    subject.idv_session.selfie_check_performed = true
    subject.idv_session.unresolved_handoff_eligible = eligible
  end

  shared_examples 'not offered' do
    it 'redirects to the start of verification' do
      get :show

      expect(response).to redirect_to(idv_url)
    end
  end

  describe '#show' do
    it 'renders the consent page' do
      get :show

      expect(response).to render_template(:show)
      expect(@analytics).to have_logged_event(:idv_unresolved_handoff_visited)
    end

    context 'when resolution did not record eligibility' do
      let(:eligible) { false }
      it_behaves_like 'not offered'
    end

    context 'when the service provider is not allowlisted' do
      let(:allowed_issuers) { [] }
      it_behaves_like 'not offered'
    end

    context 'when facial match was not requested' do
      let(:acr_values) { Saml::Idp::Constants::IAL_VERIFIED_ACR }
      it_behaves_like 'not offered'
    end

    context 'when the request is SAML' do
      let(:request_url) { 'http://www.example.com/api/saml/auth2025' }
      it_behaves_like 'not offered'
    end
  end

  describe '#create' do
    let(:handoff) { controller.user_session[Idv::UnresolvedHandoff::SESSION_KEY] }

    context 'without consent' do
      it 're-renders the page and starts no handoff' do
        post :create, params: { unresolved_handoff: { consent_given: '0' } }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response).to render_template(:show)
        expect(handoff).to be_nil
        expect(@analytics).to have_logged_event(
          :idv_unresolved_handoff_submitted,
          success: false,
          error_details: { consent_given: { accepted: true } },
        )
      end
    end

    context 'with consent' do
      it 'starts the handoff, discards the verification and returns to the service provider' do
        post :create, params: { unresolved_handoff: { consent_given: '1' } }

        expect(response).to redirect_to(request_url)
        expect(handoff['issuer']).to eq(service_provider.issuer)
        expect(handoff['pii']).to include(
          'first_name' => Idp::Constants::MOCK_IDV_APPLICANT_WITH_PASSPORT[:first_name],
          'ssn' => '900-12-3456',
          'address1' => '123 Main St',
          'zipcode' => '00000',
        )
        expect(handoff['verification_status']['document']).to include(
          'type' => Idp::Constants::DocumentTypes::PASSPORT,
          'issuer_check_source' => 'state_department',
        )
        expect(handoff['verification_status']['self_asserted'])
          .to eq(%w[social_security_number address])
        expect(controller.user_session[:idv]).to be_blank
        expect(user.reload.active_profile).to be_nil
        expect(@analytics).to have_logged_event(
          :idv_unresolved_handoff_submitted,
          success: true,
        )
      end
    end

    context 'with a state ID whose address came from the document' do
      before do
        subject.idv_session.pii_from_doc = Pii::StateId.new(
          **Idp::Constants::MOCK_IDV_APPLICANT.slice(*Pii::StateId.members),
        )
        subject.idv_session.updated_user_address = nil
        subject.idv_session.source_check_vendor = DocAuth::Aamva::Proofer::VENDOR_NAME
      end

      it 'shares the document address and marks only the SSN as self-asserted' do
        post :create, params: { unresolved_handoff: { consent_given: '1' } }

        expect(response).to redirect_to(request_url)
        expect(handoff['pii']).to include(
          'address1' => Idp::Constants::MOCK_IDV_APPLICANT[:address1],
          'zipcode' => Idp::Constants::MOCK_IDV_APPLICANT[:zipcode],
        )
        expect(handoff['verification_status']['document']).to include(
          'type' => Idp::Constants::MOCK_IDV_APPLICANT[:document_type_received],
          'issuer_check_source' => 'aamva',
        )
        expect(handoff['verification_status']['self_asserted']).to eq(['social_security_number'])
      end
    end

    context 'when not eligible' do
      let(:eligible) { nil }

      it 'starts no handoff' do
        post :create, params: { unresolved_handoff: { consent_given: '1' } }

        expect(response).to redirect_to(idv_url)
        expect(handoff).to be_nil
      end
    end
  end
end
