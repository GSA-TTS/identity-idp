# frozen_string_literal: true

module IdvResolutionStepdownConcern
  extend ActiveSupport::Concern

  def request_has_stepped_down?
    resolved_authn_context_result&.idv_resolution_stepdown_eligible? &&
      user_session[:idv_resolution_stepdown].present?
  end

  def idv_resolution_stepdown_pii
    return @idv_resolution_stepdown_pii if defined?(@idv_resolution_stepdown_pii)

    @idv_resolution_stepdown_pii = IdvResolutionStepdownConcern.pii_from(
      user_session[:idv_resolution_stepdown],
      issuer: current_sp&.issuer,
    )
  end

  # @param data [Hash, nil] the stepdown stored in the user session
  # @return [Pii::Attributes, nil] the decrypted PII, when `data` is for `issuer`
  def self.pii_from(data, issuer:)
    return if data.blank? || data[:issuer] != issuer || data[:encrypted_pii].blank?

    pii_json = SessionEncryptor.new.kms_decrypt(data[:encrypted_pii])
    Pii::Attributes.new_from_hash(JSON.parse(pii_json, symbolize_names: true))
  end
end
