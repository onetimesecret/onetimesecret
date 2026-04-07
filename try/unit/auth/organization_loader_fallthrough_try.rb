# try/unit/auth/organization_loader_fallthrough_try.rb
#
# frozen_string_literal: true

#
# Tests the fall-through bypass fix in OrganizationLoader#determine_organization.
#
# Scenario: A domain-scoped member is denied access at step 2 (domain-based
# selection). Steps 3-5 must NOT return that same org via customer.organization_instances,
# is_default, or first-available fallback. The denied org's objid is excluded.

require_relative '../../support/test_helpers'

OT.boot! :test

# Build a test harness that includes OrganizationLoader so we can call
# determine_organization directly (it is a private method).
class OrgLoaderHarness
  include Onetime::Application::OrganizationLoader
  public :determine_organization
end

@loader = OrgLoaderHarness.new

@owner = Onetime::Customer.create!(email: generate_unique_test_email("loader_owner"))
@org = Onetime::Organization.create!("Loader Test Org", @owner, generate_unique_test_email("loader_contact"))

# Create a custom domain and register it in the display_domains index
@domain = Onetime::CustomDomain.create!("loader-test.example.com", @org.objid)

# Create a domain-scoped member who can only access a *different* domain
@scoped_user = Onetime::Customer.create!(email: generate_unique_test_email("loader_scoped"))
@other_domain_objid = "cust_domain_#{SecureRandom.hex(8)}"
@scoped_membership = Onetime::OrganizationMembership.ensure_membership(
  @org, @scoped_user,
  domain_scope_id: @other_domain_objid
)


## Domain-scoped member denied at step 2 does NOT receive org from fallback steps
# Simulate a request to loader-test.example.com by the scoped user who is
# scoped to a different domain. Without the fix, the org would be returned
# via steps 3-5 (first-available fallback). With the fix, nil is returned.
env = { 'HTTP_HOST' => 'loader-test.example.com' }
result = @loader.determine_organization(@scoped_user, {}, env)
result.nil?
#=> true

## Org-scoped (full access) member still gets org via domain-based selection
env = { 'HTTP_HOST' => 'loader-test.example.com' }
result = @loader.determine_organization(@owner, {}, env)
result.objid == @org.objid
#=> true

## Domain-scoped member with matching domain gets org via domain-based selection
@matching_user = Onetime::Customer.create!(email: generate_unique_test_email("loader_matching"))
Onetime::OrganizationMembership.ensure_membership(
  @org, @matching_user,
  domain_scope_id: @domain.objid
)
env = { 'HTTP_HOST' => 'loader-test.example.com' }
result = @loader.determine_organization(@matching_user, {}, env)
result.objid == @org.objid
#=> true

## Without HTTP_HOST (no domain context), scoped member still gets org via fallback
# When there is no domain in the request, step 2 is skipped entirely,
# so no denial occurs and the org is available via steps 3-5.
result = @loader.determine_organization(@scoped_user, {}, {})
result.objid == @org.objid
#=> true


# Cleanup
[@domain, @org, @owner, @scoped_user, @matching_user].each do |obj|
  obj.destroy! if obj&.respond_to?(:destroy!) && obj.exists?
end
