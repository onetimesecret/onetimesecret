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

    # Complimentary subscription marker — lives on Stripe subscription
    # metadata and is cached locally on org.complimentary by webhooks.
    # Stripe is the source of truth; the local field is read-only.
    FIELD_COMPLIMENTARY      = 'complimentary'

    # Optional metadata fields
    FIELD_PLAN_CODE          = 'ots_plan_code'           # Deduplication key (e.g., "identity_plus" for monthly+yearly)
    FIELD_IS_POPULAR         = 'ots_is_popular'          # Boolean: show "Most Popular" badge
    FIELD_PLAN_NAME_LABEL    = 'ots_plan_name_label'     # Display label next to plan name (e.g., "For Teams")
    FIELD_INCLUDES_PLAN      = 'ots_includes_plan'       # Plan ID this plan includes (for "Includes everything in X" display)

    # Limit fields (prefixed with 'limit_')
    # Maps metadata field name to YAML catalog key
    #
    # `total_members_per_org` is the aggregate cap across all roles. The role-specific
    # keys (`role_owners_per_org`, `role_admins_per_org`, `role_members_per_org`)
    # apply sub-caps per role and are enforced alongside the aggregate cap on
    # invitation. See OrganizationAPI::Logic::Invitations::CreateInvitation.
    LIMIT_FIELDS = {
      'limit_teams' => 'teams',
      'limit_total_members_per_org' => 'total_members_per_org',
      'limit_role_owners_per_org' => 'role_owners_per_org',
      'limit_role_admins_per_org' => 'role_admins_per_org',
      'limit_role_members_per_org' => 'role_members_per_org',
      'limit_custom_domains' => 'custom_domains',
      'limit_secret_lifetime' => 'secret_lifetime',
      'limit_secrets_per_day' => 'secrets_per_day',
    }.freeze

    # Human-readable description for a LIMIT_FIELDS key. Shared by CLI option
    # declarations, interactive prompts, and docs generators so a new entry in
    # LIMIT_FIELDS surfaces consistently everywhere without per-site editing.
    def self.limit_field_description(field_name)
      unit = field_name.end_with?('lifetime') ? 'seconds' : '-1 for unlimited'
      "Limit #{field_name.delete_prefix('limit_').tr('_', ' ')} (#{unit})"
    end

    # Legacy constants for backward compatibility
    FIELD_LIMIT_TEAMS                 = 'limit_teams'
    FIELD_LIMIT_TOTAL_MEMBERS_PER_ORG = 'limit_total_members_per_org'
    FIELD_LIMIT_ROLE_OWNERS_PER_ORG   = 'limit_role_owners_per_org'
    FIELD_LIMIT_ROLE_ADMINS_PER_ORG   = 'limit_role_admins_per_org'
    FIELD_LIMIT_ROLE_MEMBERS_PER_ORG  = 'limit_role_members_per_org'
    FIELD_LIMIT_CUSTOM_DOMAINS        = 'limit_custom_domains'
    FIELD_LIMIT_SECRET_LIFETIME       = 'limit_secret_lifetime'
    FIELD_LIMIT_SECRETS_PER_DAY       = 'limit_secrets_per_day'

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

    # Required metadata fields for plan creation (app check is separate gate)
    # These fields must be present AND non-blank for a product to be valid.
    REQUIRED_FIELDS = [
      FIELD_PLAN_ID,
      FIELD_TIER,
      FIELD_REGION,
    ].freeze

    # Canonical free plan ID (used when canceling subscriptions)
    FREE_PLAN_ID = 'free_v1'

    # Plan IDs that represent free/unpaid tiers
    FREE_PLAN_IDS = %w[free free_v1].freeze

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

    # Resolve the deployment's current region for Stripe customer metadata.
    #
    # Returns the configured jurisdiction (e.g., 'EU', 'US') when regions are
    # enabled, or 'global' when regions are disabled. Raises ConfigError if
    # regions are enabled but no jurisdiction is set — that's a deployment
    # misconfiguration that must be corrected, not silently defaulted.
    #
    # @return [String] Region jurisdiction code, or 'global' if regions disabled
    # @raise [Onetime::ConfigError] If regions enabled but jurisdiction missing
    def self.current_region
      # Compare against the string 'true' so a YAML-supplied string like
      # "false" (which is truthy in Ruby) doesn't get treated as enabled.
      return 'global' unless OT.conf&.dig('features', 'regions', 'enabled').to_s == 'true'

      jurisdiction = OT.conf&.dig('features', 'regions', 'current_jurisdiction')
      if jurisdiction.to_s.strip.empty?
        raise Onetime::ConfigError,
          'features.regions.enabled is true but features.regions.current_jurisdiction is not set'
      end

      jurisdiction
    end
  end
end
