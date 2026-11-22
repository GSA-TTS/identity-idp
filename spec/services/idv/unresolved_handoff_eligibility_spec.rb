require 'rails_helper'

RSpec.describe Idv::UnresolvedHandoffEligibility do
  let(:user) { create(:user) }
  let(:service_provider) { create(:service_provider, :active) }
  let(:allowed_issuers) { [service_provider.issuer] }
  let(:idv_session) do
    Idv::Session.new(user_session: {}, current_user: user, service_provider:)
  end
  let(:facial_match) { true }
  let(:resolved_authn_context_result) do
    Component::Parser::Result.new(**Component::Parser::Result.members.index_with(false))
      .with(facial_match?: facial_match, identity_proofing?: true)
  end
  let(:threatmetrix_review_status) { 'pass' }
  let(:hybrid_review_status) { nil }
  let(:resolution_success) { false }
  let(:exception) { nil }
  let(:ssn_rate_limited) { false }
  let(:result) do
    FormResponse.new(
      success: false,
      errors: {},
      extra: {
        proofing_results: {
          exception:,
          context: {
            stages: {
              resolution: { success: resolution_success },
              threatmetrix: { review_status: threatmetrix_review_status },
              hybrid_mobile_threatmetrix: { review_status: hybrid_review_status }.compact,
            },
          },
        },
      },
    )
  end
  let(:failures) { Idv::VerifyInfoConcern::VerificationFailures.new(result:) }

  subject(:eligibility) do
    described_class.new(
      idv_session:,
      service_provider:,
      resolved_authn_context_result:,
      failures:,
      ssn_rate_limited:,
    )
  end

  before do
    allow(IdentityConfig.store).to receive(:idv_unresolved_handoff_allowed_issuers)
      .and_return(allowed_issuers)
    idv_session.pii_from_doc = Pii::Passport.new(
      **Idp::Constants::MOCK_IDV_APPLICANT_WITH_PASSPORT.slice(*Pii::Passport.members),
    )
    idv_session.source_check_vendor = 'dos:passport'
    idv_session.selfie_check_performed = true
  end

  it 'is eligible when the passport passed and only resolution failed' do
    expect(eligibility.eligible?).to eq(true)
    expect(eligibility.ineligible_reasons).to eq([])
  end

  shared_examples 'ineligible' do |reason|
    it "is ineligible (#{reason})" do
      expect(eligibility.eligible?).to eq(false)
      expect(eligibility.ineligible_reasons).to include(reason)
    end
  end

  context 'when the service provider is not allowlisted' do
    let(:allowed_issuers) { [] }
    include_examples 'ineligible', :service_provider_not_allowed
  end

  context 'when facial match was not requested' do
    let(:facial_match) { false }
    include_examples 'ineligible', :facial_match_not_requested
  end

  context 'when the document is a state ID' do
    before do
      idv_session.pii_from_doc = Pii::StateId.new(
        **Idp::Constants::MOCK_IDV_APPLICANT.slice(*Pii::StateId.members),
      )
    end
    include_examples 'ineligible', :not_passport
  end

  context 'when the passport source check did not run' do
    before { idv_session.source_check_vendor = nil }
    include_examples 'ineligible', :passport_source_check_missing
  end

  context 'when the selfie check did not pass' do
    before { idv_session.selfie_check_performed = false }
    include_examples 'ineligible', :selfie_check_not_passed
  end

  context 'when the user is in the in-person flow' do
    before { idv_session.opted_in_to_in_person_proofing = true }
    include_examples 'ineligible', :alternate_proofing_path
  end

  context 'when the SSN is rate limited' do
    let(:ssn_rate_limited) { true }
    include_examples 'ineligible', :ssn_rate_limited
  end

  context 'when a vendor raised an exception' do
    let(:exception) { 'timeout' }
    include_examples 'ineligible', :resolution_exception
  end

  context 'when resolution passed and something else failed' do
    let(:resolution_success) { true }
    include_examples 'ineligible', :resolution_did_not_fail
  end

  context 'when ThreatMetrix asked for review' do
    let(:threatmetrix_review_status) { 'review' }
    include_examples 'ineligible', :device_risk_not_passed
  end

  context 'when hybrid ThreatMetrix rejected the phone session' do
    let(:hybrid_review_status) { 'reject' }
    include_examples 'ineligible', :device_risk_not_passed
  end
end
