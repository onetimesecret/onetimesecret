# frozen_string_literal: true

module Onetime
  module Models
    module Features
      # Both organizations and memberships keep (plan ∪ grants) − revokes
      # for legacy readers. Compute the union and difference on the server so
      # a concurrent override cannot be overwritten by an earlier Ruby read.
      module EntitlementSetOperations
        def apply_entitlements
          publish_entitlement_sets
          materialized_entitlements.to_a
        end

        def grant_entitlement(name)
          change_entitlement_override(name, entitlements_grants, entitlements_revokes)
        end

        def revoke_entitlement(name)
          change_entitlement_override(name, entitlements_revokes, entitlements_grants)
        end

        def clear_entitlement_overrides
          publish_entitlement_sets do |tx|
            clear_typed_override_markers(tx, nil)
            tx.del(entitlements_grants.dbkey, entitlements_revokes.dbkey)
          end
          materialized_entitlements.to_a
        end

        private

        def change_entitlement_override(name, add_to, remove_from)
          name  = name.to_s
          key   = serialize_value(name)
          added = nil
          publish_entitlement_sets do |tx|
            clear_typed_override_markers(tx, name)
            tx.srem(remove_from.dbkey, key)
            added = tx.sadd?(add_to.dbkey, key)
          end
          added.value
        end

        # Membership-only capabilities have no corresponding legacy override.
        def clear_typed_override_markers(_tx, _name); end

        def publish_entitlement_sets
          target = materialized_entitlements.dbkey
          dbclient.multi do |tx|
            yield tx if block_given?
            tx.sunionstore(target, entitlements_plan.dbkey, entitlements_grants.dbkey)
            tx.sdiffstore(target, target, entitlements_revokes.dbkey)
          end
        end
      end
    end
  end
end
