# frozen_string_literal: true

module Idv
  # A one-time handoff to an allowlisted service provider for a user whose passport passed every
  # document check but whose identity resolution failed. Nothing is saved to a Profile: the data
  # lives only in the user's (KMS-encrypted) session, is scoped to one issuer, and authorizes a
  # single OpenID Connect request. The service provider receives a distinct `acr`, no
  # `verified_at`, and a `verification_status` claim so it can adjudicate the user itself.
  #
  # Token exchange and every other service provider still see an unverified user.
  class UnresolvedHandoff
    ACR = 'urn:acr.login.gov:document-verified-identity-unresolved'
    SESSION_KEY = 'unresolved_idv_handoff'

    # Fields the service provider receives as unverified, because the user typed them in.
    SELF_ASSERTED_ATTRIBUTES = %w[social_security_number address].freeze

    # @param user_session [Hash] the Warden user session
    def initialize(user_session:)
      @user_session = user_session
    end

    # @param issuer [String]
    # @param pii [Hash] the document PII merged with the SSN and typed-in address
    # @param document_type [String] passport or passport_card
    # @param source_check_vendor [String] the vendor that confirmed the MRZ
    def start!(issuer:, pii:, document_type:, source_check_vendor:)
      user_session[SESSION_KEY] = {
        'issuer' => issuer,
        # Blank values are dropped: an empty address2 would otherwise add a blank address line.
        'pii' => Pii::Attributes.new_from_hash(pii.to_h).to_h.compact_blank.stringify_keys,
        'verification_status' => self.class.verification_status(
          document_type:,
          source_check_vendor:,
        ),
        'consented_at' => Time.zone.now.iso8601,
        'authorized_at' => nil,
      }
    end

    # Whether an authorization request from `issuer` may use the handoff. True once only.
    def authorizable?(issuer)
      data = data_for(issuer)
      data.present? && data['authorized_at'].blank?
    end

    def mark_authorized!
      user_session[SESSION_KEY]['authorized_at'] = Time.zone.now.iso8601
    end

    def present_for?(issuer)
      data_for(issuer).present?
    end

    def clear!
      user_session.delete(SESSION_KEY)
    end

    def self.verification_status(document_type:, source_check_vendor:)
      {
        'identity_resolution' => 'failed',
        'document' => {
          'type' => document_type,
          'authenticity' => 'passed',
          'issuer_check' => 'passed',
          'issuer_check_vendor' => source_check_vendor,
          'facial_match' => 'passed',
        },
        # A copy: SessionEncryptor#dump transforms session arrays in place.
        'self_asserted' => SELF_ASSERTED_ATTRIBUTES.dup,
      }
    end

    # Reads an authorized handoff for `issuer` from a raw session hash, as the token and userinfo
    # endpoints see it through OutOfBandSessionAccessor.
    #
    # @return [Hash, nil] the handoff data, or nil when there is no authorized one for `issuer`
    def self.authorized_data_from_user_session(user_session, issuer:)
      data = user_session&.dig(SESSION_KEY)
      return if data.blank?
      return if data['issuer'] != issuer || data['authorized_at'].blank?

      data
    end

    private

    attr_reader :user_session

    def data_for(issuer)
      data = user_session[SESSION_KEY]
      data if data.present? && data['issuer'] == issuer
    end
  end
end
