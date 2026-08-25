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

        # Default ceiling for unauthenticated creation on CANONICAL hosts:
        # 7 days. This is the shipped default, NOT a universal guest invariant.
        #
        # The 7-day rule addresses unaccountable strangers parking data on the
        # platform's own canonical storage boundary. A guest creating through a
        # custom domain is governed by that domain owner's organization plan
        # (normally 14/30 days), because the tenant is the accountable storage
        # owner. SecretLifetimePolicy owns this request-boundary distinction.
        #
        # Self-hosted operators can raise or lower the canonical-host value via
        # site.secret_options.ttl_max_anonymous (env TTL_MAX_ANONYMOUS). The
        # genuine software-safety bound remains MAX_TTL (365 days).
        #
        # Consumers should call configured_anonymous_max_ttl for the raw
        # canonical-host setting, or SecretLifetimePolicy.guest_ceiling for an
        # effective request ceiling.
        ANONYMOUS_MAX_TTL = 604_800  # 7 days

        # Resolve the configured canonical-host guest TTL ceiling.
        #
        # This is one input to SecretLifetimePolicy, not the effective ceiling
        # for every unauthenticated request. Custom-domain guests use the owning
        # organization's plan policy instead.
        #
        # Bounded to [1, MAX_TTL]. A non-positive or malformed value falls back
        # to the default rather than making anonymous secrets impossible —
        # "0" almost certainly means "unset me", not "expire immediately".
        #
        # @return [Integer] Ceiling in seconds for anonymous callers
        def self.configured_anonymous_max_ttl
          raw = OT.conf.dig('site', 'secret_options', 'ttl_max_anonymous')
          return ANONYMOUS_MAX_TTL if raw.nil?

          value = Integer(raw)
          return ANONYMOUS_MAX_TTL unless value.positive?

          value.clamp(1, MAX_TTL)
        rescue ArgumentError, TypeError
          OT.lw '[WithEntitlements] Invalid site.secret_options.ttl_max_anonymous, using default',
            { value: raw.inspect, default: ANONYMOUS_MAX_TTL }
          ANONYMOUS_MAX_TTL
        rescue StandardError => ex
          # OT.conf unavailable (boot ordering, config fault). Fail to the
          # product default rather than to the config ttl_options max.
          OT.le "[WithEntitlements] ttl_max_anonymous unreadable (#{ex.class}: #{ex.message}); " \
                "using default #{ANONYMOUS_MAX_TTL}"
          ANONYMOUS_MAX_TTL
        end

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
          # A request-scoped preview context (ADR-020) takes precedence: when
          # a colonel has an active preview, the session-reconciled override
          # is returned instead of materialized state.
          #
          # This portable base returns the materialized set when available,
          # otherwise an empty array. WithPlanEntitlements overrides this
          # method to add the Plan.load fallback chain via `super`.
          #
          # @return [Array<String>] List of entitlement strings
          def entitlements
            preview = preview_entitlements
            return preview unless preview.nil?

            if respond_to?(:entitlements_materialized?) && entitlements_materialized?
              return materialized_entitlements.to_a
            end

            []
          end

          # Check if billing system is enabled
          # Returns false in standalone mode. Portable across models.
          def billing_enabled?
            Onetime::BillingConfig.instance.enabled?
          rescue StandardError
            false # If BillingConfig fails, assume billing disabled
          end

          private

          # Resolve the request-scoped preview override, if any (ADR-020).
          #
          # Consults the Fiber-local populated by the
          # EntitlementPreviewContext middleware. Only hosts with a session
          # reconciler (Organization's WithMaterializedEntitlements) can
          # apply the override; other hosts fall through to their normal
          # resolution.
          #
          # Guards the top of BOTH this module's #entitlements and
          # WithPlanEntitlements#entitlements: the override must win before
          # the standalone fail-open and Plan.load fallback branches, which
          # return without reaching `super`.
          #
          # @return [Array<String>, nil] Reconciled entitlements, or nil when
          #   no preview is active or this host cannot reconcile
          def preview_entitlements
            ctx = Onetime::EntitlementPreview.context
            return nil unless ctx

            grants_key  = ctx[:grants_key]
            revokes_key = ctx[:revokes_key]
            unless (grants_key || revokes_key) && respond_to?(:reconcile_with_session_overrides)
              return nil
            end

            reconcile_with_session_overrides(grants_key, revokes_key)
          end

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
