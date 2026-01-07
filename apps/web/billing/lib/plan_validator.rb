# apps/web/billing/lib/plan_validator.rb
#
# frozen_string_literal: true

require_relative '../errors'
require_relative '../models/plan'
require_relative '../config'

module Billing
  # CatalogMissError - Raised when a price_id is not found in the plan catalog
  #
  # This error indicates a critical billing integrity issue:
  # - The price_id exists in Stripe but not in our cached catalog
  # - The catalog may need refreshing via `bin/ots billing catalog pull`
  # - Or a webhook may have been missed for a new product/price
  #
  # Fail-closed behavior: We raise rather than silently proceeding with
  # potentially incorrect billing data.
  #
  class CatalogMissError < Billing::OpsProblem
    attr_reader :price_id

    def initialize(message = nil, price_id: nil)
      @price_id = price_id
      message ||= "Price ID not found in catalog: #{price_id}. " \
                  'Run `bin/ots billing catalog pull` to refresh.'
      super(message)
    end
  end

  # PlanValidator - Catalog-first plan_id validation
  #
  # Provides authoritative plan_id resolution from the billing catalog.
  # The catalog (populated from Stripe prices) is the single source of truth.
  #
  # ## Why Catalog-First?
  #
  # Stripe prices are immutable - once created, their price_id never changes.
  # However, subscription metadata can drift:
  # - Manual Stripe Dashboard changes don't update metadata
  # - Stale metadata from migrations or bugs persists
  # - Support changes via CLI may not update all metadata fields
  #
  # By resolving plan_id from price_id via catalog lookup, we ensure
  # correctness regardless of metadata state.
  #
  # ## Fail-Closed Behavior
  #
  # If a price_id is not found in the catalog, we raise CatalogMissError
  # rather than falling back to potentially incorrect metadata. Billing
  # integrity is critical - we'd rather fail loudly than assign wrong plans.
  #
  # ## Usage
  #
  #   # Resolve plan_id from price_id (authoritative)
  #   plan_id = Billing::PlanValidator.resolve_plan_id(price_id)
  #
  #   # Validate a plan_id exists
  #   if Billing::PlanValidator.valid_plan_id?(user_provided_plan_id)
  #     # Safe to use
  #   end
  #
  #   # Get list of available plan_ids
  #   plans = Billing::PlanValidator.available_plan_ids
  #
  #   # Detect drift between metadata and catalog
  #   drift = Billing::PlanValidator.detect_drift(
  #     price_id: subscription.items.data.first.price.id,
  #     metadata_plan_id: subscription.metadata['plan_id']
  #   )
  #   OT.lw('Drift detected', drift) if drift
  #
  module PlanValidator
    extend self
    include Onetime::LoggerMethods

    # Resolve plan_id from price_id via catalog lookup
    #
    # This is the authoritative way to get a plan_id. The catalog is
    # populated from Stripe prices and refreshed via webhooks or CLI.
    #
    # @param price_id [String] Stripe price ID (e.g., "price_xxx")
    # @return [String] The plan_id from the catalog
    # @raise [ArgumentError] If price_id is nil or empty
    # @raise [CatalogMissError] If price_id is not found in catalog
    #
    def resolve_plan_id(price_id)
      if price_id.nil? || price_id.to_s.strip.empty?
        raise ArgumentError, 'price_id is required'
      end

      plan = Billing::Plan.find_by_stripe_price_id(price_id)

      unless plan
        billing_logger.error '[PlanValidator.resolve_plan_id] Price not in catalog',
                             price_id: price_id
        raise CatalogMissError.new(price_id: price_id)
      end

      plan.plan_id
    end

    # Check if a plan_id is valid (exists in catalog or static config)
    #
    # Valid plan_ids can come from:
    # 1. Stripe catalog (cached Billing::Plan entries via Plan.load)
    # 2. Static config-defined plans (from billing.yaml)
    #
    # @param plan_id [String] Plan ID to validate
    # @return [Boolean] True if plan_id is valid
    #
    def valid_plan_id?(plan_id)
      return false if plan_id.nil? || plan_id.to_s.strip.empty?

      # Check catalog first (Stripe plans via direct load)
      cached_plan = Billing::Plan.load(plan_id)
      if cached_plan&.exists?
        billing_logger.debug '[PlanValidator.valid_plan_id?] Found in catalog',
                             plan_id: plan_id
        return true
      end

      # Fall back to static config plans (from billing.yaml)
      static_plans = Billing::Config.load_plans || {}
      found_in_config = static_plans.key?(plan_id)

      if found_in_config
        billing_logger.debug '[PlanValidator.valid_plan_id?] Found in static config',
                             plan_id: plan_id
      else
        billing_logger.debug '[PlanValidator.valid_plan_id?] Plan not found',
                             plan_id: plan_id
      end

      found_in_config
    end

    # Get all available plan_ids from catalog and static config
    #
    # Returns a unique, sorted list of all valid plan_ids.
    # Useful for error messages and CLI help text.
    #
    # @return [Array<String>] Sorted list of available plan_ids
    #
    def available_plan_ids
      catalog_plan_ids = Billing::Plan.list_plans.map(&:plan_id)
      static_plan_ids = (Billing::Config.load_plans || {}).keys
      (catalog_plan_ids + static_plan_ids).uniq.sort
    end

    # Detect drift between subscription metadata and catalog
    #
    # Compares the plan_id in subscription metadata against what the
    # catalog says it should be based on price_id. Logs a warning
    # if they differ (drift detected).
    #
    # @param price_id [String] Stripe price ID from subscription
    # @param metadata_plan_id [String, nil] plan_id from subscription metadata
    # @return [Hash, nil] Drift info if detected, nil if no drift
    # @raise [CatalogMissError] If price_id is not in catalog
    #
    def detect_drift(price_id:, metadata_plan_id:)
      catalog_plan_id = resolve_plan_id(price_id)

      # No drift if they match
      return nil if catalog_plan_id == metadata_plan_id

      drift_info = {
        catalog_plan_id: catalog_plan_id,
        metadata_plan_id: metadata_plan_id,
        price_id: price_id,
      }

      billing_logger.warn '[PlanValidator] Drift detected: metadata differs from catalog',
                          drift_info

      drift_info
    end
  end
end
