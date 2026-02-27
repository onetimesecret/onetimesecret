# apps/web/billing/metadata.rb
#
# frozen_string_literal: true

module Billing
  # Stripe Product Metadata Constants
  #
  # Defines standardized metadata field names and values for Stripe products.
  # Using constants prevents typos and makes refactoring easier.
  #
  module Metadata
    # Application identifier for filtering products
    APP_NAME = 'onetimesecret'

    # Required metadata fields
    FIELD_APP                = 'app'
    FIELD_TIER               = 'tier'
    FIELD_REGION             = 'region'
    FIELD_TENANCY            = 'tenancy'
    FIELD_ENTITLEMENTS       = 'entitlements'
    FIELD_PLAN_ID            = 'plan_id'
    FIELD_CREATED            = 'created'
    FIELD_CURRENCY           = 'currency'
    FIELD_DISPLAY_ORDER      = 'display_order'
    FIELD_SHOW_ON_PLANS_PAGE = 'show_on_plans_page'

    # Optional metadata fields
    FIELD_PLAN_CODE          = 'ots_plan_code'           # Deduplication key (e.g., "identity_plus" for monthly+yearly)
    FIELD_IS_POPULAR         = 'ots_is_popular'          # Boolean: show "Most Popular" badge
    FIELD_PLAN_NAME_LABEL    = 'ots_plan_name_label'     # Display label next to plan name (e.g., "For Teams")
    FIELD_INCLUDES_PLAN      = 'ots_includes_plan'       # Plan ID this plan includes (for "Includes everything in X" display)

    # Limit fields (prefixed with 'limit_')
    # Maps metadata field name to YAML catalog key
    LIMIT_FIELDS = {
      'limit_teams' => 'teams',
      'limit_members_per_team' => 'members_per_team',
      'limit_custom_domains' => 'custom_domains',
      'limit_secret_lifetime' => 'secret_lifetime',
      'limit_secrets_per_day' => 'secrets_per_day',
    }.freeze

    # Legacy constants for backward compatibility
    FIELD_LIMIT_TEAMS            = 'limit_teams'
    FIELD_LIMIT_MEMBERS_PER_TEAM = 'limit_members_per_team'
    FIELD_LIMIT_CUSTOM_DOMAINS   = 'limit_custom_domains'
    FIELD_LIMIT_SECRET_LIFETIME  = 'limit_secret_lifetime'
    FIELD_LIMIT_SECRETS_PER_DAY  = 'limit_secrets_per_day'

    # Non-limit metadata fields that should be synced to Stripe.
    # Maps metadata field name to yaml_key.
    #
    # During update detection, both SYNCABLE_FIELDS and LIMIT_FIELDS are compared.
    # During creation, only fields with values are included.
    SYNCABLE_FIELDS = {
      FIELD_TIER => 'tier',
      FIELD_TENANCY => 'tenancy',
      FIELD_REGION => 'region',
      FIELD_DISPLAY_ORDER => 'display_order',
      FIELD_SHOW_ON_PLANS_PAGE => 'show_on_plans_page',
      FIELD_ENTITLEMENTS => 'entitlements',      # Special handling: array join
      FIELD_INCLUDES_PLAN => 'includes_plan',
      FIELD_IS_POPULAR => 'is_popular',        # Special handling: boolean
    }.freeze

    # All required metadata fields
    REQUIRED_FIELDS = [
      FIELD_APP,
      FIELD_TIER,
      FIELD_ENTITLEMENTS,
      FIELD_TENANCY,
      FIELD_CREATED,
    ].freeze

    # Values representing unlimited resources
    UNLIMITED_VALUES = ['-1', 'infinity'].freeze

    # Valid subscription statuses
    VALID_SUBSCRIPTION_STATUSES = %w[
      active
      past_due
      unpaid
      canceled
      incomplete
      incomplete_expired
      trialing
      paused
    ].freeze

    # Check if a value represents unlimited
    #
    # @param value [String, Integer] Value to check
    # @return [Boolean] True if value represents unlimited
    def self.unlimited?(value)
      UNLIMITED_VALUES.include?(value.to_s.downcase)
    end

    # Normalize unlimited value to Ruby's Float::INFINITY
    #
    # @param value [String, Integer] Value to normalize
    # @return [Float, Integer] Float::INFINITY if unlimited, otherwise the integer value
    def self.normalize_limit(value)
      unlimited?(value) ? Float::INFINITY : value.to_i
    end
  end
end
