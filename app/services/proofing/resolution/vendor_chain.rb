# frozen_string_literal: true

module Proofing
  module Resolution
    class VendorChain
      attr_reader :assigned_vendor, :configured_shares

      def initialize(assigned_vendor:, configured_shares:)
        @assigned_vendor = assigned_vendor
        @configured_shares = configured_shares
      end

      def vendors
        return [assigned_vendor] unless failover_selected?

        [assigned_vendor, *fallback_vendors].uniq
      end

      private

      # rand is in [0, 1), so 0 percent never selects and 100 always does.
      def failover_selected?
        (rand * 100) < IdentityConfig.store.idv_resolution_failover_enabled_percent
      end

      def fallback_vendors
        configured_shares
          .select { |vendor, share| share&.positive? && vendor != :mock }
          .sort_by { |vendor, share| [-share, configured_shares.keys.index(vendor)] }
          .map(&:first)
      end
    end
  end
end
