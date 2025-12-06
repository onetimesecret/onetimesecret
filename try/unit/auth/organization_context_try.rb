# try/unit/auth/organization_context_try.rb
#
# frozen_string_literal: true

# Setup - Load the real application
ENV['AUTHENTICATION_MODE'] = 'simple'
ENV['ONETIME_HOME'] ||= File.expand_path(File.join(__dir__, '..', '..', '..')).freeze

require 'rack'
require_relative '../../support/test_helpers'
require 'onetime'

## Setup: Create test customer and organizations
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

# Create teams
@team1 = Onetime::Team.create!('Alpha Team', @cust, @org1.objid)
@team2 = Onetime::Team.create!('Beta Team', @cust, @org2.objid)

@session = {}
@env = {}

## Test OrganizationLoader module inclusion
require 'onetime/application/organization_loader'

class TestAuthStrategy
  include Onetime::Application::OrganizationLoader
end

@strategy = TestAuthStrategy.new
@strategy.respond_to?(:load_organization_context)
#=> true

## Test organization selection: Default organization priority
@session.delete('organization_id')
@session.delete('team_id')

context = @strategy.load_organization_context(@cust, @session, @env)
context[:organization]&.objid
#=> @org1.objid

## Test organization selection: Explicit session selection
@session.delete("org_context:#{@cust.objid}")  # Clear cache
@session['organization_id'] = @org2.objid

context = @strategy.load_organization_context(@cust, @session, @env)
context[:organization]&.objid
#=> @org2.objid

## Test organization selection: Invalid session ID cleared
@session.delete("org_context:#{@cust.objid}")  # Clear cache
@session['organization_id'] = 'invalid-org-id'

context = @strategy.load_organization_context(@cust, @session, @env)
context[:organization]&.objid  # Should fall back to default
#=> @org1.objid

## Test organization selection: Session cleared invalid ID
@session.key?('organization_id')
#=> false

## Test organization selection: Session caching
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

## Test team selection: First team in organization
@session.delete('organization_id')
@session.delete('team_id')
@session.delete("org_context:#{@cust.objid}")

context = @strategy.load_organization_context(@cust, @session, @env)
context[:team]&.objid
#=> @team1.objid

## Test team selection: Explicit session selection
@session.delete("org_context:#{@cust.objid}")
@session['organization_id'] = @org2.objid
@session['team_id'] = @team2.objid

context = @strategy.load_organization_context(@cust, @session, @env)
context[:team]&.objid
#=> @team2.objid

## Test team selection: Invalid team ID cleared
@session.delete("org_context:#{@cust.objid}")
@session['organization_id'] = @org1.objid
@session['team_id'] = 'invalid-team-id'

context = @strategy.load_organization_context(@cust, @session, @env)
context[:team]&.objid  # Should fall back to first team
#=> @team1.objid

## Test team selection: Invalid team ID cleared from session
@session['team_id']  # Should clear invalid ID
#=> nil

## Test anonymous user: Returns empty context
@session.clear
context = @strategy.load_organization_context(Onetime::Customer.anonymous, @session, @env)
context
#=> {}

## Test nil customer: Returns empty context
context = @strategy.load_organization_context(nil, @session, @env)
context
#=> {}

## Test cache clearing
@session['organization_id'] = @org1.objid
@session["org_context:#{@cust.objid}"] = { organization: @org1 }

@strategy.clear_organization_cache(@cust, @session)
@session["org_context:#{@cust.objid}"]
#=> nil

## Teardown: Clean up test data
@team1.destroy!
@team2.destroy!
@org1.destroy!
@org2.destroy!
@cust.destroy!
true
#=> true
