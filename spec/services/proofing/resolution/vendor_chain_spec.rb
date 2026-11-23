require 'rails_helper'

RSpec.describe Proofing::Resolution::VendorChain do
  subject(:vendor_chain) do
    described_class.new(
      assigned_vendor:,
      configured_shares:,
    )
  end

  let(:vendors) { vendor_chain.vendors }
  let(:assigned_vendor) { :socure_kyc }
  let(:configured_shares) do
    {
      socure_kyc: 60,
      instant_verify: 0,
      instant_verify_ddp: 40,
    }
  end

  before do
    allow(IdentityConfig.store).to receive(:idv_resolution_failover_enabled_percent)
      .and_return(100)
    allow(vendor_chain).to receive(:rand).and_return(0.5)
  end

  it 'puts the assigned vendor first and does not duplicate it' do
    expect(vendors).to eq([:socure_kyc, :instant_verify_ddp])
  end

  it 'excludes vendors with no traffic share' do
    expect(vendors).not_to include(:instant_verify)
  end

  context 'when the assigned vendor has zero configured share' do
    let(:assigned_vendor) { :instant_verify }

    it 'keeps the assigned vendor first' do
      expect(vendors).to eq([:instant_verify, :socure_kyc, :instant_verify_ddp])
    end
  end

  context 'when fallback shares differ' do
    let(:configured_shares) do
      {
        socure_kyc: 10,
        instant_verify: 60,
        instant_verify_ddp: 30,
      }
    end

    it 'orders fallback vendors by descending share' do
      expect(vendors).to eq([:socure_kyc, :instant_verify, :instant_verify_ddp])
    end
  end

  context 'when fallback shares are equal' do
    let(:configured_shares) do
      {
        socure_kyc: 20,
        instant_verify: 40,
        instant_verify_ddp: 40,
      }
    end

    it 'uses configured bucket order to break the tie' do
      expect(vendors).to eq([:socure_kyc, :instant_verify, :instant_verify_ddp])
    end
  end

  context 'when fallback shares are zero' do
    let(:configured_shares) do
      {
        socure_kyc: 10,
        instant_verify: 0,
        instant_verify_ddp: 0,
      }
    end

    it 'does not use zero-share vendors or mock as fallbacks' do
      expect(vendors).to eq([:socure_kyc])
    end
  end

  context 'when a fallback share is nil' do
    let(:configured_shares) do
      {
        socure_kyc: 60,
        instant_verify: nil,
        instant_verify_ddp: 40,
      }
    end

    it 'does not use that vendor as a fallback' do
      expect(vendors).to eq([:socure_kyc, :instant_verify_ddp])
    end
  end

  context 'when mock is the assigned vendor' do
    let(:assigned_vendor) { :mock }

    it 'keeps mock as the assigned vendor' do
      expect(vendors).to eq([:mock, :socure_kyc, :instant_verify_ddp])
    end
  end

  context 'with rollout at zero percent' do
    before do
      allow(IdentityConfig.store).to receive(:idv_resolution_failover_enabled_percent)
        .and_return(0)
    end

    it 'does not select failover when rand returns zero' do
      allow(vendor_chain).to receive(:rand).and_return(0.0)
      expect(vendors).to eq([:socure_kyc])
    end
  end

  context 'with a partial rollout' do
    before do
      allow(IdentityConfig.store).to receive(:idv_resolution_failover_enabled_percent)
        .and_return(25)
    end

    it 'selects a roll below the percentage' do
      allow(vendor_chain).to receive(:rand).and_return(0.2499)
      expect(vendors).to eq([:socure_kyc, :instant_verify_ddp])
    end

    it 'does not select a roll at the percentage' do
      allow(vendor_chain).to receive(:rand).and_return(0.25)
      expect(vendors).to eq([:socure_kyc])
    end
  end

  context 'with rollout at 100 percent' do
    it 'selects failover at the highest possible roll' do
      allow(vendor_chain).to receive(:rand).and_return(0.9999999)
      expect(vendors).to eq([:socure_kyc, :instant_verify_ddp])
    end
  end

  it 'samples the failover rollout once' do
    expect(vendor_chain).to receive(:rand).once.and_return(0.5)

    vendors
  end
end
