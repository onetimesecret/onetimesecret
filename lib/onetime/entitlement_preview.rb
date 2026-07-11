# lib/onetime/entitlement_preview.rb
#
# frozen_string_literal: true

module Onetime
  # Request-scoped entitlement preview context (ADR-020).
  #
  # Holds the session's preview keys (test planid plus the Redis key names of
  # the session-scoped grants/revokes sets written by SetEntitlementPreview)
  # in a Fiber-local for the duration of a request. The entitlement and limit
  # chokepoints (WithEntitlements#entitlements, WithPlanEntitlements#entitlements,
  # OrganizationMembership#entitlements, WithMaterializedLimits#limit_for)
  # consult this context, so every consumer above them is preview-aware
  # without a session parameter.
  #
  # Populated once per request by Middleware::EntitlementPreviewContext and
  # cleared in its ensure block — the same fiber-local discipline as
  # connection_pinning.rb. A missing context means no preview is active.
  module EntitlementPreview
    FIBER_KEY = :ots_entitlement_preview

    class << self
      # Stash the preview context for the current fiber.
      #
      # Empty strings normalize to nil so a blank session value cannot
      # register as an active preview. When all three values are nil there is
      # nothing to preview: the fiber-local is cleared rather than storing an
      # empty hash that would make `active?` report true.
      #
      # @param planid [String, nil] Preview plan id
      # @param grants_key [String, nil] Redis key of the session grants set
      # @param revokes_key [String, nil] Redis key of the session revokes set
      # @return [Hash, nil] The frozen context, or nil when nothing was stored
      def set(planid:, grants_key:, revokes_key:)
        planid      = normalize(planid)
        grants_key  = normalize(grants_key)
        revokes_key = normalize(revokes_key)

        if planid.nil? && grants_key.nil? && revokes_key.nil?
          clear
          return nil
        end

        Fiber[FIBER_KEY] = {
          planid: planid,
          grants_key: grants_key,
          revokes_key: revokes_key,
        }.freeze
      end

      # @return [Hash, nil] Frozen context hash, or nil when no preview is active
      def context
        Fiber[FIBER_KEY]
      end

      # @return [Boolean] Whether a preview context is present on this fiber
      def active?
        !context.nil?
      end

      # Remove the fiber-local.
      #
      # @return [nil]
      def clear
        Fiber[FIBER_KEY] = nil
      end

      private

      def normalize(value)
        str = value.to_s
        str.empty? ? nil : str
      end
    end
  end
end
