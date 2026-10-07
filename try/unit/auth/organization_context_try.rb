# try/unit/auth/organization_context_try.rb
#
# frozen_string_literal: true

# Setup - Load the real application
# (datastore URLs come from test_helpers, which derives the per-worktree DB)
ENV['AUTHENTICATION_MODE'] = 'simple'

require 'rack'
require_relative '../../support/test_helpers'
require 'onetime'

# Create test customer and organizations
test_email = "orgcontext-#{Time.now.to_i}@onetimesecret.com"
@cust = Onetime::Customer.create!(
  email: test_email,
  role: 'customer'
)

# Create organizations (use different contact emails to avoid unique index conflicts)
@org1 = Onetime::Organization.create!('Primary Workspace', @cust)
@org1.is_default = true
@org1.save

@org2 = Onetime::Organization.create!('Secondary Workspace', @cust)

@session = {}
@env = {}

## OrganizationLoader module inclusion
require 'onetime/application/organization_loader'

class TestAuthStrategy
  include Onetime::Application::OrganizationLoader
end

@strategy = TestAuthStrategy.new
@strategy.respond_to?(:load_organization_context)
#=> true

## Organization selection: Header override with valid membership
@session.clear
@env['HTTP_O_ORGANIZATION_ID'] = @org2.objid

context = @strategy.load_organization_context(@cust, @session, @env)
context[:organization]&.objid
#=> @org2.objid

## Organization selection: Header override takes precedence over session
@session.clear
@session['organization_id'] = @org1.objid
@env['HTTP_O_ORGANIZATION_ID'] = @org2.objid

context = @strategy.load_organization_context(@cust, @session, @env)
context[:organization]&.objid
#=> @org2.objid

## Organization selection: Invalid header org falls through to session
@session.clear
@session['organization_id'] = @org1.objid
@env['HTTP_O_ORGANIZATION_ID'] = 'nonexistent-org-id'

context = @strategy.load_organization_context(@cust, @session, @env)
context[:organization]&.objid
#=> @org1.objid

## Organization selection: Header org without membership falls through
# Create org owned by different customer (cust2 is not a member of org3)
test_email2 = "orgcontext2-#{Time.now.to_i}@onetimesecret.com"
@cust2 = Onetime::Customer.create!(email: test_email2, role: 'customer')
@org3 = Onetime::Organization.create!('Other Workspace', @cust2)

@session.clear
@env['HTTP_O_ORGANIZATION_ID'] = @org3.objid

# @cust is NOT a member of @org3, should fall through to default
context = @strategy.load_organization_context(@cust, @session, @env)
context[:organization]&.objid
#=> @org1.objid

## Clean up header test data
@org3.destroy!
@cust2.destroy!
@env.delete('HTTP_O_ORGANIZATION_ID')

## Organization selection: Default organization priority
@session.delete('organization_id')

context = @strategy.load_organization_context(@cust, @session, @env)
context[:organization]&.objid
#=> @org1.objid

## Organization selection: Explicit session selection
@session['organization_id'] = @org2.objid

context = @strategy.load_organization_context(@cust, @session, @env)
context[:organization]&.objid
#=> @org2.objid

## Organization selection: Invalid session ID cleared
@session['organization_id'] = 'invalid-org-id'

context = @strategy.load_organization_context(@cust, @session, @env)
context[:organization]&.objid  # Should fall back to default
#=> @org1.objid

## Organization selection: Session cleared invalid ID
@session.key?('organization_id')
#=> false

## No session cache: a load writes nothing to the session
@session.clear
@context1 = @strategy.load_organization_context(@cust, @session, @env)
@session
#=> {}

## No session cache: a repeated load resolves the same organization
@context2 = @strategy.load_organization_context(@cust, @session, @env)
@context1[:organization]&.objid == @context2[:organization]&.objid
#=> true

## No session cache: a leftover org_context entry from an older session is not read
@session.clear
@session["org_context:#{@cust.objid}"] = {
  'organization_id' => @org2.objid, 'expires_at' => Familia.now.to_i + 300
}
context = @strategy.load_organization_context(@cust, @session, @env)
context[:organization]&.objid
#=> @org1.objid

## Anonymous user with role 'anonymous': Returns empty context
@session.clear
anon_cust = Onetime::Customer.new(role: 'anonymous')
context = @strategy.load_organization_context(anon_cust, @session, @env)
context
#=> {}

## Nil customer: Returns empty context
context = @strategy.load_organization_context(nil, @session, @env)
context
#=> {}

## Context shape: no cache expiry, and no custom domains on a canonical request
@session.clear
context = @strategy.load_organization_context(@cust, @session, @env)
[context.key?(:expires_at), context[:scope_domains]]
#=> [false, []]

## select_organization: records the selection for a member
@session.clear
@select_context = @strategy.load_organization_context(@cust, @session, @env)
selected = @strategy.select_organization(@cust, @session, @org2.objid, @select_context)
[selected&.objid, @session['organization_id']]
#=> [@org2.objid, @org2.objid]

## select_organization: the next load without a header resolves the selection
context = @strategy.load_organization_context(@cust, @session, @env)
context[:organization]&.objid
#=> @org2.objid

## select_organization: callable on the module, without mixing it in
@module_session = {}
selected = Onetime::Application::OrganizationLoader.select_organization(
  @cust, @module_session, @org2.objid, @select_context
)
[selected&.objid, @module_session['organization_id']]
#=> [@org2.objid, @org2.objid]

## select_organization: refuses an organization the customer is not a member of
@stranger = Onetime::Customer.create!(email: "orgcontext3-#{Time.now.to_i}@onetimesecret.com", role: 'customer')
@org4 = Onetime::Organization.create!('Stranger Workspace', @stranger)
selected = @strategy.select_organization(@cust, @session, @org4.objid, @select_context)
[selected, @session['organization_id']]
#=> [nil, @org2.objid]

## select_organization: refuses an unknown organization id
selected = @strategy.select_organization(@cust, @session, 'nonexistent-org-id', @select_context)
[selected, @session['organization_id']]
#=> [nil, @org2.objid]

## select_organization: refuses without the request's context (scope unknown)
@no_context_session = {}
[
  @strategy.select_organization(@cust, @no_context_session, @org2.objid, nil),
  @strategy.select_organization(@cust, @no_context_session, @org2.objid, {}),
  @no_context_session,
]
#=> [nil, nil, {}]

## select_organization: refuses an archived organization
@org2.archive!('organization_context_try')
@archived_session = {}
selected = @strategy.select_organization(@cust, @archived_session, @org2.objid, @select_context)
[@org2.archived?, selected, @archived_session]
#=> [true, nil, {}]

## Archived selection: a selection made before the archive is cleared on the next load
context = @strategy.load_organization_context(@cust, @session, @env)
[context[:organization]&.objid, @session.key?('organization_id')]
#=> [@org1.objid, false]

## Archived header: the header no longer selects the archived organization
@session.clear
context = @strategy.load_organization_context(@cust, @session, { 'HTTP_O_ORGANIZATION_ID' => @org2.objid })
context[:organization]&.objid
#=> @org1.objid

## Deleted selection: a selected organization that is then deleted falls back and is cleared
@doomed_org = Onetime::Organization.create!('Doomed Workspace', @cust)
@doomed_session = {}
@doomed_context = @strategy.load_organization_context(@cust, @doomed_session, @env)
@strategy.select_organization(@cust, @doomed_session, @doomed_org.objid, @doomed_context)
@doomed_selected = @doomed_session['organization_id']
@doomed_org.destroy!
context = @strategy.load_organization_context(@cust, @doomed_session, @env)
[@doomed_selected == @doomed_org.objid, context[:organization]&.objid, @doomed_session.key?('organization_id')]
#=> [true, @org1.objid, false]

## Deleted selection: the header no longer selects the deleted organization either
context = @strategy.load_organization_context(@cust, {}, { 'HTTP_O_ORGANIZATION_ID' => @doomed_org.objid })
context[:organization]&.objid
#=> @org1.objid

## Clean up selection test data
@org4.destroy!
@stranger.destroy!
true
#=> true

## Clean up test data
@org1.destroy!
@org2.destroy!
@cust.destroy!
true
#=> true
