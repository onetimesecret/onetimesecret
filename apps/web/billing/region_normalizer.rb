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
  #   Billing::RegionNormalizer.match?(nil, "US")   # => false (fail-closed)
  #   Billing::RegionNormalizer.match?("US", nil)   # => true  (no region configured)
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

    # Compare two region values with normalization (fail-closed)
    #
    # When a deployment region is configured (b is non-nil), products
    # or plans must have an explicit matching region to be accepted.
    # Products with nil/blank region are rejected — there are no
    # cross-region products, and any future ones will carry an
    # explicit region value.
    #
    # When no deployment region is configured (b is nil), all
    # products are accepted regardless of their region metadata
    # (pre-regionalization pass-through).
    #
    # This matches the semantics of the existing correct_region?
    # method, where nil.to_s.upcase produces "" which never matches
    # a configured region string.
    #
    # @param a [String, nil] Product/plan region value
    # @param b [String, nil] Deployment's configured region
    # @return [Boolean] true if regions match or no region configured
    def self.match?(a, b)
      na = normalize(a)
      nb = normalize(b)
      return true if nb.nil?
      return false if na.nil?

      na == nb
    end
  end
end
