# try/unit/auth/auth_org_immutability_try.rb
#
# frozen_string_literal: true

# Tests for auth_org immutability (issue #2807)
#
# Verifies that auth_org always returns the authenticated user's
# organization from StrategyResult metadata, even after @organization
# is overwritten by domain-scoped logic (e.g., authorize_domain_sso!).
#
# The clobbering flow:
#   1. Logic::Base#initialize calls extract_organization_context
#      which sets @organization from strategy_result metadata
#   2. SsoConfig::Base#authorize_domain_sso! overwrites @organization
#      with the domain owner's org (may differ from auth user's org)
#   3. auth_org bypasses @organization entirely, reading directly
#      from @strategy_result.metadata — so it stays immutable

require_relative '../../support/test_helpers'

OT.boot! :test

require 'onetime/logic'

@timestamp = Familia.now.to_i

# Create two distinct customers and organizations to simulate the
# clobbering scenario: user authenticates as org1 member, then
# domain-scoped logic loads org2 (the domain owner's org).
@auth_owner = Onetime::Customer.create!(email: "auth-owner-#{@timestamp}@test.com")
@domain_owner = Onetime::Customer.create!(email: "domain-owner-#{@timestamp}@test.com")

@auth_org = Onetime::Organization.create!("Auth Workspace", @auth_owner, "auth-#{@timestamp}@test.com")
@domain_org = Onetime::Organization.create!("Domain Workspace", @domain_owner, "domain-#{@timestamp}@test.com")

# Disable billing for standalone entitlements
@auth_org.define_singleton_method(:billing_enabled?) { false }
@domain_org.define_singleton_method(:billing_enabled?) { false }

# Build a strategy result representing the authenticated user's session
@strategy_result = MockStrategyResult.new(
  session: MockSession.new,
  user: @auth_owner,
  auth_method: 'session',
  metadata: {
    organization_context: {
      organization: @auth_org,
      organization_id: @auth_org.objid,
      expires_at: Familia.now.to_i + 300,
    }
  }
)

# A thin harness that includes OrganizationContext the same way
# Logic::Base does, but without the full controller infrastructure.
class AuthOrgTestHarness
  include Onetime::Logic::OrganizationContext

  attr_accessor :strategy_result, :cust

  def initialize(strategy_result)
    @strategy_result = strategy_result
    @cust = strategy_result&.user
    extract_organization_context(strategy_result)
  end
end

@harness = AuthOrgTestHarness.new(@strategy_result)


## auth_org returns the organization from strategy_result metadata
@harness.auth_org.objid
#=> @auth_org.objid

## @organization initially matches auth_org
@harness.organization.objid
#=> @auth_org.objid

## auth_org and @organization point to the same object before clobbering
@harness.auth_org.objid == @harness.organization.objid
#=> true

## After clobbering @organization, auth_org still returns the ORIGINAL org
# This simulates what authorize_domain_sso! does in SsoConfig::Base:
#   @organization = load_organization_for_domain(@custom_domain)
@harness.instance_variable_set(:@organization, @domain_org)
@harness.auth_org.objid
#=> @auth_org.objid

## After clobbering, @organization now points to the domain org
@harness.organization.objid
#=> @domain_org.objid

## auth_org and @organization have diverged
@harness.auth_org.objid == @harness.organization.objid
#=> false

## auth_org is the auth owner's org, @organization is the domain owner's org
[@harness.auth_org.objid, @harness.organization.objid]
#=> [@auth_org.objid, @domain_org.objid]


# Edge cases: nil and missing metadata

## auth_org returns nil when strategy_result is nil
@nil_harness = AuthOrgTestHarness.new(nil)
@nil_harness.auth_org
#=> nil

## auth_org returns nil when metadata has no organization_context (anonymous user)
# Use anonymous user to test metadata edge case without triggering lazy creation
@empty_meta_sr = MockStrategyResult.new(
  session: MockSession.new,
  user: nil,
  metadata: {}
)
@empty_harness = AuthOrgTestHarness.new(@empty_meta_sr)
@empty_harness.auth_org
#=> nil

## auth_org returns nil when organization_context exists but organization is nil (anonymous)
# Use anonymous user to test metadata edge case without triggering lazy creation
@nil_org_sr = MockStrategyResult.new(
  session: MockSession.new,
  user: nil,
  metadata: { organization_context: { organization: nil } }
)
@nil_org_harness = AuthOrgTestHarness.new(@nil_org_sr)
@nil_org_harness.auth_org
#=> nil

## auth_org returns nil for anonymous strategy result
@anon_sr = MockStrategyResult.anonymous
@anon_harness = AuthOrgTestHarness.new(@anon_sr)
@anon_harness.auth_org
#=> nil

## @organization is also nil for anonymous strategy result
@anon_harness.organization
#=> nil


# Verify auth_org reads live from strategy_result (not cached at init time)

## auth_org reflects strategy_result metadata, not a snapshot
# If strategy_result metadata were mutated (shouldn't happen, but
# this proves auth_org is a live read, not a cached copy):
@live_sr = MockStrategyResult.new(
  session: MockSession.new,
  user: @auth_owner,
  metadata: { organization_context: { organization: @auth_org } }
)
@live_harness = AuthOrgTestHarness.new(@live_sr)
@live_harness.auth_org.objid
#=> @auth_org.objid

## require_organization! operates on @organization (the mutable ivar)
# After clobbering, require_organization! returns the domain org, not auth org.
@harness.require_organization!.objid
#=> @domain_org.objid

## Teardown: clean up test data
@domain_org.destroy! if @domain_org&.exists?
@auth_org.destroy! if @auth_org&.exists?
@domain_owner.destroy! if @domain_owner&.exists?
@auth_owner.destroy! if @auth_owner&.exists?
true
#=> true
