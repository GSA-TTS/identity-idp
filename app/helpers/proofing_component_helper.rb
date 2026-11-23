# frozen_string_literal: true

module ProofingComponentHelper
  def proofing_component_analytics_properties(idv_session)
    return {} unless defined?(idv_session)

    { proofing_components: Idv::ProofingComponents.new(idv_session: idv_session).to_h }
  end
end
