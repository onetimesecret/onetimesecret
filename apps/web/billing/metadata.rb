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
    FIELD_CAPABILITIES       = 'capabilities'
    FIELD_PLAN_ID            = 'plan_id'
    FIELD_CREATED            = 'created'
    FIELD_DISPLAY_ORDER      = 'display_order'
    FIELD_SHOW_ON_PLANS_PAGE = 'show_on_plans_page'

    # Limit fields (prefixed with 'limit_')
    FIELD_LIMIT_TEAMS            = 'limit_teams'
    FIELD_LIMIT_MEMBERS_PER_TEAM = 'limit_members_per_team'

    # All required metadata fields
    REQUIRED_FIELDS = [
      FIELD_APP,
      FIELD_TIER,
      FIELD_REGION,
      FIELD_CAPABILITIES,
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
