# try/unit/operations/customers/role_support_try.rb
#
# frozen_string_literal: true

#
# Unit tryouts for Onetime::Operations::Customers::RoleSupport (#4328) — the
# shared "who is still a colonel" predicate behind the last-colonel interlocks
# on the role endpoint, the unverify endpoint and `bin/ots customers role`.
#
# The point of these cases is the FAIL-OPEN failure mode. Customer.colonel_count
# / role_index_for read a DERIVED index that drifts UPWARD through two
# documented familia-2.12 mechanisms (reconcile_role_index.rb):
#
#   * ADD-ONLY partial writes retain the previous role's bucket member, so an
#     account demoted through a targeted writer stays in `role_index:colonel`
#   * a TTL-expired customer hash leaves its index member behind forever
#
# and `has_system_role?` additionally refuses every elevated role to an
# UNVERIFIED account. So a guard that counted the index would answer "another
# colonel exists" when none does, and cheerfully demote the last one.
#
# These run against REAL Redis with a deliberately drifted index, which is the
# only way to prove the re-validation actually happens.
#
# Run: try --agent try/unit/operations/customers/role_support_try.rb

require_relative '../../../support/test_helpers'

OT.boot! :test

require 'onetime/operations/customers/role_support'

RS = Onetime::Operations::Customers::RoleSupport

@nonce  = Familia.generate_id[0, 12]
@bucket = Onetime::Customer.role_index_for('colonel')

# Every colonel this file did not create is noise for the "sole colonel" cases,
# so the roster is measured RELATIVE to a snapshot taken before seeding.
@preexisting = RS.active_colonels.map(&:objid)

def make_customer(label, role:, verified:)
  cust = Onetime::Customer.create!(email: "rolesupport_#{label}_#{@nonce}@example.com")
  cust.role     = role
  cust.verified = verified ? 'true' : 'false'
  cust.save
  cust
end

# Ours, relative to the snapshot.
def ours(colonels)
  colonels.reject { |c| @preexisting.include?(c.objid) }
end

@colonel   = make_customer('primary', role: 'colonel', verified: true)
@unverified = make_customer('unverified', role: 'colonel', verified: false)
@demoted   = make_customer('demoted', role: 'customer', verified: true)

# DRIFT 1 — add-only partial write: the demoted account still sits in the
# colonel bucket, exactly as a targeted writer would leave it.
@bucket.add(@demoted.objid)

# DRIFT 2 — an index member whose customer hash no longer exists (the
# TTL-expiry shape). Nothing else in Redis names this objid.
@ghost_objid = "cust_ghost_#{@nonce}"
@bucket.add(@ghost_objid)

## The drifted index over-reports: colonel_count sees every seeded member
[@bucket.member?(@demoted.objid), @bucket.member?(@ghost_objid)]
#=> [true, true]

## active_colonels EXCLUDES an index member whose customer hash is gone
ours(RS.active_colonels).map(&:objid).include?(@ghost_objid)
#=> false

## ...EXCLUDES one whose authoritative role field disagrees with the bucket
ours(RS.active_colonels).map(&:objid).include?(@demoted.objid)
#=> false

## ...and EXCLUDES an unverified colonel (has_system_role? would refuse it too)
ours(RS.active_colonels).map(&:objid).include?(@unverified.objid)
#=> false

## ...leaving exactly the one account that is authoritatively a colonel
ours(RS.active_colonels).map(&:objid)
#=> [@colonel.objid]

## last_colonel_by_verification? is TRUE for the sole verified colonel
RS.last_colonel_by_verification?(@colonel)
#=> @preexisting.empty?

## last_colonel? is TRUE for demoting that same account
RS.last_colonel?(@colonel, 'customer')
#=> @preexisting.empty?

## ...but a PROMOTION (to colonel) is never a last-colonel refusal
RS.last_colonel?(@colonel, 'colonel')
#=> false

## ...and a non-colonel target is never one either
RS.last_colonel?(@demoted, 'customer')
#=> false

## An UNVERIFIED colonel is not "the last colonel" by verification — it is not
## eligible for the role in the first place, so unverifying it changes nothing
RS.last_colonel_by_verification?(@unverified)
#=> false

## Once a SECOND verified colonel exists, neither predicate refuses
@second = make_customer('second', role: 'colonel', verified: true)
[RS.last_colonel?(@colonel, 'customer'), RS.last_colonel_by_verification?(@colonel)]
#=> [false, false]

## ...and the roster now names both
ours(RS.active_colonels).map(&:objid).sort == [@colonel.objid, @second.objid].sort
#=> true

# Teardown: destroy the customers, then drop the two synthetic index members
# (destroy! only clears the CURRENT role's bucket, so the drift we seeded by
# hand has to be removed by hand).
[@colonel, @unverified, @demoted, @second].each { |c| c.destroy! if c.exists? }
@bucket.remove(@demoted.objid)
@bucket.remove(@ghost_objid)
