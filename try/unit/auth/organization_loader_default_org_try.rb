# try/unit/auth/organization_loader_default_org_try.rb
#
# frozen_string_literal: true

# Tests for OrganizationLoader respecting Customer.default_org_id
#
# Verifies that when a customer has default_org_id set, OrganizationLoader
# prioritizes that org over the org's is_default flag.

require_relative '../../support/test_helpers'

OT.boot! :test, false

# Include the module in a test class
class TestLoader
  include Onetime::Application::OrganizationLoader
end

@loader = TestLoader.new
@cust = nil
@personal_workspace = nil
@company_org = nil

## Setup - create customer and two organizations
@cust = Onetime::Customer.create!(email: "loader-test-#{SecureRandom.hex(4)}@example.com")
@cust.exists?
#=> true

## Create personal workspace (is_default = true)
@personal_workspace = Onetime::Organization.create!(
  'Personal Workspace',
  @cust,
  @cust.email
)
@personal_workspace.is_default = true
@personal_workspace.save
@personal_workspace.is_default.to_s
#=> "true"

## Create company organization (is_default = false)
@company_org = Onetime::Organization.create!(
  'ACME Corp',
  @cust,
  "acme-#{SecureRandom.hex(4)}@example.com"
)
# Add the customer as a member (create! makes them owner, not a member of their personal ws)
@company_org.add_members_instance(@cust, through_attrs: { role: 'member' })
@company_org.member?(@cust)
#=> true

## Without default_org_id, should use org with is_default flag
@cust.default_org_id.nil?
#=> true

## Determine org selects personal workspace (is_default=true)
@context = @loader.load_organization_context(@cust, {}, {})
@context[:organization].objid == @personal_workspace.objid
#=> true

## Set customer's default_org_id to company org
@cust.default_org_id = @company_org.objid
@cust.save
@cust.default_org_id == @company_org.objid
#=> true

## Now determine org should select company org (respects default_org_id)
# Need fresh session to avoid cache
@context2 = @loader.load_organization_context(@cust, {}, {})
@context2[:organization].objid == @company_org.objid
#=> true

## Clear default_org_id, should fall back to is_default org
@cust.default_org_id = nil
@cust.save
@context3 = @loader.load_organization_context(@cust, {}, {})
@context3[:organization].objid == @personal_workspace.objid
#=> true

## CLEANUP
@cust&.destroy!
@personal_workspace&.destroy!
@company_org&.destroy!
true
#=> true
