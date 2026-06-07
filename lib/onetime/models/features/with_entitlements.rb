# lib/onetime/models/features/with_entitlements.rb
#
# frozen_string_literal: true

module Onetime
  module Models
    module Features
      # Entitlement-Based Authorization Feature (Portable Base)
      #
      # Slim, portable foundation for entitlement checking. Any Familia::Horreum
      # subclass that has a `materialized_entitlements` set (typically provided by
      # `WithMaterializedEntitlements`) can include this feature to gain the
      # boolean predicate `can?(entitlement)` and the read-only `entitlements`
      # accessor, plus the `billing_enabled?` helper used by sibling features.
      #
      # Plan-resolution semantics (fallback to Billing::Plan.load when
      # materialization hasn't happened yet) live in WithPlanEntitlements,
      # which is Organization-only. Likewise, limits and quota predicates live
      # in WithMaterializedLimits.
      #
      # Method-resolution-order pattern:
      # WithPlanEntitlements#entitlements overrides this module's
      # implementation and calls `super` to reach the materialized-only path.
      # The Organization model lists `with_plan_entitlements` AFTER
      # `with_entitlements` so its override sits at the top of the chain.
      #
      # Usage:
      #   org.can?('custom_domains')        # => true/false
      #   org.entitlements                  # => ["api_access", "custom_domains", ...]
      #
      # == Fail-Open / Fail-Closed Design
      #
      # See WithPlanEntitlements for the full fail-open / fail-closed rationale.
      # In this portable base, behavior is intentionally conservative:
      # - If the host model has not been materialized, `entitlements` returns
      #   an empty array. Callers that want the Plan.load fallback chain must
      #   include WithPlanEntitlements.
      #
      module WithEntitlements
        Familia::Base.add_feature self, :with_entitlements

        # Maximum TTL allowed (365 days) - prevents resource exhaustion
        MAX_TTL = 365 * 24 * 60 * 60

        # Default TTL values (in seconds)
        # Free tier max: 14 days. Paid plans or billing-disabled get 30 days.
        # This also serves as the entitlement gate threshold — requests above
        # this value require the 'extended_default_expiration' entitlement.
        #
        # MUST match `free_v1.limits.secret_lifetime` in etc/billing.yaml so
        # that a billing-enabled org with an empty planid (cache miss /
        # unassigned) gets the same 14-day ceiling as the canonical free_v1
        # plan. See #3111 for the drift bug this constant previously caused.
        DEFAULT_FREE_TTL = 1_209_600  # 14 days

        def self.included(base)
          OT.ld "[features] #{base}: #{name}"
          base.include InstanceMethods
        end

        module InstanceMethods
          # Check if model has a specific entitlement
          #
          # @param entitlement [String, Symbol] Entitlement to check
          # @return [Boolean] True if model has the entitlement
          #
          # @example
          #   org.can?('custom_domains')  # => true
          #   org.can?(:api_access)       # => false
          def can?(entitlement)
            entitlements.include?(entitlement.to_s)
          end

          # Get entitlements from materialized state.
          #
          # This portable base returns the materialized set when available,
          # otherwise an empty array. WithPlanEntitlements overrides this
          # method to add the Plan.load fallback chain via `super`.
          #
          # @return [Array<String>] List of entitlement strings
          def entitlements
            if respond_to?(:entitlements_materialized?) && entitlements_materialized?
              return materialized_entitlements.to_a
            end

            []
          end

          # Get entitlements with request context for preview mode support
          #
          # Call sites that have session access should use this method instead
          # of `entitlements` when preview mode needs to be respected.
          #
          # @param session [Hash, nil] Rack session hash (or hash-like object)
          # @return [Array<String>] List of entitlement strings
          #
          # @example Controller usage
          #   org.entitlements_for_request(env['rack.session'])
          #
          # @example When session has preview keys
          #   session = { entitlement_preview_grants_key: 'session:abc:grants' }
          #   org.entitlements_for_request(session)  # => reconciled entitlements
          def entitlements_for_request(session = nil)
            return entitlements unless session.respond_to?(:key?)

            grants_key  = session[:entitlement_preview_grants_key]
            revokes_key = session[:entitlement_preview_revokes_key]

            if (grants_key || revokes_key) && respond_to?(:reconcile_with_session_overrides)
              return reconcile_with_session_overrides(grants_key, revokes_key)
            end

            entitlements
          end

          # Check if billing system is enabled
          # Returns false in standalone mode. Portable across models.
          def billing_enabled?
            Onetime::BillingConfig.instance.enabled?
          rescue StandardError
            false # If BillingConfig fails, assume billing disabled
          end

          private

          # Parse a limit value from string/nil to numeric.
          #
          # Kept here as a portable utility used by WithMaterializedLimits and
          # WithPlanEntitlements. Lives in the base because it has no plan or
          # organization coupling.
          #
          # @param val [String, Integer, nil] Raw limit value
          # @return [Numeric] Parsed limit (0, integer, or Float::INFINITY)
          def parse_limit_value(val)
            return 0 if val.nil? || val.to_s.empty?
            return Float::INFINITY if ['unlimited', '-1'].include?(val.to_s)

            val.to_i
          end
        end
      end
    end
  end
end
