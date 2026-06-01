# lib/onetime/models/organization/features/with_plan_entitlements.rb
#
# frozen_string_literal: true

module Onetime
  module Models
    module Features
      # Plan-Resolution Entitlements Feature (Organization-only)
      #
      # Adds the Billing::Plan fallback chain on top of the portable
      # WithEntitlements base. Overrides `entitlements` and calls `super` to
      # reach the materialized-only path when the org has been materialized.
      #
      # This module is Organization-specific because it references `planid`,
      # `Billing::Plan`, and `Billing::PlanHelpers`. It must be included AFTER
      # `with_entitlements` so its `entitlements` override sits at the top of
      # the method-resolution chain.
      #
      # == Fail-Open / Fail-Closed Design
      #
      # This module implements the dual-mode authorization strategy:
      #
      # === FAIL-OPEN (Self-Hosted / Standalone Mode)
      #
      # When billing is disabled or no entitlements exist, we allow unlimited
      # resource creation. This ensures self-hosted instances work without any
      # billing configuration. Conditions that trigger fail-open:
      # - billing_enabled? returns false
      # - No plan assigned (planid empty)
      # - entitlements array is empty
      #
      # Result: STANDALONE_ENTITLEMENTS (full access), limits return Float::INFINITY
      #
      # === FAIL-CLOSED (SaaS / Billing Enabled)
      #
      # When billing is properly configured, quota checks are strictly enforced.
      # Internal errors (Redis failures, missing plan data) should propagate as
      # exceptions rather than silently allowing resource creation. This protects
      # from misuse and ensures plan limits are respected.
      #
      module WithPlanEntitlements
        Familia::Base.add_feature self, :with_plan_entitlements

        # Full entitlement set for standalone mode
        # When billing is disabled or plan cache is empty, users get full access
        # Must include all entitlements from ROLE_ENTITLEMENTS (ADR-012) so the
        # membership intersection (org ∩ role) doesn't exclude member-level ones.
        STANDALONE_ENTITLEMENTS = %w[
          create_secrets view_receipt api_access notifications
          extended_default_expiration
          manage_teams manage_members audit_logs workspace_branding ip_access_rules
          custom_domains homepage_secrets incoming_secrets
          custom_branding custom_privacy_defaults
          custom_mail_sender flexible_from_domain
          custom_signup_validation manage_sso manage_orgs manage_billing
        ].freeze

        # Free tier entitlements as fallback when billing is enabled
        # but plan cache is empty. This prevents showing "No features available"
        # and provides a failsafe degraded experience.
        #
        # These match the free_v1 plan in billing.yaml.
        FREE_TIER_ENTITLEMENTS = %w[
          create_secrets
          view_receipt
          api_access
          custom_domains
          incoming_secrets
          homepage_secrets
        ].freeze

        def self.included(base)
          OT.ld "[features] #{base}: #{name}"
          base.extend ClassMethods
          base.include InstanceMethods
        end

        module ClassMethods
          # Parse TTL value from environment variable with strict validation
          #
          # Uses Integer() for strict parsing to reject malformed values like "123abc".
          # Applies bounds validation: minimum 0, maximum MAX_TTL (365 days).
          #
          # @param env_var [String] Environment variable name
          # @param default [Integer] Default value if env var is not set or invalid
          # @return [Integer] Validated TTL value in seconds (0 to MAX_TTL)
          #
          # @example
          #   Organization.parse_ttl_env('PLAN_TTL_ANONYMOUS', 604_800)
          def parse_ttl_env(env_var, default)
            raw = ENV.fetch(env_var, nil)
            return default if raw.nil? || raw.strip.empty?

            begin
              value = Integer(raw.strip, 10)
              value.clamp(0, WithEntitlements::MAX_TTL)
            rescue ArgumentError
              OT.lw "[WithPlanEntitlements] Invalid #{env_var} value, using default",
                { env_var: env_var, default: default }
              default
            end
          end

          # FREE tier default limits when cache is unavailable
          #
          # The secret_lifetime.max value can be overridden via PLAN_TTL_ANONYMOUS
          # environment variable for Docker/self-hosted deployments.
          #
          # Results are memoized at class level for consistent behavior.
          #
          # @see https://github.com/onetimesecret/onetimesecret/issues/2390
          # @see https://github.com/onetimesecret/onetimesecret/issues/3111
          def free_tier_limits
            @free_tier_limits ||= {
              'organizations.max' => 5,
              'teams.max' => 0,
              'total_members_per_org.max' => 0,
              'role_owners_per_org.max' => 1,
              'role_admins_per_org.max' => 0,
              'role_members_per_org.max' => 0,
              'secret_lifetime.max' => parse_ttl_env('PLAN_TTL_ANONYMOUS', WithEntitlements::DEFAULT_FREE_TTL),
            }.freeze
          end

          # Reset memoized free_tier_limits (for testing)
          def reset_free_tier_limits!
            @free_tier_limits = nil
          end
        end

        module InstanceMethods
          # Materialize standalone-mode entitlements onto this org.
          #
          # When billing is disabled (self-hosted/standalone deployments), there is
          # no Stripe webhook to drive materialization. This method writes the
          # STANDALONE_ENTITLEMENTS set into the org's materialized storage so the
          # runtime fallback at `#entitlements` is no longer the sole source of
          # truth.
          #
          # No-op (returns false) when billing is enabled — those orgs are
          # materialized by the subscription webhook from the assigned plan.
          #
          # Idempotent: safe to call multiple times. Each call re-runs the
          # reconciliation (plan + grants − revokes) via
          # `materialize_entitlements_from_config`.
          #
          # Called from `Organization.create!` (new orgs) and the
          # `materialize_standalone_entitlements` chore (backfill of existing
          # orgs). See ADR-012 §Standalone mode.
          #
          # @return [Boolean] false in billing mode; otherwise the result of
          #   `materialize_entitlements_from_config` (true on success).
          def materialize_standalone_entitlements!
            return false if billing_enabled?

            materialize_entitlements_from_config(
              entitlements: STANDALONE_ENTITLEMENTS,
              limits: {},
            )
          end

          # Get all entitlements for current plan.
          #
          # Overrides WithEntitlements#entitlements with the Plan.load fallback
          # chain. Calls `super` only when the org has been materialized — that
          # path returns materialized_entitlements directly.
          #
          # Order is intentional and matches the pre-split behavior:
          # 1. If billing disabled (standalone mode) -> STANDALONE_ENTITLEMENTS (full access)
          # 2. If materialized -> super (returns materialized_entitlements)
          # 3. If no planid set -> FREE_TIER_ENTITLEMENTS
          # 4. If plan found in cache -> plan.entitlements
          # 5. If plan not in cache, try billing.yaml config fallback
          # 6. Final fallback -> raise PlanCacheMissError (fail-closed)
          #
          # @return [Array<String>] List of entitlement strings
          def entitlements
            # Fail-open: self-hosted/standalone gets full access
            unless billing_enabled?
              return STANDALONE_ENTITLEMENTS.dup
            end

            # Materialized path: delegate to WithEntitlements#entitlements via super,
            # which reads materialized_entitlements directly.
            if respond_to?(:entitlements_materialized?) && entitlements_materialized?
              return super
            end

            # Legacy path (migration): org hasn't been materialized yet
            # Fall back to Plan.load chain until all orgs are migrated
            if planid.to_s.empty?
              return FREE_TIER_ENTITLEMENTS.dup
            end

            # Guard: Billing module may not be loaded (e.g. app built without
            # the billing feature). Fall through to fail-closed below.
            if defined?(::Billing::Plan)
              # Try loading from Redis cache first
              plan = ::Billing::Plan.load(planid)
              if plan
                return plan.entitlements.to_a
              end

              # Plan not in cache - try billing.yaml config fallback
              config_plan = ::Billing::Plan.load_from_config(planid)
              if config_plan && config_plan[:entitlements]
                OT.ld "[WithPlanEntitlements] Using config fallback for plan: #{planid}"
                return config_plan[:entitlements].dup
              end
            end

            # Fail-closed: unknown plan ID is an ops problem, not a silent degradation.
            # This catches catalog misconfigurations and stale planid values that
            # would otherwise silently grant free-tier access.
            raise Billing::PlanCacheMissError.new(
              'Plan not found in cache or config',
              plan_id: planid,
              context: 'WithPlanEntitlements#entitlements',
              organization_id: extid,
            )
          end

          # Check entitlement with detailed response for upgrade messaging
          #
          # Lives in WithPlanEntitlements (not the portable base) because it
          # references `planid` and `Billing::PlanHelpers`, neither of which
          # is portable to non-billing models.
          #
          # @param entitlement [String, Symbol] Entitlement to check
          # @return [Hash] Result with upgrade path information
          #
          # Response includes:
          # - allowed: boolean indicating if entitlement is available
          # - entitlement: the requested entitlement
          # - current_plan: organization's current plan ID
          # - upgrade_needed: boolean indicating if upgrade required
          # - upgrade_to: suggested plan ID (if upgrade needed)
          #
          # @example
          #   org.check_entitlement('custom_domains')
          #   # => {
          #   #   allowed: false,
          #   #   entitlement: "custom_domains",
          #   #   current_plan: "free",
          #   #   upgrade_needed: true,
          #   #   upgrade_to: "identity_v1"
          #   # }
          def check_entitlement(entitlement)
            allowed = can?(entitlement)
            result  = {
              allowed: allowed,
              entitlement: entitlement.to_s,
              current_plan: planid,
              upgrade_needed: !allowed,
            }

            if !allowed && defined?(Billing::PlanHelpers)
              result[:upgrade_to] = Billing::PlanHelpers.upgrade_path_for(entitlement, planid)
            end

            result
          end

          private

          # Get entitlements for a test plan (colonel test mode)
          #
          # Checks Billing::Plan cache first (production/Stripe-synced), then falls back
          # to billing.yaml config (for development when Stripe cache is empty).
          #
          # @param test_planid [String] Plan ID to test
          # @return [Array<String>] List of entitlements for the test plan
          def test_plan_entitlements(test_planid)
            # Guard: billing must be enabled and Billing::Plan must exist
            unless billing_enabled? && defined?(::Billing::Plan)
              return STANDALONE_ENTITLEMENTS.dup
            end

            # Check Billing::Plan cache first (production/Stripe-synced)
            plan = ::Billing::Plan.load(test_planid)
            return plan.entitlements.to_a if plan

            # Fall back to billing.yaml config when Stripe cache is empty
            config_plan = ::Billing::Plan.load_from_config(test_planid)
            return config_plan[:entitlements].dup if config_plan

            []
          end

          # Get FREE tier limit for a resource key
          #
          # @param key [String] Flattened limit key (e.g., "teams.max")
          # @return [Numeric] Limit value, defaults to 0 for unknown keys
          def free_tier_limit_for(key)
            val = self.class.free_tier_limits[key]
            return 0 if val.nil?

            val
          end
        end
      end
    end
  end
end
