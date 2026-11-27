# frozen_string_literal: true

module OpenidConnect
  class ProofingData
    def initialize(identity:, session_accessor:)
      @identity = identity
      @session_accessor = session_accessor
    end

    def available?
      active_profile.present? || stepdown?
    end

    def document_artifacts
      if stepdown?
        document_capture_session&.document_artifacts&.retained
      else
        active_profile&.document_artifacts&.retained
      end
    end

    def document_images_shareable?
      profile_document_images_shareable? || stepdown_document_images_shareable?
    end

    def document_metadata
      if stepdown?
        metadata = document_capture_session&.document_metadata
      else
        metadata = active_profile.document_metadata
      end

      metadata&.retained? ? metadata.document_data : {}
    end

    def pii
      if stepdown?
        stepdown_pii
      elsif active_profile.present?
        session_accessor.load_pii(active_profile.id)
      end || Pii::Attributes.new_from_hash({})
    end

    def stepdown?
      active_profile.blank? && stepdown_pii.present?
    end

    def consented?
      identity.biometric_sharing_consented?(active_profile:, stepped_down_at:)
    end

    private

    attr_reader :identity, :session_accessor

    def active_profile
      identity.user&.active_profile
    end

    def issuer
      identity&.service_provider_record&.issuer
    end

    def stepdown_pii
      @stepdown_pii ||= session_accessor.load_idv_resolution_stepdown_pii(
        issuer: identity.service_provider,
      )
    end

    def stepped_down_at
      @stepped_down_at ||= session_accessor.load_idv_stepdown_time(
        issuer: identity.service_provider,
      )
    end

    def document_capture_session
      @document_capture_session ||= DocumentCaptureSession.find_by(
        uuid: session_accessor.load_stepdown_document_capture_session_uuid(
          issuer: identity.service_provider,
        ),
        user: identity.user,
        issuer: identity.service_provider,
      )
    end

    def profile_document_images_shareable?
      active_profile.present? &&
        identity.service_provider_record&.document_images_sharing_allowed? &&
        consented?
    end

    def stepdown_document_images_shareable?
      identity.service_provider_record&.document_images_sharing_allowed? &&
        consented? &&
        document_capture_session.present?
    end
  end
end
