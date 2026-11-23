require 'rails_helper'

RSpec.describe Proofing::Resolution::ResolutionDecision do
  let(:resolution_result) { Proofing::Resolution::Result.new(success: true) }
  let(:residential_resolution_result) { resolution_result }
  let(:ipp_enrollment_in_progress) { false }
  let(:ipp_current_address_matches_id) { nil }
  let(:applicant_pii) { {} }
  let(:proofing_vendor) { :instant_verify_ddp }
  let(:resolution_bypassed) { false }
  let(:get_to_yes_enabled_vendors) { ['instant_verify_ddp'] }

  subject(:decision) do
    described_class.new(
      resolution_result:,
      residential_resolution_result:,
      ipp_enrollment_in_progress:,
      ipp_current_address_matches_id:,
      applicant_pii:,
      proofing_vendor:,
      resolution_bypassed:,
    )
  end

  before do
    allow(IdentityConfig.store).to receive(:idv_aamva_get_to_yes_enabled_vendors)
      .and_return(get_to_yes_enabled_vendors)
  end

  context 'when resolution passes' do
    it 'succeeds' do
      expect(decision).to have_attributes(success?: true, reason: :pass_resolution_and_state_id)
    end
  end

  context 'when resolution fails' do
    let(:resolution_result) { Proofing::Resolution::Result.new(success: false) }

    it 'fails' do
      expect(decision).to have_attributes(
        success?: false,
        reason: :fail_resolution_without_state_id_coverage,
      )
    end

    context 'when the failure was bypassed' do
      let(:resolution_bypassed) { true }

      it 'succeeds' do
        expect(decision).to have_attributes(success?: true, reason: :instant_verify_bypass)
      end
    end
  end

  context 'when resolution fails only on attributes AAMVA verified' do
    let(:resolution_result) do
      Proofing::Resolution::Result.new(
        success: false,
        failed_result_can_pass_with_additional_verification: true,
        attributes_requiring_additional_verification: [:address],
      )
    end
    let(:applicant_pii) { { aamva_verified_attributes: [:address] } }

    it 'succeeds because AAMVA covers the failure' do
      expect(decision).to have_attributes(
        success?: true,
        reason: :state_id_covers_failed_resolution,
        passed_state_id_attributes: [:address],
      )
    end

    context 'when get to yes is not enabled for the vendor' do
      let(:get_to_yes_enabled_vendors) { ['socure_kyc'] }

      it 'fails' do
        expect(decision).to have_attributes(
          success?: false,
          reason: :fail_resolution_without_state_id_coverage,
        )
      end
    end

    context 'when the address was edited' do
      let(:applicant_pii) { { aamva_verified_attributes: [:address], address_edited: true } }

      it 'fails because AAMVA cannot cover the edited address' do
        expect(decision).to have_attributes(
          success?: false,
          reason: :fail_resolution_without_state_id_coverage,
          passed_state_id_attributes: [],
        )
      end
    end
  end

  context 'when an in-person residential address differs from the ID and fails' do
    let(:ipp_enrollment_in_progress) { true }
    let(:ipp_current_address_matches_id) { false }
    let(:residential_resolution_result) { Proofing::Resolution::Result.new(success: false) }

    it 'fails without crediting the passing ID address result' do
      expect(decision).to have_attributes(success?: false, reason: :fail_resolution_skip_state_id)
    end

    context 'when the ID address failure was bypassed' do
      let(:resolution_bypassed) { true }

      it 'still fails' do
        expect(decision).to have_attributes(
          success?: false,
          reason: :fail_resolution_skip_state_id,
        )
      end
    end
  end
end
