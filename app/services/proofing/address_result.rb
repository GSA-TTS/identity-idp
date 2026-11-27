# frozen_string_literal: true

module Proofing
  class AddressResult
    attr_reader :success,
                :errors,
                :exception,
                :vendor_name,
                :transaction_id,
                :reference,
                :vendor_workflow,
                :result,
                :dual_vendor_check_eligible,
                :vendor_verified

    def initialize(
      success:,
      vendor_name:,
      vendor_verified:,
      exception: nil,
      errors: {},
      transaction_id: '',
      reference: '',
      vendor_workflow: nil,
      result: nil,
      dual_vendor_check_eligible: false
    )
      @success = success
      @errors = errors
      @exception = exception
      @vendor_name = vendor_name
      @transaction_id = transaction_id
      @reference = reference
      @vendor_workflow = vendor_workflow
      @result = result
      @dual_vendor_check_eligible = dual_vendor_check_eligible
      @vendor_verified = vendor_verified
    end

    def success?
      success
    end

    def timed_out?
      exception.is_a?(Proofing::TimeoutError)
    end

    def to_h
      {
        exception:,
        errors:,
        success: success?,
        timed_out: timed_out?,
        transaction_id:,
        reference:,
        vendor_name:,
        result:,
        vendor_verified:,
      }
    end
  end
end
