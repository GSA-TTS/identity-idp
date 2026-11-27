require 'rails_helper'

RSpec.describe Test::AccountRecoveryController do
  let(:user) { create(:user, :fully_registered) }

  describe '#index' do
    render_views

    it 'offers cancel and expire only for requests that can still be ended' do
      cancellable = create(:account_recovery_request, :granted, user: user)
      suspended = create(:account_recovery_request, :replacement_mfa_pending, user: create(:user))

      get :index

      expect(response.body).to include(test_account_recovery_cancel_path(id: cancellable.id))
      expect(response.body).to include(test_account_recovery_expire_path(id: cancellable.id))
      expect(response.body).not_to include(test_account_recovery_cancel_path(id: suspended.id))
      expect(response.body).not_to include(test_account_recovery_expire_path(id: suspended.id))
      expect(response.body).to include(test_account_recovery_destroy_path(id: suspended.id))
    end
  end

  %i[cancel expire].each do |action|
    describe "##{action}" do
      it 'ends a request that has not suspended the existing MFA methods' do
        recovery_request = create(:account_recovery_request, :granted, user: user)

        post action, params: { id: recovery_request.id }

        expect(response).to redirect_to(test_account_recovery_url)
        expect(flash[:error]).to be_nil
        expect(recovery_request.reload).to be_terminal
      end

      it 'leaves a request that has suspended the existing MFA methods in flight' do
        recovery_request = create(:account_recovery_request, :password_verified, user: user)
        AccountRecovery::SuspendExistingMfa.new(account_recovery_request: recovery_request).call

        post action, params: { id: recovery_request.id }

        expect(response).to redirect_to(test_account_recovery_url)
        expect(flash[:error]).to include(AccountRecoveryRequest::REPLACEMENT_MFA_PENDING)
        expect(recovery_request.reload).to be_replacement_mfa_pending
        expect(user.phone_configurations.first).to be_suspended_for_account_recovery
      end
    end
  end
end
