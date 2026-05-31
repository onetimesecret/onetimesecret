# try/unit/models/organization_membership_entitlements_try.rb
#
# frozen_string_literal: true

# Unit tests for OrganizationMembership materialized entitlements (ADR-012 Stage 3)
#
# Tests the membership-level entitlement system:
# - ROLE_ENTITLEMENTS constant defining role -> entitlement templates
# - materialize_for_role! computes org.entitlements INTERSECT ROLE_ENTITLEMENTS[role]
# - can?(entitlement) checks materialized set
# - Operator grants/revokes at membership level
# - Role hierarchy: owner > admin > member entitlement sets
#
# Acceptance criteria from #3225:
# 1. Member denied admin-only entitlement
# 2. Admin allowed admin-level entitlement
# 3. Owner allowed all entitlements
# 4. Org without entitlement denies regardless of role
# 5. Operator grant overrides role template

require_relative '../../support/test_models'
require_relative '../../../apps/web/billing/lib/test_support/billing_helpers'

OT.boot! :test

# Arrange: Explicitly disable billing for standalone-mode tests.
# Tests should declare the state they need (AAA pattern) rather than
# depend on config file defaults that can drift.
BillingTestHelpers.disable_billing!

# =============================================================================
# ROLE_ENTITLEMENTS Constant Structure
# =============================================================================

## ROLE_ENTITLEMENTS is defined on OrganizationMembership
Onetime::OrganizationMembership.const_defined?(:ROLE_ENTITLEMENTS)
#=> true

## ROLE_ENTITLEMENTS has entries for owner, admin, member
Onetime::OrganizationMembership::ROLE_ENTITLEMENTS.keys.sort
#=> ['admin', 'member', 'owner']

## Owner template includes admin and member entitlements (role hierarchy)
o = Onetime::OrganizationMembership::ROLE_ENTITLEMENTS['owner']
a = Onetime::OrganizationMembership::ROLE_ENTITLEMENTS['admin']
m = Onetime::OrganizationMembership::ROLE_ENTITLEMENTS['member']
(a - o).empty? && (m - o).empty?
#=> true

## Admin template includes member entitlements
a = Onetime::OrganizationMembership::ROLE_ENTITLEMENTS['admin']
m = Onetime::OrganizationMembership::ROLE_ENTITLEMENTS['member']
(m - a).empty?
#=> true

## Member entitlements do NOT include admin-only entitlements
a = Onetime::OrganizationMembership::ROLE_ENTITLEMENTS['admin']
m = Onetime::OrganizationMembership::ROLE_ENTITLEMENTS['member']
(a - m).empty?
#=> false

## Owner-only entitlements: manage_billing, manage_orgs
o = Onetime::OrganizationMembership::ROLE_ENTITLEMENTS['owner']
a = Onetime::OrganizationMembership::ROLE_ENTITLEMENTS['admin']
o.include?('manage_billing') && !a.include?('manage_billing')
#=> true

## Admin-only entitlements: manage_members, audit_logs
a = Onetime::OrganizationMembership::ROLE_ENTITLEMENTS['admin']
m = Onetime::OrganizationMembership::ROLE_ENTITLEMENTS['member']
a.include?('manage_members') && !m.include?('manage_members')
#=> true

## Member entitlements: create_secrets, api_access
m = Onetime::OrganizationMembership::ROLE_ENTITLEMENTS['member']
m.include?('create_secrets') && m.include?('api_access')
#=> true

# =============================================================================
# Membership Materialization: activate! path
# =============================================================================

## Membership responds to entitlements_materialized?
Onetime::OrganizationMembership.new.respond_to?(:entitlements_materialized?)
#=> true

## Membership responds to materialize_for_role!
Onetime::OrganizationMembership.new.respond_to?(:materialize_for_role!)
#=> true

## Membership responds to can?
Onetime::OrganizationMembership.new.respond_to?(:can?)
#=> true

# =============================================================================
# Full Integration: Create org and memberships
# =============================================================================

## Setup org with owner, verify owner membership has entitlements after creation
suffix = "#{Familia.now.to_i}_#{rand(10000)}"
owner = Onetime::Customer.create!(email: "ment_owner_#{suffix}@test.example.com")
org = Onetime::Organization.create!("Test Org #{suffix}", owner, "contact_#{suffix}@test.example.com")
membership = Onetime::OrganizationMembership.find_by_org_customer(org.objid, owner.objid)
membership&.entitlements_materialized?
#=> true

## Owner membership can? create_secrets
suffix = "#{Familia.now.to_i}_#{rand(10000)}"
owner = Onetime::Customer.create!(email: "ment2_owner_#{suffix}@test.example.com")
org = Onetime::Organization.create!("Test Org2 #{suffix}", owner, "contact2_#{suffix}@test.example.com")
membership = Onetime::OrganizationMembership.find_by_org_customer(org.objid, owner.objid)
membership.can?('create_secrets')
#=> true

## Owner membership can? manage_billing (owner-only)
suffix = "#{Familia.now.to_i}_#{rand(10000)}"
owner = Onetime::Customer.create!(email: "ment3_owner_#{suffix}@test.example.com")
org = Onetime::Organization.create!("Test Org3 #{suffix}", owner, "contact3_#{suffix}@test.example.com")
membership = Onetime::OrganizationMembership.find_by_org_customer(org.objid, owner.objid)
membership.can?('manage_billing')
#=> true

## Member role cannot manage_billing
suffix = "#{Familia.now.to_i}_#{rand(10000)}"
owner = Onetime::Customer.create!(email: "mowner_#{suffix}@test.example.com")
member = Onetime::Customer.create!(email: "mmember_#{suffix}@test.example.com")
org = Onetime::Organization.create!("Member Test Org #{suffix}", owner, "mcontact_#{suffix}@test.example.com")
invite = Onetime::OrganizationMembership.create_invitation!(organization: org, email: member.email, role: 'member', inviter: owner)
invite.accept!(member)
m = Onetime::OrganizationMembership.find_by_org_customer(org.objid, member.objid)
m.can?('manage_billing')
#=> false

## Member role can create_secrets
suffix = "#{Familia.now.to_i}_#{rand(10000)}"
owner = Onetime::Customer.create!(email: "m2owner_#{suffix}@test.example.com")
member = Onetime::Customer.create!(email: "m2member_#{suffix}@test.example.com")
org = Onetime::Organization.create!("Member Test Org2 #{suffix}", owner, "m2contact_#{suffix}@test.example.com")
invite = Onetime::OrganizationMembership.create_invitation!(organization: org, email: member.email, role: 'member', inviter: owner)
invite.accept!(member)
m = Onetime::OrganizationMembership.find_by_org_customer(org.objid, member.objid)
m.can?('create_secrets')
#=> true

## Admin role can manage_members but not manage_billing
suffix = "#{Familia.now.to_i}_#{rand(10000)}"
owner = Onetime::Customer.create!(email: "aowner_#{suffix}@test.example.com")
admin = Onetime::Customer.create!(email: "aadmin_#{suffix}@test.example.com")
org = Onetime::Organization.create!("Admin Test Org #{suffix}", owner, "acontact_#{suffix}@test.example.com")
invite = Onetime::OrganizationMembership.create_invitation!(organization: org, email: admin.email, role: 'admin', inviter: owner)
invite.accept!(admin)
a = Onetime::OrganizationMembership.find_by_org_customer(org.objid, admin.objid)
a.can?('manage_members') && !a.can?('manage_billing')
#=> true

# =============================================================================
# Acceptance Criterion 5: Operator grant overrides role template
# =============================================================================

## Member with operator grant can manage_members
suffix = "#{Familia.now.to_i}_#{rand(10000)}"
owner = Onetime::Customer.create!(email: "gowner_#{suffix}@test.example.com")
member = Onetime::Customer.create!(email: "gmember_#{suffix}@test.example.com")
org = Onetime::Organization.create!("Grant Test Org #{suffix}", owner, "gcontact_#{suffix}@test.example.com")
invite = Onetime::OrganizationMembership.create_invitation!(organization: org, email: member.email, role: 'member', inviter: owner)
invite.accept!(member)
m = Onetime::OrganizationMembership.find_by_org_customer(org.objid, member.objid)
m.grant_entitlement('manage_members')
m.can?('manage_members')
#=> true

## Grant persists in entitlements_grants
suffix = "#{Familia.now.to_i}_#{rand(10000)}"
owner = Onetime::Customer.create!(email: "g2owner_#{suffix}@test.example.com")
member = Onetime::Customer.create!(email: "g2member_#{suffix}@test.example.com")
org = Onetime::Organization.create!("Grant2 Test Org #{suffix}", owner, "g2contact_#{suffix}@test.example.com")
invite = Onetime::OrganizationMembership.create_invitation!(organization: org, email: member.email, role: 'member', inviter: owner)
invite.accept!(member)
m = Onetime::OrganizationMembership.find_by_org_customer(org.objid, member.objid)
m.grant_entitlement('audit_logs')
m.entitlements_grants.member?('audit_logs')
#=> true

## Role label unchanged after grant
suffix = "#{Familia.now.to_i}_#{rand(10000)}"
owner = Onetime::Customer.create!(email: "g3owner_#{suffix}@test.example.com")
member = Onetime::Customer.create!(email: "g3member_#{suffix}@test.example.com")
org = Onetime::Organization.create!("Grant3 Test Org #{suffix}", owner, "g3contact_#{suffix}@test.example.com")
invite = Onetime::OrganizationMembership.create_invitation!(organization: org, email: member.email, role: 'member', inviter: owner)
invite.accept!(member)
m = Onetime::OrganizationMembership.find_by_org_customer(org.objid, member.objid)
m.grant_entitlement('manage_members')
m.role
#=> 'member'

# =============================================================================
# can? with Symbol argument
# =============================================================================

## can? with Symbol argument works (coerced to string)
suffix = "#{Familia.now.to_i}_#{rand(10000)}"
owner = Onetime::Customer.create!(email: "sowner_#{suffix}@test.example.com")
org = Onetime::Organization.create!("Symbol Test Org #{suffix}", owner, "scontact_#{suffix}@test.example.com")
m = Onetime::OrganizationMembership.find_by_org_customer(org.objid, owner.objid)
m.can?(:manage_billing)
#=> true

## can? with unknown entitlement returns false
suffix = "#{Familia.now.to_i}_#{rand(10000)}"
owner = Onetime::Customer.create!(email: "uowner_#{suffix}@test.example.com")
org = Onetime::Organization.create!("Unknown Test Org #{suffix}", owner, "ucontact_#{suffix}@test.example.com")
m = Onetime::OrganizationMembership.find_by_org_customer(org.objid, owner.objid)
m.can?('nonexistent_entitlement')
#=> false
