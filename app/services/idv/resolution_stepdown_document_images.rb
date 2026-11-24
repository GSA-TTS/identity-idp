# frozen_string_literal: true

module Idv
  # The ID document and selfie images, and document metadata, a service provider may fetch for a
  # user who stepped down from identity resolution. Without a Profile they come from the document
  # capture session recorded in the stepdown, and only with consent given since the stepdown.
  class ResolutionStepdownDocumentImages
    # @param identity [ServiceProviderIdentity]
    # @param session_accessor [OutOfBandSessionAccessor]
    def initialize(identity:, session_accessor:)
      @identity = identity
      @session_accessor = session_accessor
    end

    def stepped_down?
      identity.service_provider_record&.document_images_sharing_allowed? &&
        AuthnContextResolver.new(
          user: identity.user,
          service_provider: identity.service_provider_record,
          acr_values: identity.acr_values,
        ).result_is_stepped_down? &&
        document_capture_session.present?
    end

    def shareable?
      stepped_down? && identity.biometric_sharing_consented_since?(stepped_down_at)
    end

    # @return [ActiveRecord::Relation<DocumentArtifact>]
    def artifacts
      return DocumentArtifact.none unless shareable?

      document_capture_session.document_artifacts.retained.where(profile_id: nil)
    end

    # @return [Hash]
    def document_metadata
      metadata = document_capture_session.document_metadata if shareable?
      metadata&.profile_id.nil? && metadata&.retained? ? metadata.document_data : {}
    end

    private

    attr_reader :identity, :session_accessor

    def stepdown
      @stepdown ||= session_accessor.load_idv_resolution_stepdown(issuer: identity.service_provider)
    end

    def stepped_down_at
      Time.zone.parse(stepdown[:stepped_down_at].to_s)
    end

    def document_capture_session
      return @document_capture_session if defined?(@document_capture_session)

      uuid = stepdown&.dig(:document_capture_session_uuid)
      @document_capture_session = uuid && DocumentCaptureSession.find_by(
        uuid:,
        user_id: identity.user_id,
      )
    end
  end
end
