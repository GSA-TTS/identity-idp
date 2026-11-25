# frozen_string_literal: true

module Idv
  class UnresolvedHandoffConsentForm
    include ActiveModel::Model

    attr_reader :consent_given

    validates :consent_given,
              acceptance: {
                message: proc { I18n.t('idv.unresolved_handoff.errors.consent_required') },
              }

    def initialize(consent_given: false)
      @consent_given = consent_given
    end

    def submit(params)
      @consent_given = params[:consent_given] == '1'

      FormResponse.new(success: valid?, errors: errors)
    end
  end
end
