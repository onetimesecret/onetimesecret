# try/unit/models/custom_domain_destroy_cascade_try.rb
#
# frozen_string_literal: true

#
# Tests that CustomDomain.destroy! cascades to:
# 1. Domain-specific configs (SsoConfig, MailerConfig, IncomingConfig)
# 2. Domain-scoped memberships (SSO-provisioned users restricted to this domain)
#
# After destroy!, all associated resources should be cleaned up.

require_relative '../../support/test_helpers'

OT.boot! :test

@owner = Onetime::Customer.create!(email: generate_unique_test_email("cascade_owner"))
@org = Onetime::Organization.create!("Cascade Test Org", @owner, generate_unique_test_email("cascade_contact"))
@domain = Onetime::CustomDomain.create!("cascade-test.example.com", @org.objid)
@domain_id = @domain.identifier

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

## Destroy the domain (triggers cascade)
@domain.destroy!
true
#=> true

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


# Cleanup
[@org, @owner, @scoped_user_a, @scoped_user_b, @org_member].each do |obj|
  obj.destroy! if obj&.respond_to?(:destroy!) && obj.exists?
end
