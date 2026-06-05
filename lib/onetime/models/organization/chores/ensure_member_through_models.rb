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
# Five branches per member entry:
#
#   1. Through-model exists AND materialized      → silent no-op
#   2. Through-model exists, NOT materialized      → materialize only
#   3. Through-model missing, customer loadable    → create + materialize
#   4. Through-model missing, customer NOT loadable → warn (stale ZSET entry)
#   5. org.members empty                           → no-op
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

  org.members.to_a.each do |customer_objid|
    membership = OT::OrganizationMembership.find_by_org_customer(org.objid, customer_objid)

    if membership.nil?
      customer = OT::Customer.load(customer_objid)

      if customer.nil? || !customer.exists?
        logger.warn 'Stale ZSET entry: customer not loadable',
          chore: :ensure_member_through_models,
          org_extid: org.extid,
          customer_objid: customer_objid
        next
      end

      role = customer_objid == owner_objid ? 'owner' : 'member'

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
        customer_objid: customer_objid,
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
      customer_objid: customer_objid

    modified = true
  end

  modified || nil
end
