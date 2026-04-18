# try/unit/models/custom_domain_destroy_cascade_try.rb
#
# frozen_string_literal: true

#
# Tests that CustomDomain.destroy! cascades to:
# 1. Domain-specific configs (HomepageConfig, ApiConfig, SsoConfig,
#    MailerConfig, IncomingConfig)
# 2. Domain-scoped memberships (SSO-provisioned users restricted to this domain)
#
# After destroy!, all associated resources should be cleaned up.

require_relative '../../support/test_helpers'

OT.boot! :test

@owner = Onetime::Customer.create!(email: generate_unique_test_email("cascade_owner"))
@org = Onetime::Organization.create!("Cascade Test Org", @owner, generate_unique_test_email("cascade_contact"))
@domain = Onetime::CustomDomain.create!("cascade-test.example.com", @org.objid)
@domain_id = @domain.identifier

# Stage sibling configs — HomepageConfig + ApiConfig exercise the cleanup path
# added alongside the #3023 backfill migration work; the others were already
# cleaned prior to that change.
Onetime::CustomDomain::HomepageConfig.upsert(domain_id: @domain_id, enabled: true)
Onetime::CustomDomain::ApiConfig.upsert(domain_id: @domain_id, enabled: true)

# Create domain-scoped members
@scoped_user_a = Onetime::Customer.create!(email: generate_unique_test_email("cascade_scoped_a"))
@membership_a = Onetime::OrganizationMembership.ensure_membership(
  @org, @scoped_user_a,
  domain_scope_id: @domain.objid
)
@membership_a_objid = @membership_a.objid

@scoped_user_b = Onetime::Customer.create!(email: generate_unique_test_email("cascade_scoped_b"))
@membership_b = Onetime::OrganizationMembership.ensure_membership(
  @org, @scoped_user_b,
  domain_scope_id: @domain.objid
)
@membership_b_objid = @membership_b.objid

# Create an org-scoped member who should NOT be removed
@org_member = Onetime::Customer.create!(email: generate_unique_test_email("cascade_orgmember"))
@org_membership = Onetime::OrganizationMembership.ensure_membership(@org, @org_member)
@org_membership_objid = @org_membership.objid


## Pre-condition: domain-scoped memberships exist
Onetime::OrganizationMembership.find_all_by_domain_scope(@domain.objid).size
#=> 2

## Pre-condition: org-scoped membership exists
@org_membership.active?
#=> true

## Pre-condition: domain exists
@domain.exists?
#=> true

## Pre-condition: HomepageConfig exists
Onetime::CustomDomain::HomepageConfig.exists_for_domain?(@domain_id)
#=> true

## Pre-condition: ApiConfig exists
Onetime::CustomDomain::ApiConfig.exists_for_domain?(@domain_id)
#=> true

## Destroy the domain (triggers cascade)
@domain.destroy!
true
#=> true

## After destroy: HomepageConfig was cleaned up
Onetime::CustomDomain::HomepageConfig.exists_for_domain?(@domain_id)
#=> false

## After destroy: ApiConfig was cleaned up
Onetime::CustomDomain::ApiConfig.exists_for_domain?(@domain_id)
#=> false

## After destroy: domain-scoped memberships are removed
Onetime::OrganizationMembership.find_all_by_domain_scope(@domain_id).size
#=> 0

## After destroy: domain-scoped membership A hash is deleted
Onetime::OrganizationMembership.exists?(@membership_a_objid)
#=> false

## After destroy: domain-scoped membership B hash is deleted
Onetime::OrganizationMembership.exists?(@membership_b_objid)
#=> false

## After destroy: org-scoped membership is preserved
Onetime::OrganizationMembership.exists?(@org_membership_objid)
#=> true

## After destroy: org-scoped member is still in org.members
@org.member?(@org_member)
#=> true

## After destroy: scoped user A is no longer in org.members
@org.member?(@scoped_user_a)
#=> false

## After destroy: scoped user B is no longer in org.members
@org.member?(@scoped_user_b)
#=> false

# --- Destroy with no sibling configs present is a no-op on cleanup ---
#
# Bare code between `##` testcases does not execute under Tryouts; wrap
# setup as its own testcase so @ivars propagate to subsequent testcases.

## Setup: fresh domain with no sibling configs
@bare_owner = Onetime::Customer.create!(email: generate_unique_test_email("cascade_bare"))
@bare_org = Onetime::Organization.create!("Cascade Bare Org", @bare_owner, generate_unique_test_email("cascade_bare_contact"))
@bare_domain = Onetime::CustomDomain.create!("cascade-bare.example.com", @bare_org.objid)
@bare_domain_id = @bare_domain.identifier
[Onetime::CustomDomain::HomepageConfig.exists_for_domain?(@bare_domain_id),
 Onetime::CustomDomain::ApiConfig.exists_for_domain?(@bare_domain_id),
 Onetime::CustomDomain::SsoConfig.exists_for_domain?(@bare_domain_id),
 Onetime::CustomDomain::MailerConfig.exists_for_domain?(@bare_domain_id),
 Onetime::CustomDomain::IncomingConfig.exists_for_domain?(@bare_domain_id)]
#=> [false, false, false, false, false]

## Destroy on bare domain does not raise
@bare_domain.destroy!
true
#=> true

## Bare domain is gone
Onetime::CustomDomain.find_by_identifier(@bare_domain_id)
#=> nil

# --- One sibling cleanup raising does not block the others ---
#
# Stub HomepageConfig.delete_for_domain! to raise, confirm ApiConfig is still
# cleaned up and destroy! still completes. Restore the stub afterwards so
# cleanup below runs normally.

## Setup: fail-path domain with both HomepageConfig and ApiConfig present
@fail_owner = Onetime::Customer.create!(email: generate_unique_test_email("cascade_fail"))
@fail_org = Onetime::Organization.create!("Cascade Fail Org", @fail_owner, generate_unique_test_email("cascade_fail_contact"))
@fail_domain = Onetime::CustomDomain.create!("cascade-fail.example.com", @fail_org.objid)
@fail_domain_id = @fail_domain.identifier
Onetime::CustomDomain::HomepageConfig.upsert(domain_id: @fail_domain_id, enabled: true)
Onetime::CustomDomain::ApiConfig.upsert(domain_id: @fail_domain_id, enabled: true)
[Onetime::CustomDomain::HomepageConfig.exists_for_domain?(@fail_domain_id),
 Onetime::CustomDomain::ApiConfig.exists_for_domain?(@fail_domain_id)]
#=> [true, true]

## Stubbed HomepageConfig raises during cleanup but destroy! still completes
hp_class = Onetime::CustomDomain::HomepageConfig
original_delete = hp_class.method(:delete_for_domain!)
hp_class.define_singleton_method(:delete_for_domain!) do |_domain_id|
  raise Familia::HorreumError, "forced cleanup failure"
end
begin
  @fail_domain.destroy!
  :completed
ensure
  hp_class.define_singleton_method(:delete_for_domain!) do |domain_id|
    original_delete.call(domain_id)
  end
end
#=> :completed

## ApiConfig was still cleaned up despite HomepageConfig raising
Onetime::CustomDomain::ApiConfig.exists_for_domain?(@fail_domain_id)
#=> false

## Domain hash is gone — the main destroy! ran after sibling cleanups
Onetime::CustomDomain.find_by_identifier(@fail_domain_id)
#=> nil


# --- Sibling cleanups run before the primary record is destroyed ---
#
# Partial-failure recovery depends on this ordering: if super ran first, a
# mid-cascade failure would orphan siblings with no recovery path. Capture
# the primary record's existence at sibling-cleanup time to prove the order.

## Setup: ordering-path domain with HomepageConfig present (unique name avoids stale display_domains)
@order_owner = Onetime::Customer.create!(email: generate_unique_test_email("cascade_order"))
@order_org = Onetime::Organization.create!("Cascade Order Org", @order_owner, generate_unique_test_email("cascade_order_contact"))
@order_domain_name = "cascade-order-#{SecureRandom.hex(4)}.example.com"
@order_domain = Onetime::CustomDomain.create!(@order_domain_name, @order_org.objid)
@order_domain_id = @order_domain.identifier
@order_domain_dbkey = @order_domain.dbkey
Onetime::CustomDomain::HomepageConfig.upsert(domain_id: @order_domain_id, enabled: true)
Onetime::CustomDomain::HomepageConfig.exists_for_domain?(@order_domain_id)
#=> true

## Sibling cleanup fires while primary record still exists in Redis
hp_class = Onetime::CustomDomain::HomepageConfig
original_delete = hp_class.method(:delete_for_domain!)
captured_dbkey = @order_domain_dbkey
captured_primary_exists = nil
hp_class.define_singleton_method(:delete_for_domain!) do |domain_id|
  captured_primary_exists = Familia.dbclient.exists?(captured_dbkey)
  original_delete.call(domain_id)
end
begin
  @order_domain.destroy!
ensure
  hp_class.define_singleton_method(:delete_for_domain!) do |domain_id|
    original_delete.call(domain_id)
  end
end
captured_primary_exists
#=> true

## After destroy: primary record is gone
Onetime::CustomDomain.find_by_identifier(@order_domain_id)
#=> nil


# Cleanup
[@org, @owner, @scoped_user_a, @scoped_user_b, @org_member,
 @bare_org, @bare_owner, @fail_org, @fail_owner,
 @order_org, @order_owner].each do |obj|
  obj.destroy! if obj&.respond_to?(:destroy!) && obj.exists?
end
# Remove the HomepageConfig we left behind on the fail_domain (the stub blocked its cleanup).
Onetime::CustomDomain::HomepageConfig.delete_for_domain!(@fail_domain_id) if @fail_domain_id
