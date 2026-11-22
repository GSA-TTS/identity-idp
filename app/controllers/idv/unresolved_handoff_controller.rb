# frozen_string_literal: true

module Idv
  # Lets a user whose passport passed every document check, but whose identity resolution failed,
  # continue to an allowlisted service provider without a verified profile. See
  # Idv::UnresolvedHandoff and Idv::UnresolvedHandoffEligibility.
  class UnresolvedHandoffController < ApplicationController
    include Idv::AvailabilityConcern
    include IdvSessionConcern

    before_action :confirm_two_factor_authenticated
    before_action :confirm_eligible

    def show
      analytics.idv_unresolved_handoff_visited
      @consent_form = Idv::UnresolvedHandoffConsentForm.new
      @sp_name = decorated_sp_session.sp_name
    end

    def create
      @consent_form = Idv::UnresolvedHandoffConsentForm.new
      result = @consent_form.submit(consent_params)
      analytics.idv_unresolved_handoff_submitted(**result)

      if !result.success?
        @sp_name = decorated_sp_session.sp_name
        return render :show, status: :unprocessable_content
      end

      Idv::UnresolvedHandoff.new(user_session:).start!(
        issuer: current_sp.issuer,
        pii: handoff_pii,
        document_type: idv_session.pii_from_doc.document_type_received,
        source_check_vendor: idv_session.source_check_vendor,
      )

      # The PII now lives only in the handoff, so the in-progress verification is discarded.
      idv_session.clear

      redirect_to sp_session_request_url_with_updated_params, allow_other_host: true
    end

    private

    def confirm_eligible
      return if eligible?

      redirect_to idv_url
    end

    # The decision was made when resolution failed; re-check the parts that could have changed.
    def eligible?
      idv_session.unresolved_handoff_eligible == true &&
        current_sp&.idv_unresolved_handoff_allowed? &&
        resolved_authn_context_result.facial_match? &&
        oidc_request? &&
        idv_session.pii_from_doc.present?
    end

    # The handoff is released through OpenID Connect userinfo only.
    def oidc_request?
      request_url = sp_session[:request_url]
      request_url.present? && URI(request_url).path.end_with?('/openid_connect/authorize')
    end

    def handoff_pii
      idv_session.pii_from_doc.to_h.merge(
        ssn: idv_session.ssn,
        **idv_session.updated_user_address.to_h,
      )
    end

    def consent_params
      params.fetch(:unresolved_handoff, {}).permit(:consent_given)
    end
  end
end
