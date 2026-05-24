# try/unit/models/organization_membership_provisioning_source_try.rb
#
# frozen_string_literal: true

#
# Tests OrganizationMembership#provisioning_source — lifecycle attribution
# independent of role. Verifies the field persists, defaults to nil, and
# threads correctly through accept! and ensure_membership.
#
# Issue #3033 v4: provisioning_source is the per-membership lifecycle field
# that replaces the v3 Customer#signup_method idea.

require_relative '../../support/test_helpers'

OT.boot! :test

@owner = Onetime::Customer.create!(email: generate_unique_test_email("psrc_owner"))
@org = Onetime::Organization.create!("Provisioning Source Test Org", @owner, generate_unique_test_email("psrc_contact"))

## Self-created owner row defaults to nil (no upstream provisioning attribution)
@owner_membership = Onetime::OrganizationMembership.find_by_org_customer(@org.objid, @owner.objid)
@owner_membership.provisioning_source
#=> nil

## accept! propagates provisioning_source through activation
@invited = Onetime::Customer.create!(email: generate_unique_test_email("psrc_invited"))
@invite = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @invited.email,
  role: 'member',
  inviter: @owner,
)
@invite.accept!(@invited, provisioning_source: 'invited')
@invited_membership = Onetime::OrganizationMembership.find_by_org_customer(@org.objid, @invited.objid)
@invited_membership.provisioning_source
#=> "invited"

## accept! without provisioning_source kwarg leaves the field nil
@legacy = Onetime::Customer.create!(email: generate_unique_test_email("psrc_legacy"))
@legacy_invite = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @legacy.email,
  role: 'member',
  inviter: @owner,
)
@legacy_invite.accept!(@legacy)
@legacy_membership = Onetime::OrganizationMembership.find_by_org_customer(@org.objid, @legacy.objid)
@legacy_membership.provisioning_source
#=> nil

## ensure_membership direct-add path records provisioning_source
@sso_direct = Onetime::Customer.create!(email: generate_unique_test_email("psrc_sso_direct"))
@sso_direct_membership = Onetime::OrganizationMembership.ensure_membership(
  @org, @sso_direct,
  role: 'member',
  provisioning_source: 'sso',
)
@sso_direct_membership.provisioning_source
#=> "sso"

## ensure_membership activate-pending path also records provisioning_source
@sso_pending = Onetime::Customer.create!(email: generate_unique_test_email("psrc_sso_pending"))
Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @sso_pending.email,
  role: 'member',
  inviter: @owner,
)
@sso_pending_membership = Onetime::OrganizationMembership.ensure_membership(
  @org, @sso_pending,
  role: 'member',
  provisioning_source: 'sso',
)
@sso_pending_membership.provisioning_source
#=> "sso"

## ensure_membership without provisioning_source kwarg leaves it nil
@bare = Onetime::Customer.create!(email: generate_unique_test_email("psrc_bare"))
@bare_membership = Onetime::OrganizationMembership.ensure_membership(@org, @bare, role: 'member')
@bare_membership.provisioning_source
#=> nil

## Idempotent re-call doesn't overwrite an existing membership's source
@idempotent_membership = Onetime::OrganizationMembership.ensure_membership(
  @org, @sso_direct,
  role: 'member',
  provisioning_source: 'scim',
)
@idempotent_membership.provisioning_source
#=> "sso"

## safe_dump exposes provisioning_source
@dump = @invited_membership.safe_dump
@dump[:provisioning_source]
#=> "invited"
