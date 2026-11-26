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

  describe '#idv_resolution_stepdown_time' do
    subject(:idv_resolution_stepdown_time) { controller.idv_resolution_stepdown_time }
    let(:idv_resolution_stepdown_eligible) { true }
    let(:stepped_down_at) { Time.zone.parse('2026-11-25T14:30:00Z') }

    before do
      controller.user_session[:idv_resolution_stepdown] = {
        issuer: stored_issuer,
        encrypted_pii:,
        stepped_down_at: stepped_down_at&.iso8601,
      }
      allow(controller).to receive(:current_sp).and_return service_provider
    end

    context 'when the person stepped down for the current service provider' do
      let(:stored_issuer) { issuer }

      it 'returns the time of the step-down' do
        expect(idv_resolution_stepdown_time).to eq(stepped_down_at)
      end
    end

    context 'when the person stepped down for another service provider' do
      let(:stored_issuer) { 'urn:gov:gsa:openidconnect:other' }

      it 'returns nil' do
        expect(idv_resolution_stepdown_time).to be_nil
      end
    end

    context 'when the stored step-down has no time' do
      let(:stored_issuer) { issuer }
      let(:stepped_down_at) { nil }

      it 'returns nil' do
        expect(idv_resolution_stepdown_time).to be_nil
      end
    end
  end
end
