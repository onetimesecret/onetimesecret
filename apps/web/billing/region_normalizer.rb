# apps/web/billing/region_normalizer.rb
#
# frozen_string_literal: true

module Billing
  # RegionNormalizer - Single source of truth for region string handling
  #
  # Centralizes the normalization logic that was previously duplicated
  # across BillingConfig#region, Plan.correct_region?, and various CLI
  # commands. All region comparisons in the billing system should go
  # through this module to prevent nil/blank/case mismatches.
  #
  # ## Normalization Rules
  #
  #   nil       => nil
  #   ""        => nil
  #   "  "      => nil
  #   "us"      => "US"
  #   " Eu  "   => "EU"
  #
  # ## Usage
  #
  #   Billing::RegionNormalizer.normalize("eu")    # => "EU"
  #   Billing::RegionNormalizer.normalize(nil)      # => nil
  #   Billing::RegionNormalizer.normalize("")       # => nil
  #
  #   Billing::RegionNormalizer.match?("eu", "EU")  # => true
  #   Billing::RegionNormalizer.match?(nil, "US")   # => true  (pass-through)
  #
  module RegionNormalizer
    # Normalize a region string: nil/blank -> nil, otherwise stripped + upcased
    #
    # This prevents the nil.to_s -> "" bug that erases Stripe metadata
    # when a nil region is coerced to an empty string and written back.
    #
    # @param region [String, nil] Raw region value
    # @return [String, nil] Normalized region or nil
    def self.normalize(region)
      return nil if region.nil?

      val = region.to_s.strip
      return nil if val.empty?

      val.upcase
    end

    # Compare two region values with normalization
    #
    # Returns true if both normalize to the same non-nil value,
    # or if either is nil (pass-through mode). The nil pass-through
    # matches existing behavior: when no region is configured, all
    # products are accepted regardless of their region metadata.
    #
    # @param a [String, nil] First region value
    # @param b [String, nil] Second region value
    # @return [Boolean] true if regions match or either is nil
    def self.match?(a, b)
      na = normalize(a)
      nb = normalize(b)
      return true if na.nil? || nb.nil?

      na == nb
    end
  end
end
