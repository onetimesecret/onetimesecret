# lib/onetime/models/organization/chores/ensure_member_through_models.rb
#
# frozen_string_literal: true

# Housekeeping chore: Backfill missing OrganizationMembership through-models
# for pre-v0.25.6 accounts.
#
# Pre-v0.25.6 accounts have their customer objid in `org.members` (a Familia
# sorted set / Redis ZSET) but no corresponding OrganizationMembership hash
# in Redis. The v0.25.6 `require_entitlement!` gate requires this
# through-model to exist AND have materialized entitlements.
#
# Four branches per member entry (ghost records filtered by load_multi):
#
#   1. Through-model exists AND materialized      → silent no-op
#   2. Through-model exists, NOT materialized      → materialize only
#   3. Through-model missing, customer present     → create + materialize
#   4. org.members empty                           → no-op
#
# Run via HousekeepingJob:
#   HousekeepingJob.perform('Onetime::Organization', :ensure_member_through_models)

module Onetime
  module Chores
    module EnsureMemberThroughModels
      # No constants needed — the logic is purely structural.
    end
  end
end

Onetime::Organization.chore :ensure_member_through_models do |org|
  logger      = Onetime.get_logger('Chores')
  owner_objid = org.owner_id
  modified    = false

  # Batch-load customers from the ZSET; compact drops ghost records.
  customers = OT::Customer.load_multi(org.members.to_a).compact

  customers.each do |customer|
    membership = OT::OrganizationMembership.find_by_org_customer(org.objid, customer.objid)

    if membership.nil?
      role = customer.objid == owner_objid ? 'owner' : 'member'

      membership = org.add_members_instance(
        customer,
        through_attrs: {
          role: role,
          status: 'active',
          joined_at: org.created.to_f,
        },
      )

      logger.info 'Created membership through-model',
        chore: :ensure_member_through_models,
        org_extid: org.extid,
        customer_objid: customer.objid,
        role: role

      modified = true
    end

    next unless membership && !membership.entitlements_materialized?

    if org.entitlements.empty?
      org.materialize_standalone_entitlements!
    end

    membership.materialize_for_role!(org)

    logger.info 'Materialized membership entitlements',
      chore: :ensure_member_through_models,
      org_extid: org.extid,
      customer_objid: customer.objid

    modified = true
  end

  modified || nil
end
