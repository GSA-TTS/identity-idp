# frozen_string_literal: true

module Proofing
  module Resolution
    # Decides whether identity resolution passed, and why, from the resolution results alone.
    # ResultAdjudicator combines this decision with device profiling to adjudicate the full result,
    # and failover uses it to decide whether to try the next vendor.
    class ResolutionDecision
      attr_reader :resolution_result,
                  :residential_resolution_result,
                  :ipp_enrollment_in_progress,
                  :ipp_current_address_matches_id,
                  :applicant_pii,
                  :proofing_vendor,
                  :resolution_bypassed

      def initialize(
        resolution_result:,
        residential_resolution_result:,
        ipp_enrollment_in_progress:,
        ipp_current_address_matches_id:,
        applicant_pii:,
        proofing_vendor: nil,
        resolution_bypassed: false
      )
        @resolution_result = resolution_result
        @residential_resolution_result = residential_resolution_result
        @ipp_enrollment_in_progress = ipp_enrollment_in_progress
        @ipp_current_address_matches_id = ipp_current_address_matches_id
        @applicant_pii = applicant_pii
        @proofing_vendor = proofing_vendor
        @resolution_bypassed = resolution_bypassed
      end

      def success?
        success_and_reason.first
      end

      def reason
        success_and_reason.last
      end

      # Reports the attributes AAMVA verified that were usable for this decision, so the logs
      # match the coverage decision rather than the raw AAMVA response.
      def passed_state_id_attributes
        attributes = applicant_pii[:aamva_verified_attributes].to_a
        return attributes unless applicant_pii[:address_edited] == true

        # AAMVA verifies the address printed on the identity document. If the user edited their
        # address afterwards, resolution proofed a different address than the one AAMVA verified,
        # so the AAMVA response can no longer cover an address failure.
        attributes.reject { |attribute| attribute.to_sym == :address }
      end

      private

      def success_and_reason
        @success_and_reason ||=
          # This branch is IPP-specific: only the in-person flow resolves a separate
          # residential address (ResidentialAddressPlugin returns an automatic success
          # when not in IPP). When the residential address differs from the ID address
          # and its resolution fails, fail here rather than crediting the state-ID
          # (document) address resolution. This does not apply to non-IPP flows because
          # they never run a separate residential resolution.
          if ipp_enrollment_in_progress && !residential_resolution_result.success? &&
             ipp_current_address_matches_id == false
            [false, :fail_resolution_skip_state_id]
          elsif resolution_bypassed
            [true, :instant_verify_bypass]
          elsif resolution_result.success?
            [true, :pass_resolution_and_state_id]
          elsif state_id_attributes_cover_resolution_failures?
            [true, :state_id_covers_failed_resolution]
          else
            [false, :fail_resolution_without_state_id_coverage]
          end
      end

      def state_id_attributes_cover_resolution_failures?
        return false unless get_to_yes_enabled_for_vendor?
        return false unless resolution_result.failed_result_can_pass_with_additional_verification?

        failed_resolution_attributes =
          resolution_result.attributes_requiring_additional_verification
        (failed_resolution_attributes.to_a - passed_state_id_attributes.map(&:to_sym)).empty?
      end

      # The "get to yes" feature is enabled per resolution vendor, since each vendor reports failed
      # attributes differently. A nil vendor won't match the allowlist, so it stays disabled.
      def get_to_yes_enabled_for_vendor?
        IdentityConfig.store.idv_aamva_get_to_yes_enabled_vendors
          .include?(proofing_vendor.to_s)
      end
    end
  end
end
