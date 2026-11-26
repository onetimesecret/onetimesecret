# lib/onetime/models/organization_membership/features/with_capabilities.rb
#
# frozen_string_literal: true

module Onetime
  module Models
    module Features
      module MembershipCapabilities
        Familia::Base.add_feature self, :membership_capabilities

        # Only these names were authorization inputs before the split. In
        # particular, an old arbitrary string cannot grant a future capability.
        LEGACY_CAPABILITIES = %w[manage_members manage_org manage_sso manage_billing].freeze

        # Read the stored membership and its overrides in the same operation
        # that writes the snapshot. A stale Ruby instance cannot reinstate a
        # capability after a role change or recreate a removed membership.
        MATERIALIZE_SCRIPT = <<~LUA
          local role, status, previous = unpack(redis.call('HMGET', KEYS[1],
            'role', 'status', 'materialized_capabilities'))
          if not status then return nil end
          local role_capabilities = cjson.decode(ARGV[2])[role]
          local active = status == ARGV[1] and role_capabilities
          local action, target, persist = ARGV[5], ARGV[6], ARGV[7] == 'true'
          if action ~= '' and not active then return nil end

          local legacy = cjson.decode(ARGV[4])
          local effective, grants, revokes = {}, {}, {}
          local changed = false
          for _, name in ipairs(cjson.decode(ARGV[3])) do
            local field, key = 'capability_override:' .. name, cjson.encode(name)
            local stored = redis.call('HGET', KEYS[1], field)
            local override = stored and cjson.decode(stored)
            local grant, revoke = override == 'grant', override == 'revoke'
            if legacy[name] then
              -- Observe older writers, including removal of an override. An
              -- empty legacy set is meaningful after an old process clears it.
              grant = redis.call('SISMEMBER', KEYS[2], key) == 1
              revoke = redis.call('SISMEMBER', KEYS[3], key) == 1
            end
            if action == 'clear' or (action ~= '' and target == name) then
              local next_grant, next_revoke = action == 'grant', action == 'revoke'
              changed = changed or grant ~= next_grant or revoke ~= next_revoke
              grant, revoke = next_grant, next_revoke
              if legacy[name] and persist then
                redis.call(grant and 'SADD' or 'SREM', KEYS[2], key)
                redis.call(revoke and 'SADD' or 'SREM', KEYS[3], key)
                local permitted = (grant or redis.call('SISMEMBER', KEYS[4], key) == 1) and not revoke
                redis.call(permitted and 'SADD' or 'SREM', KEYS[5], key)
              end
            end
            if grant then grants[#grants + 1] = name end
            if revoke then revokes[#revokes + 1] = name end
            local decision = revoke and 'revoke' or (grant and 'grant')
            if persist and decision ~= override then
              if decision then redis.call('HSET', KEYS[1], field, cjson.encode(decision))
              else redis.call('HDEL', KEYS[1], field) end
            end
            if active and (role_capabilities[name] or grant) and not revoke then
              effective[#effective + 1] = name
            end
          end

          local materialized = #effective == 0 and '[]' or cjson.encode(effective)
          if persist and materialized ~= previous then
            redis.call('HSET', KEYS[1], 'materialized_capabilities', materialized)
          end
          return {effective, grants, revokes, changed and 1 or 0}
        LUA

        def self.included(base)
          # Stored snapshot from the last evaluation. Use has_capability? for
          # a current answer, including after role changes or override edits.
          base.field :materialized_capabilities
          base.include InstanceMethods
        end

        module InstanceMethods
          # Resolve from the persisted membership on demand, so existing rows
          # need no backfill. The snapshot shares the membership's lifetime.
          def materialize_capabilities!
            capability_state&.first || []
          end
          alias role_capabilities materialize_capabilities!

          def grant_capability(name)
            capability_state(action: 'grant', capability: name)&.last == 1
          end

          def revoke_capability(name)
            capability_state(action: 'revoke', capability: name)&.last == 1
          end

          # Hash fields are private to this operation. They disappear with the
          # membership and a stale Familia model save cannot write them back.
          # A dry run returns the projected effective, grants and revokes and
          # whether the requested action changes an override. It writes nothing.
          def capability_state(action: '', capability: '', persist: true)
            return if objid.to_s.empty?
            unless ['', 'clear', 'grant', 'revoke'].include?(action) &&
                   (['', 'clear'].include?(action) || self.class::CAPABILITIES.include?(capability.to_s))
              raise ArgumentError, 'Unknown capability override'
            end

            roles = self.class::ROLE_CAPABILITIES.to_h do |role, capabilities|
              [serialize_value(role), capabilities.to_h { |name| [name, true] }]
            end

            dbclient.eval(
              MATERIALIZE_SCRIPT,
              keys: [dbkey, entitlements_grants.dbkey, entitlements_revokes.dbkey,
                     entitlements_plan.dbkey, materialized_entitlements.dbkey],
              argv: [serialize_value('active'), serialize_value(roles), serialize_value(self.class::CAPABILITIES.to_a.sort),
                     serialize_value(LEGACY_CAPABILITIES.to_h { |name| [name, true] }), action, capability.to_s, persist.to_s],
            )
          end

          # Capability checks are independent of endpoint authorization.
          def has_capability?(capability) # rubocop:disable Naming/PredicatePrefix -- #3491 model API
            capability = capability.to_s
            self.class::CAPABILITIES.include?(capability) && materialize_capabilities!.include?(capability)
          end
        end
      end
    end
  end
end
