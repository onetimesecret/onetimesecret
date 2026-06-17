# try/unit/models/organization_membership_domain_scope_try.rb
#
# frozen_string_literal: true

#
# Tests domain_scope_id on OrganizationMembership
#
# Validates the three predicates added for SSO-provisioned user isolation:
# - org_scoped?: true when domain_scope_id is nil/empty (full org access)
# - domain_scoped?: true when domain_scope_id is set (scoped to one domain)
# - can_access_domain?(domain): authorization check combining both
#
# Also validates that ensure_membership propagates domain_scope_id.

require_relative '../../support/test_helpers'

OT.boot! :test

@owner = Onetime::Customer.create!(email: generate_unique_test_email("dscope_owner"))
@org = Onetime::Organization.create!("Domain Scope Test Org", @owner, generate_unique_test_email("dscope_contact"))

# Shared domain identifiers (using realistic objid-style strings)
@domain_a_objid = "cust_domain_#{SecureRandom.hex(8)}"
@domain_b_objid = "cust_domain_#{SecureRandom.hex(8)}"

# Domain-like objects for can_access_domain? which expects domain.objid
@domain_a = OpenStruct.new(objid: @domain_a_objid)
@domain_b = OpenStruct.new(objid: @domain_b_objid)


# =============================================================================
# org_scoped? / domain_scoped? Predicate Tests
# =============================================================================

## org_scoped? is true when domain_scope_id is nil
@owner_membership = Onetime::OrganizationMembership.find_by_org_customer(@org.objid, @owner.objid)
@owner_membership.org_scoped?
#=> true

## domain_scoped? is false when domain_scope_id is nil
@owner_membership.domain_scoped?
#=> false

## org_scoped? is true when domain_scope_id is empty string
@owner_membership.domain_scope_id = ''
@owner_membership.org_scoped?
#=> true

## domain_scoped? is false when domain_scope_id is empty string
@owner_membership.domain_scoped?
#=> false

## Restore nil for subsequent tests
@owner_membership.domain_scope_id = nil

## domain_scoped? is true when domain_scope_id is set
@scoped_customer = Onetime::Customer.create!(email: generate_unique_test_email("dscope_scoped"))
@scoped_result = Onetime::OrganizationMembership.ensure_membership(@org, @scoped_customer, domain_scope_id: @domain_a_objid)
@scoped_result.domain_scoped?
#=> true

## org_scoped? is false when domain_scope_id is set
@scoped_result.org_scoped?
#=> false

## domain_scope_id value matches what was set
@scoped_result.domain_scope_id
#=> @domain_a_objid


# =============================================================================
# can_access_domain? Tests
# =============================================================================

## can_access_domain? returns true for org-scoped member (any domain)
@owner_membership.can_access_domain?(@domain_a)
#=> true

## can_access_domain? returns true for org-scoped member with different domain
@owner_membership.can_access_domain?(@domain_b)
#=> true

## can_access_domain? returns true for matching domain scope
@scoped_result.can_access_domain?(@domain_a)
#=> true

## can_access_domain? returns false for non-matching domain scope
@scoped_result.can_access_domain?(@domain_b)
#=> false

## can_access_domain?(nil) returns false for org-scoped member (fail closed)
@owner_membership.can_access_domain?(nil)
#=> false

## can_access_domain?(nil) returns false for domain-scoped member (fail closed)
@scoped_result.can_access_domain?(nil)
#=> false


# =============================================================================
# ensure_membership with domain_scope_id Tests
# =============================================================================

## ensure_membership with domain_scope_id persists the scope
@ds_customer = Onetime::Customer.create!(email: generate_unique_test_email("dscope_ensure"))
@ds_result = Onetime::OrganizationMembership.ensure_membership(@org, @ds_customer, domain_scope_id: @domain_b_objid)
@ds_result.domain_scope_id
#=> @domain_b_objid

## ensure_membership with domain_scope_id creates active membership
@ds_result.active?
#=> true

## ensure_membership with domain_scope_id: membership is domain-scoped
@ds_result.domain_scoped?
#=> true

## ensure_membership without domain_scope_id creates org-scoped membership
@orgscoped_customer = Onetime::Customer.create!(email: generate_unique_test_email("dscope_orgscoped"))
@orgscoped_result = Onetime::OrganizationMembership.ensure_membership(@org, @orgscoped_customer)
@orgscoped_result.org_scoped?
#=> true

## ensure_membership without domain_scope_id: domain_scope_id is nil or empty
@orgscoped_result.domain_scope_id.to_s.empty?
#=> true

## Idempotent: re-calling ensure_membership for existing member returns same membership
@existing_objid = @ds_result.objid
@idem_result = Onetime::OrganizationMembership.ensure_membership(@org, @ds_customer, domain_scope_id: @domain_b_objid)
@idem_result.objid == @existing_objid
#=> true


# =============================================================================
# accept! carries domain_scope_id from invitation to active membership
# =============================================================================

## Invitation with domain_scope_id: accepted membership retains scope
@invite_customer = Onetime::Customer.create!(email: generate_unique_test_email("dscope_invited"))
@invite = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @invite_customer.email,
  role: 'member',
  inviter: @owner
)
@invite.domain_scope_id = @domain_a_objid
@invite.save
@invite.accept!(@invite_customer)
@activated = Onetime::OrganizationMembership.find_by_org_customer(@org.objid, @invite_customer.objid)
@activated.domain_scope_id
#=> @domain_a_objid

## Activated membership is domain-scoped
@activated.domain_scoped?
#=> true

## Activated membership can access the scoped domain
@activated.can_access_domain?(@domain_a)
#=> true

## Activated membership cannot access a different domain
@activated.can_access_domain?(@domain_b)
#=> false


# =============================================================================
# SsoConfig.grant_org_scope? predicate and conditional scope derivation (#3384)
# =============================================================================

## grant_org_scope? defaults to false on a new SsoConfig
@default_sso_config = Onetime::CustomDomain::SsoConfig.new(domain_id: @domain_a_objid)
@default_sso_config.grant_org_scope?
#=> false

## grant_org_scope? returns true when set to 'true'
@orgscope_sso_config = Onetime::CustomDomain::SsoConfig.new(domain_id: @domain_b_objid, grant_org_scope: 'true')
@orgscope_sso_config.grant_org_scope?
#=> true

## grant_org_scope? returns false when set to 'false' explicitly
@noscope_sso_config = Onetime::CustomDomain::SsoConfig.new(domain_id: @domain_a_objid, grant_org_scope: 'false')
@noscope_sso_config.grant_org_scope?
#=> false

## Conditional scope: grant_org_scope true yields nil (org-scoped)
@scope_id_when_granted = @orgscope_sso_config.grant_org_scope? ? nil : @domain_b_objid
@scope_id_when_granted.nil?
#=> true

## Conditional scope: grant_org_scope false yields domain objid (domain-scoped)
@scope_id_when_default = @default_sso_config.grant_org_scope? ? nil : @domain_a_objid
@scope_id_when_default
#=> @domain_a_objid

## ensure_membership with grant_org_scope=true produces org-scoped member
@grant_customer = Onetime::Customer.create!(email: generate_unique_test_email("dscope_grant"))
@grant_scope_id = @orgscope_sso_config.grant_org_scope? ? nil : @domain_b_objid
@grant_result = Onetime::OrganizationMembership.ensure_membership(@org, @grant_customer, domain_scope_id: @grant_scope_id)
@grant_result.org_scoped?
#=> true

## ensure_membership with grant_org_scope=false produces domain-scoped member
@deny_customer = Onetime::Customer.create!(email: generate_unique_test_email("dscope_deny"))
@deny_scope_id = @default_sso_config.grant_org_scope? ? nil : @domain_a_objid
@deny_result = Onetime::OrganizationMembership.ensure_membership(@org, @deny_customer, domain_scope_id: @deny_scope_id)
@deny_result.domain_scoped?
#=> true

## domain_scope_id matches the domain objid when grant_org_scope is false
@deny_result.domain_scope_id
#=> @domain_a_objid


# Cleanup
[@org, @owner, @scoped_customer, @ds_customer, @orgscoped_customer, @invite_customer, @grant_customer, @deny_customer].each do |obj|
  obj.destroy! if obj&.respond_to?(:destroy!) && obj.exists?
end
