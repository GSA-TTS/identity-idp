# frozen_string_literal: true

class AddLookupIndexesToAccountRecoveryRequests < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    # Recovery link redemption looks a request up by token fingerprint alone.
    add_index :account_recovery_requests, :token_fingerprint,
              unique: true,
              where: 'token_fingerprint IS NOT NULL',
              algorithm: :concurrently,
              if_not_exists: true

    # GrantAccountRecoveryRequestsAndSendEmailsJob polls waiting requests every few minutes.
    add_index :account_recovery_requests, %i[state requested_at],
              algorithm: :concurrently,
              if_not_exists: true
  end
end
