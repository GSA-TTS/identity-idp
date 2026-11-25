require 'rails_helper'

RSpec.describe IdvResolutionStepdownConcern do
  controller ApplicationController do
    include IdvResolutionStepdownConcern
  end
  let(:user) { create(:user) }
  before do
    stub_sign_in(user)
    allow(controller).to receive(:resolved_authn_context_result)
      .and_return(authn_context_result)
  end

  let(:issuer) { 'urn:gov:gsa:openidconnect:test' }
  let(:service_provider) { build(:service_provider, issuer:) }
  let(:authn_context_result) do
    instance_double(
      Component::Parser::Result,
      idv_resolution_stepdown_eligible?: idv_resolution_stepdown_eligible,
    )
  end
  let(:encrypted_pii) do
    SessionEncryptor.new.kms_encrypt({ first_name: 'Jane' }.to_json)
  end

  describe '#request_has_stepped_down?' do
    subject(:request_has_stepped_down) { controller.request_has_stepped_down? }

    context 'when request is stepdown eligible' do
      let(:idv_resolution_stepdown_eligible) { true }

      context 'with stored data' do
        before do
          controller.user_session[:idv_resolution_stepdown] = {
            issuer:,
            encrypted_pii:,
          }
        end

        it 'returns true' do
          expect(request_has_stepped_down).to be true
        end
      end

      context 'without stored data' do
        it 'returns false' do
          expect(request_has_stepped_down).to be false
        end
      end
    end

    context 'without resolver eligibility' do
      let(:idv_resolution_stepdown_eligible) { false }

      before do
        controller.user_session[:idv_resolution_stepdown] = {
          issuer:,
          encrypted_pii:,
        }
      end

      it 'returns false' do
        expect(controller.request_has_stepped_down?).to be false
      end
    end
  end

  describe '#idv_resolution_stepdown_pii' do
    subject(:idv_resolution_stepdown_pii) { controller.idv_resolution_stepdown_pii }
    let(:idv_resolution_stepdown_eligible) { true }

    context 'with stored data' do
      before do
        controller.user_session[:idv_resolution_stepdown] = {
          issuer:,
          encrypted_pii:,
        }
        allow(controller).to receive(:current_sp).and_return service_provider
      end

      it 'returns decrypted PII' do
        expect(idv_resolution_stepdown_pii.first_name).to eq('Jane')
      end

      context 'with another issuer' do
        before do
          controller.user_session[:idv_resolution_stepdown] = {
            issuer: 'urn:gov:gsa:openidconnect:other',
            encrypted_pii:,
          }
        end

        it 'returns false' do
          expect(idv_resolution_stepdown_pii).to be nil
        end
      end

      context 'without encrypted PII' do
        before do
          controller.user_session[:idv_resolution_stepdown] = {
            issuer:,
            encrypted_pii: nil,
          }
        end

        it 'returns false' do
          expect(idv_resolution_stepdown_pii).to be nil
        end
      end
    end
  end
end
