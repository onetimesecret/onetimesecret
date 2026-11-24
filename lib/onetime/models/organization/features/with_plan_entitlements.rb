# lib/onetime/models/organization/features/with_plan_entitlements.rb
#
# frozen_string_literal: true

require 'onetime/authorization/registry'

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

        # Keep the typed snapshot inside the organization hash so it follows
        # its lifetime, including when an older server deletes the record.
        # Older billing workers only update the mixed set. Read that set in
        # the same operation that refreshes the feature projection.
        PLAN_FEATURES_SCRIPT = <<~LUA
          if redis.call('EXISTS', KEYS[1]) == 0 then return nil end
          local features, grants, revokes, changed = {}, {}, {}, false
          local candidates, fallback = cjson.decode(ARGV[1]), cjson.decode(ARGV[2])
          local persist, action, target = ARGV[3] == 'true', ARGV[4], ARGV[5]
          if ARGV[6] == 'true' then
            local stamp = redis.call('HGET', KEYS[1], 'materialized_entitlements_at')
            local materialized = false
            if stamp and stamp ~= '' then
              local decoded, value = pcall(cjson.decode, stamp)
              if decoded and (value == cjson.null or value == '') then
                materialized = false
              elseif (decoded and type(value) == 'string' and string.match(value, '^%d+:[%w]+$'))
                or (not decoded and string.match(stamp, '^%d+:[%w]+$')) then
                materialized = true
              else
                return redis.error_reply('Invalid organization entitlement materialization timestamp')
              end
            end
            if materialized then
              fallback = false
            else
              local plan = redis.call('HGET', KEYS[1], 'planid') or 'null'
              if not fallback or ARGV[7] ~= plan then return {'unmaterialized', plan} end
            end
          end
          for _, name in ipairs(candidates) do
            local key = cjson.encode(name)
            local field = 'feature_override:' .. name
            local marker = redis.call('HGET', KEYS[1], field)
            local grant = redis.call('SISMEMBER', KEYS[3], key) == 1
            local revoke = redis.call('SISMEMBER', KEYS[4], key) == 1
            local typed = marker and cjson.decode(marker)
            -- A legacy edit or clear cancels a previous typed override when
            -- their values disagree. Historical fallback overrides stay inert.
            if (typed == 'grant' and (not grant or revoke)) or (typed == 'revoke' and not revoke) then typed = nil end
            local permitted = redis.call('SISMEMBER', KEYS[2], key) == 1
            if action == 'clear' or (action ~= '' and name == target) then
              local next_grant, next_revoke = action == 'grant', action == 'revoke'
              changed = changed or grant ~= next_grant or revoke ~= next_revoke or typed ~= action
              grant, revoke = next_grant, next_revoke
              typed = action ~= 'clear' and action
              permitted = (grant or redis.call('SISMEMBER', KEYS[5], key) == 1) and not revoke
              if persist then
                redis.call(grant and 'SADD' or 'SREM', KEYS[3], key)
                redis.call(revoke and 'SADD' or 'SREM', KEYS[4], key)
                redis.call(permitted and 'SADD' or 'SREM', KEYS[2], key)
              end
            end
            local encoded = typed and cjson.encode(typed)
            if persist and encoded ~= marker then
              if encoded then redis.call('HSET', KEYS[1], field, encoded)
              else redis.call('HDEL', KEYS[1], field) end
            end
            if fallback then
              permitted = (fallback[name] or typed == 'grant') and typed ~= 'revoke'
            elseif typed then
              -- A worker on the previous version may have published its
              -- mixed snapshot after the typed grant or revoke committed.
              if persist and permitted ~= (typed == 'grant') then
                redis.call(typed == 'grant' and 'SADD' or 'SREM', KEYS[2], key)
              end
              permitted = typed == 'grant'
            end
            if permitted then features[#features + 1] = name end
            if grant then grants[#grants + 1] = name end
            if revoke then revokes[#revokes + 1] = name end
          end
          local snapshot = #features == 0 and '[]' or cjson.encode(features)
          if persist and redis.call('HGET', KEYS[1], 'materialized_plan_features') ~= snapshot then
            redis.call('HSET', KEYS[1], 'materialized_plan_features', snapshot)
          end
          return {features, grants, revokes, changed and 1 or 0}
        LUA

        # Full entitlement set for standalone mode
        # When billing is disabled or plan cache is empty, users get full access
        # Must include all entitlements from ROLE_ENTITLEMENTS (ADR-012) so the
        # membership intersection (org ∩ role) doesn't exclude member-level ones.
        STANDALONE_ENTITLEMENTS = %w[
          create_secrets view_receipt api_access notifications
          extended_default_expiration
          manage_teams manage_members audit_logs workspace_branding ip_access_rules
          custom_domains homepage_secrets homepage_network_rules incoming_secrets
          custom_branding custom_privacy_defaults
          custom_mail_sender flexible_from_domain
          custom_signin_config custom_signup_validation base_domain_signup
          manage_sso manage_org manage_billing
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
          #   Organization.parse_ttl_env('TTL_MAX_ANONYMOUS', 604_800)
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
          # The secret_lifetime.max value can be overridden via TTL_MAX_ANONYMOUS
          # environment variable for Docker/self-hosted deployments.
          #
          # This is the FREE-TIER limit, not the anonymous ceiling. The anonymous
          # ceiling moved to its own config key in 2026-07 —
          # site.secret_options.ttl_max_anonymous, resolved by
          # WithEntitlements.configured_anonymous_max_ttl — because deriving it
          # from plan state meant it disappeared wherever billing was disabled.
          # These limits still bound the anonymous grant on billing-enabled
          # deployments (V2::Logic::Secrets::BaseSecretAction#anonymous_max_ttl
          # takes the minimum), which is where the audit's invariant
          # "anonymous grant <= authenticated free-tier grant" has meaning.
          # 2026-07-29 API audit, item 4.
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
              'secret_lifetime.max' => parse_ttl_env('TTL_MAX_ANONYMOUS', WithEntitlements::DEFAULT_FREE_TTL),
            }.freeze
          end

          # Reset memoized free_tier_limits (for testing)
          def reset_free_tier_limits!
            @free_tier_limits = nil
          end
        end

        module InstanceMethods
          def plan_entitlements(persist: true)
            preview = preview_entitlements
            return preview.select { |item| Onetime::Authorization::Registry.feature?(item) }.uniq.sort if preview

            resolve_plan_features(persist: persist)&.first || []
          end

          def has_feature?(feature) # rubocop:disable Naming/PredicatePrefix -- public feature API
            Onetime::Authorization::Registry.feature?(feature) && plan_entitlements.include?(feature.to_s)
          end

          def apply_entitlements
            legacy = super
            # A legacy override may be recorded before the plan is assigned.
            # Its write need not consult the billing catalog.
            plan_entitlements if entitlements_materialized? && !Onetime::EntitlementPreview.active?
            legacy
          end

          def clear_typed_override_markers(tx, name)
            names = name ? [name] : Onetime::Authorization::Registry.features
            tx.hdel(dbkey, *names.map { |feature| "feature_override:#{feature}" })
          end
          private :clear_typed_override_markers

          def update_feature_override(action, feature, persist: true)
            unless action == 'clear' || (%w[grant revoke].include?(action) && Onetime::Authorization::Registry.feature?(feature))
              raise ArgumentError, 'Unknown feature override'
            end

            resolve_plan_features(action: action, feature: feature, persist: persist) || raise(Onetime::Problem, 'Organization no longer exists')
          end

          # A plan preview only affects the caller's view. Persistent writes
          # always resolve the actual plan, including in an operator request.
          def resolve_plan_features(action: '', feature: '', persist: true)
            billing  = billing_enabled?
            keys     = [dbkey, materialized_entitlements.dbkey, entitlements_grants.dbkey,
                        entitlements_revokes.dbkey, entitlements_plan.dbkey]
            fallback = billing ? false : STANDALONE_ENTITLEMENTS.to_h { |name| [name, true] }
            args     = [serialize_value(Onetime::Authorization::Registry.features.to_a.sort),
                        serialize_value(fallback), persist.to_s, action, feature.to_s, billing.to_s]
            3.times do
              result = dbclient.eval(PLAN_FEATURES_SCRIPT, keys: keys, argv: args)
              return result unless result&.first == 'unmaterialized'

              args[6] = result.last
              plan_id = deserialize_value(result.last)
              args[1] = serialize_value(unmaterialized_plan_entitlements(plan_id).to_h { |name| [name, true] })
            end
            raise Onetime::Problem, 'Organization plan changed during feature lookup'
          end
          private :resolve_plan_features

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
          # Order is intentional:
          # 1. If a request-scoped preview is active (ADR-020) -> session-reconciled override
          # 2. If billing disabled (standalone mode) -> STANDALONE_ENTITLEMENTS (full access)
          # 3. If materialized -> super (returns materialized_entitlements)
          # 4. If no planid set -> FREE_TIER_ENTITLEMENTS
          # 5. If plan found in cache -> plan.entitlements
          # 6. If plan not in cache, try billing.yaml config fallback
          # 7. Final fallback -> raise PlanCacheMissError (fail-closed)
          #
          # @return [Array<String>] List of entitlement strings
          def entitlements
            # Preview override first (ADR-020): the fail-open and Plan.load
            # branches below return without reaching super, so a guard in the
            # base alone would be skipped for non-materialized orgs. No-op in
            # standalone — preview state is only written by the colonel
            # billing-mode endpoint.
            preview = preview_entitlements
            return preview unless preview.nil?

            entitlements_without_preview
          end

          def entitlements_without_preview
            # Fail-open: self-hosted/standalone gets full access
            unless billing_enabled?
              return STANDALONE_ENTITLEMENTS.dup
            end

            # Materialized path: delegate to WithEntitlements#entitlements via super,
            # which reads materialized_entitlements directly.
            if respond_to?(:entitlements_materialized?) && entitlements_materialized?
              return materialized_entitlements.to_a
            end

            unmaterialized_plan_entitlements(planid)
          end
          private :entitlements_without_preview

          def unmaterialized_plan_entitlements(planid)
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
          private :unmaterialized_plan_entitlements

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
