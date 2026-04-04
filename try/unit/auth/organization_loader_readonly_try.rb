# try/unit/auth/organization_loader_readonly_try.rb
#
# frozen_string_literal: true

# Tests for OrganizationLoader read-only behavior during auth phase
#
# Issue #2880: Remove write operations from OrganizationLoader auth phase
#
# These tests verify that determine_organization:
# - Returns nil for users with no organizations
# - Does NOT create an organization (no Redis writes during auth)
# - Auth completes successfully even with nil organization
#
# Run: bundle exec try try/unit/auth/organization_loader_readonly_try.rb

require_relative '../../support/test_helpers'
require 'onetime/application/organization_loader'

OT.boot! :test

# Test class that includes OrganizationLoader for testing
class TestLoaderStrategy
  include Onetime::Application::OrganizationLoader

  # Expose private method for testing
  def test_determine_organization(customer, session, env)
    determine_organization(customer, session, env)
  end
end

# Setup test data
@test_suffix = "#{Familia.now.to_i}_#{rand(10000)}"

# Create customer WITHOUT any organizations
@email = "loader_readonly_#{@test_suffix}@onetimesecret.com"
@customer = Onetime::Customer.create!(email: @email, role: 'customer')

# Create a second customer WITH an organization (for contrast tests)
@email_with_org = "loader_with_org_#{@test_suffix}@onetimesecret.com"
@customer_with_org = Onetime::Customer.create!(email: @email_with_org, role: 'customer')
@existing_org = Onetime::Organization.create!(
  'Existing Org',
  @customer_with_org,
  @email_with_org,
  is_default: true
)

# Initialize loader
@loader = TestLoaderStrategy.new
@env = {}

## Test setup: Customer without org starts with zero organizations
@customer.organization_instances.count
#=> 0

## Initialize loader and session for tests
@session = {}
[@loader.class, @session.class]
#=> [TestLoaderStrategy, Hash]

## determine_organization returns nil for user with no organizations
result = @loader.test_determine_organization(@customer, @session, @env)
result.nil?
#=> true

## No organization was created during determine_organization call
@customer.organization_instances.count
#=> 0

## load_organization_context returns hash with nil organization
context = @loader.load_organization_context(@customer, @session, @env)
[context.class, context[:organization].nil?]
#=> [Hash, true]

## load_organization_context provides required structure
context = @loader.load_organization_context(@customer, @session, @env)
context.key?(:organization) && context.key?(:organization_id)
#=> true

## organization_id is nil when no organization exists
context = @loader.load_organization_context(@customer, @session, @env)
context[:organization_id].nil?
#=> true

## Nil organization means session does NOT cache (allows immediate retry)
# Clear session first
@session.clear
@loader.load_organization_context(@customer, @session, @env)
cache_key = "org_context:#{@customer.objid}"
# Nil orgs are NOT cached to allow immediate retry on failure
@session[cache_key].nil?
#=> true

## Repeated calls still return nil without creating org
context2 = @loader.load_organization_context(@customer, @session, @env)
[context2[:organization].nil?, @customer.organization_instances.count]
#=> [true, 0]

## Invalid session selection is cleared, returns nil
@session.clear
@session['organization_id'] = 'nonexistent_org_id'
context4 = @loader.load_organization_context(@customer, @session, @env)
[@session.key?('organization_id'), context4[:organization].nil?]
#=> [false, true]

## Customer with existing org gets that org returned
@session_with_org = {}
context_with_org = @loader.load_organization_context(@customer_with_org, @session_with_org, @env)
context_with_org[:organization]&.objid
#=> @existing_org.objid

## Customer with org has cached entry in session (positive result)
cache_key_with_org = "org_context:#{@customer_with_org.objid}"
@session_with_org[cache_key_with_org].class
#=> Hash

## Customer with org still has exactly one org after load
@customer_with_org.organization_instances.count
#=> 1

# Test domain-based selection with no matching org
@env_with_domain = { 'HTTP_HOST' => 'unknown.example.com:3000' }

## Domain-based lookup falls through when no matching org
context_domain = @loader.load_organization_context(@customer, {}, @env_with_domain)
context_domain[:organization].nil?
#=> true

## Still no organization created after domain lookup
@customer.organization_instances.count
#=> 0

# Teardown
@existing_org.destroy! if @existing_org&.exists?
@customer_with_org.destroy! if @customer_with_org&.exists?
@customer.destroy! if @customer&.exists?
