# lib/onetime/models/organization_membership/features/with_capabilities.rb
#
# frozen_string_literal: true

module Onetime
  module Models
    module Features
      module MembershipCapabilities
        Familia::Base.add_feature self, :membership_capabilities

        # Read the stored membership and its overrides in the same operation
        # that writes the snapshot. A stale Ruby instance cannot reinstate a
        # capability after a role change or recreate a removed membership.
        MATERIALIZE_SCRIPT = <<~LUA
          local role, status, previous = unpack(redis.call('HMGET', KEYS[1],
            'role', 'status', 'materialized_capabilities'))
          if not status then return '[]' end

          local role_capabilities = cjson.decode(ARGV[2])[role]
          local effective = {}
          if status == ARGV[1] and role_capabilities then
            for _, name in ipairs(cjson.decode(ARGV[3])) do
              local key = cjson.encode(name)
              if (role_capabilities[name] or redis.call('SISMEMBER', KEYS[2], key) == 1)
                and redis.call('SISMEMBER', KEYS[3], key) == 0 then
                effective[#effective + 1] = name
              end
            end
          end

          local materialized = #effective == 0 and '[]' or cjson.encode(effective)
          if materialized ~= previous then
            redis.call('HSET', KEYS[1], 'materialized_capabilities', materialized)
          end
          return materialized
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
            return [] if objid.to_s.empty?

            roles = self.class::ROLE_CAPABILITIES.to_h do |role, capabilities|
              [serialize_value(role), capabilities.to_h { |name| [name, true] }]
            end

            materialized = dbclient.eval(
              MATERIALIZE_SCRIPT,
              keys: [dbkey, entitlements_grants.dbkey, entitlements_revokes.dbkey],
              argv: [serialize_value('active'), serialize_value(roles), serialize_value(self.class::CAPABILITIES.to_a)],
            )
            deserialize_value(materialized)
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
