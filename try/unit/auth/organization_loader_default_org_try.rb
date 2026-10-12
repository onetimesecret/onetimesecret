# try/unit/auth/organization_loader_default_org_try.rb
#
# frozen_string_literal: true

# Tests for OrganizationLoader respecting Customer.default_org_id
#
# Verifies that when a customer has default_org_id set, OrganizationLoader
# prioritizes that org over the org's is_default flag, and that the
# is_default fallback only counts a workspace the customer owns
# (OrganizationLoader.default_organization).

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
# Nothing is carried over from the previous load
@context2 = @loader.load_organization_context(@cust, {}, {})
@context2[:organization].objid == @company_org.objid
#=> true

## Clear default_org_id, should fall back to is_default org
@cust.default_org_id = nil
@cust.save
@context3 = @loader.load_organization_context(@cust, {}, {})
@context3[:organization].objid == @personal_workspace.objid
#=> true

## Step 5 (first-available fallback) skips archived orgs
# Archive both orgs. With no default_org_id (step 3) and no non-archived
# is_default org (step 4), the first-available fallback must NOT hand back
# an archived "soft-deleted" org — it falls through to nil (step 6).
@personal_workspace.archive!('superseded in test')
@company_org.archive!('superseded in test')
@context4 = @loader.load_organization_context(@cust, {}, {})
@context4[:organization].nil?
#=> true

## A member of another customer's default workspace: it carries is_default, but not as theirs
@admin = Onetime::Customer.create!(email: "loader-admin-#{SecureRandom.hex(4)}@example.com")
@member = Onetime::Customer.create!(email: "loader-member-#{SecureRandom.hex(4)}@example.com")
@admin_default = Onetime::Organization.create!('Admin Default', @admin, nil, is_default: true)
@admin_default.add_members_instance(@member, through_attrs: { role: 'member' })
[@admin_default.is_default, @admin_default.member?(@member), @admin_default.owner?(@member)]
#=> [true, true, false]

## default_organization does not return someone else's default workspace
Onetime::Application::OrganizationLoader.default_organization(@member)
#=> nil

## The loader skips it at step 4 and still reaches it as the first organization (step 5)
@loader.load_organization_context(@member, {}, {})[:organization].objid == @admin_default.objid
#=> true

## With a default workspace of their own, that one is the default, whatever the membership order
@member_default = Onetime::Organization.create!('Member Default', @member, nil, is_default: true)
[
  Onetime::Application::OrganizationLoader.default_organization(@member)&.objid == @member_default.objid,
  @loader.load_organization_context(@member, {}, {})[:organization].objid == @member_default.objid,
]
#=> [true, true]

## default_org_id names the default, including another owner's workspace
@member.default_org_id = @admin_default.objid
@member.save
[
  Onetime::Application::OrganizationLoader.default_organization(@member)&.objid == @admin_default.objid,
  @loader.load_organization_context(@member, {}, {})[:organization].objid == @admin_default.objid,
]
#=> [true, true]

## default_organization chooses only among the organizations it is given
Onetime::Application::OrganizationLoader.default_organization(@member, [@member_default])&.objid == @member_default.objid
#=> true

## CLEANUP
@cust&.destroy!
@personal_workspace&.destroy!
@company_org&.destroy!
@admin_default&.destroy!
@member_default&.destroy!
@admin&.destroy!
@member&.destroy!
true
#=> true
