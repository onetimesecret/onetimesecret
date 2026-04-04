# try/unit/auth/organization_context_try.rb
#
# frozen_string_literal: true

# Setup - Load the real application
ENV['AUTHENTICATION_MODE'] = 'simple'
ENV['VALKEY_URL'] = 'valkey://127.0.0.1:2121/0'
ENV['REDIS_URL'] = 'redis://127.0.0.1:2121/0'

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
@env['HTTP_X_ORGANIZATION_ID'] = @org2.objid

context = @strategy.load_organization_context(@cust, @session, @env)
context[:organization]&.objid
#=> @org2.objid

## Organization selection: Header override takes precedence over session
@session.clear
@session['organization_id'] = @org1.objid
@env['HTTP_X_ORGANIZATION_ID'] = @org2.objid

context = @strategy.load_organization_context(@cust, @session, @env)
context[:organization]&.objid
#=> @org2.objid

## Organization selection: Invalid header org falls through to session
@session.clear
@session['organization_id'] = @org1.objid
@env['HTTP_X_ORGANIZATION_ID'] = 'nonexistent-org-id'

context = @strategy.load_organization_context(@cust, @session, @env)
context[:organization]&.objid
#=> @org1.objid

## Organization selection: Header org without membership falls through
# Create org owned by different customer (cust2 is not a member of org3)
test_email2 = "orgcontext2-#{Time.now.to_i}@onetimesecret.com"
@cust2 = Onetime::Customer.create!(email: test_email2, role: 'customer')
@org3 = Onetime::Organization.create!('Other Workspace', @cust2)

@session.clear
@env['HTTP_X_ORGANIZATION_ID'] = @org3.objid

# @cust is NOT a member of @org3, should fall through to default
context = @strategy.load_organization_context(@cust, @session, @env)
context[:organization]&.objid
#=> @org1.objid

## Clean up header test data
@org3.destroy!
@cust2.destroy!
@env.delete('HTTP_X_ORGANIZATION_ID')

## Organization selection: Default organization priority
@session.delete('organization_id')

context = @strategy.load_organization_context(@cust, @session, @env)
context[:organization]&.objid
#=> @org1.objid

## Organization selection: Explicit session selection
@session.delete("org_context:#{@cust.objid}")  # Clear cache
@session['organization_id'] = @org2.objid

context = @strategy.load_organization_context(@cust, @session, @env)
context[:organization]&.objid
#=> @org2.objid

## Organization selection: Invalid session ID cleared
@session.delete("org_context:#{@cust.objid}")  # Clear cache
@session['organization_id'] = 'invalid-org-id'

context = @strategy.load_organization_context(@cust, @session, @env)
context[:organization]&.objid  # Should fall back to default
#=> @org1.objid

## Organization selection: Session cleared invalid ID
@session.key?('organization_id')
#=> false

## Organization selection: Session caching
@session.delete('organization_id')
@session.delete("org_context:#{@cust.objid}")

# First load - should cache
context1 = @strategy.load_organization_context(@cust, @session, @env)
cache_key = "org_context:#{@cust.objid}"
@session[cache_key]
#=: Hash

# Second load - should use cache
context2 = @strategy.load_organization_context(@cust, @session, @env)
context1[:organization]&.objid == context2[:organization]&.objid
#=> true

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

## Cache clearing
@session['organization_id'] = @org1.objid
@session["org_context:#{@cust.objid}"] = { organization: @org1 }

@strategy.clear_organization_cache(@cust, @session)
@session["org_context:#{@cust.objid}"]
#=> nil

## Clean up test data
@org1.destroy!
@org2.destroy!
@cust.destroy!
true
#=> true
