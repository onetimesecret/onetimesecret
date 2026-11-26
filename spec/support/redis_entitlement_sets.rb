# frozen_string_literal: true

# Exercise the real transaction and Familia's JSON encoding while the host
# class supplies its own account, plan and role fixtures.
module RedisEntitlementSets
  def entitlement_store
    @entitlement_store ||= Onetime::Organization.new(objid: SecureRandom.uuid)
  end

  def dbclient = entitlement_store.dbclient
  def dbkey = entitlement_store.dbkey
  def serialize_value(value) = entitlement_store.serialize_value(value)
  def entitlements_plan = entitlement_store.entitlements_plan
  def entitlements_grants = entitlement_store.entitlements_grants
  def entitlements_revokes = entitlement_store.entitlements_revokes
  def materialized_entitlements = entitlement_store.materialized_entitlements

  def clear_entitlement_fixture
    dbclient.del(dbkey, entitlements_plan.dbkey, entitlements_grants.dbkey,
      entitlements_revokes.dbkey, materialized_entitlements.dbkey)
  end
end
