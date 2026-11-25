# frozen_string_literal: true

module Idv
  # Decides whether a user whose identity resolution (verify info) just failed may continue to
  # their service provider without a verified profile, carrying a "document verified, identity
  # unresolved" result instead of IAL2.
  #
  # Every condition must hold. The document must be fully proven: authenticity and selfie match
  # from the document vendor, plus its issuer's source check (the State Department MRZ check for
  # passports, AAMVA for driver's licenses and state IDs). The only thing that failed must be the
  # vendor's records match. Device risk, vendor exceptions and SSN lockouts never qualify.
  class UnresolvedHandoffEligibility
    attr_reader :idv_session, :service_provider, :resolved_authn_context_result, :failures

    # @param idv_session [Idv::Session]
    # @param service_provider [ServiceProvider, nil]
    # @param resolved_authn_context_result [Vot::Parser::Result]
    # @param failures [Idv::VerifyInfoConcern::VerificationFailures]
    # @param ssn_rate_limited [Boolean]
    def initialize(idv_session:, service_provider:, resolved_authn_context_result:, failures:,
                   ssn_rate_limited:)
      @idv_session = idv_session
      @service_provider = service_provider
      @resolved_authn_context_result = resolved_authn_context_result
      @failures = failures
      @ssn_rate_limited = ssn_rate_limited
    end

    def eligible?
      ineligible_reasons.empty?
    end

    # @return [Array<Symbol>] why the user does not qualify, for analytics; empty when eligible
    def ineligible_reasons
      @ineligible_reasons ||= {
        service_provider_not_allowed: !service_provider&.idv_unresolved_handoff_allowed?,
        facial_match_not_requested: !resolved_authn_context_result&.facial_match?,
        document_type_not_supported: !(passport? || state_id?),
        document_source_check_not_passed: !source_check_passed?,
        selfie_check_not_passed: idv_session.selfie_check_performed != true,
        alternate_proofing_path: alternate_proofing_path?,
        ssn_rate_limited: @ssn_rate_limited,
        resolution_exception: failures.has_exception?,
        resolution_did_not_fail: !failures.resolution_failed?,
        device_risk_not_passed: !device_risk_passed?,
      }.select { |_reason, applies| applies }.keys
    end

    private

    def document_type
      idv_session.pii_from_doc&.document_type_received
    end

    def passport?
      Idp::Constants::DocumentTypes::SUPPORTED_PASSPORT_TYPES.include?(document_type)
    end

    # mDLs are excluded: IdV accepts them without a selfie, and the handoff requires one.
    def state_id?
      Idp::Constants::DocumentTypes::SUPPORTED_STATE_ID_TYPES.include?(document_type)
    end

    # Document capture only completes for a passport whose MRZ check passed, so any recorded
    # vendor means it did. A state ID needs a real AAMVA match: an unsupported jurisdiction or a
    # bypassed AAMVA exception also lets document capture complete, but confirms nothing.
    def source_check_passed?
      vendor = idv_session.source_check_vendor
      return vendor.present? if passport?
      return false unless state_id?

      vendor == DocAuth::Aamva::Proofer::VENDOR_NAME ||
        (vendor == Idp::Constants::Vendors::STATE_ID_MOCK &&
          IdentityConfig.store.proofer_mock_fallback)
    end

    # In-person, proofing agent and CLEAR verification each have their own outcomes.
    def alternate_proofing_path?
      !!(idv_session.opted_in_to_in_person_proofing ||
        idv_session.agent_proofed ||
        idv_session.clear1_verified)
    end

    # A review or reject from ThreatMetrix is never handed off. A missing hybrid stage is fine.
    # The hybrid stage is read from `stages` directly: the adjudicator names it
    # `hybrid_mobile_threatmetrix`, which `VerificationFailures#hybrid_threatmetrix_stage` misses.
    def device_risk_passed?
      return false unless failures.threatmetrix_stage[:review_status] == 'pass'

      hybrid_status = failures.stages.dig(:hybrid_mobile_threatmetrix, :review_status)
      hybrid_status.nil? || hybrid_status == 'pass'
    end
  end
end
