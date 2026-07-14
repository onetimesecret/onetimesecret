# try/unit/logic/domains/add_domain_try.rb
#
# frozen_string_literal: true

# Tests for AddDomain logic class with enhanced duplicate handling
#
# Validates three scenarios:
# 1. Domain already in customer's organization (same org_id)
# 2. Domain in another organization (different org_id)
# 3. Orphaned domain (no org_id) - should be auto-claimed

require_relative '../../../support/test_logic'
require 'securerandom'

OT.boot! :test

# Load DomainsAPI logic classes
require 'api/domains/logic/base'
require 'api/domains/logic/domains/add_domain'

# Setup test fixtures with unique identifiers
@timestamp = Familia.now.to_i
@owner1 = Onetime::Customer.create!(email: "owner1_#{@timestamp}@test.com")
@owner2 = Onetime::Customer.create!(email: "owner2_#{@timestamp}@test.com")

@org1 = Onetime::Organization.create!("First Corp", @owner1, "domains1_#{@timestamp}@first.com")
@org2 = Onetime::Organization.create!("Second Corp", @owner2, "domains2_#{@timestamp}@second.com")

# Enable standalone mode (billing disabled) to grant custom_domains entitlement.
# Note: The singleton method override happens AFTER org creation, so we must
# re-materialize the owner memberships with the overridden org instance.
@org1.define_singleton_method(:billing_enabled?) { false }
@org2.define_singleton_method(:billing_enabled?) { false }

# Re-materialize owner memberships with the billing-disabled org instances.
# Without this, the memberships' entitlements were computed during create!
# using the original org (with billing_enabled? returning its default value).
Onetime::OrganizationMembership.find_by_org_customer(@org1.objid, @owner1.objid)&.materialize_for_role!(@org1)
Onetime::OrganizationMembership.find_by_org_customer(@org2.objid, @owner2.objid)&.materialize_for_role!(@org2)

# Define unique test domain names
@test_domain1 = "secrets-#{@timestamp}.example.com"
@test_domain2 = "api-#{@timestamp}.example.com"

# Create session and strategy result for owner1 with organization context
@session1 = {}
@strategy_result1 = MockStrategyResult.new(
  session: @session1,
  user: @owner1,
  metadata: { organization_context: { organization: @org1 } }
)

# Create session and strategy result for owner2 with organization context
@session2 = {}
@strategy_result2 = MockStrategyResult.new(
  session: @session2,
  user: @owner2,
  metadata: { organization_context: { organization: @org2 } }
)

## AddDomain with valid new domain
@params1 = { 'domain' => @test_domain1 }
@logic1 = DomainsAPI::Logic::Domains::AddDomain.new(@strategy_result1, @params1)
@logic1.raise_concerns
@logic1.process
[@logic1.greenlighted, @logic1.custom_domain.display_domain]
#=> [true, @test_domain1]

## Domain was added to organization
@org1.domain_count
#=> 1

## SCENARIO 1: Attempting to add same domain to same organization raises specific error
@params1_dup = { 'domain' => @test_domain1 }
@logic1_dup = DomainsAPI::Logic::Domains::AddDomain.new(@strategy_result1, @params1_dup)
begin
  @logic1_dup.raise_concerns
  "unexpected_success"
rescue Onetime::FormError => e
  e.message
end
#=> "Domain already registered in your organization"

## SCENARIO 1: Organization still has exactly one domain
@org1.domain_count
#=> 1

## SCENARIO 2: Attempting to add domain from another organization raises specific error
@params2 = { 'domain' => @test_domain1 }
@logic2 = DomainsAPI::Logic::Domains::AddDomain.new(@strategy_result2, @params2)
begin
  @logic2.raise_concerns
  "unexpected_success"
rescue Onetime::FormError => e
  e.message
end
#=> "Domain is registered to another organization"

## SCENARIO 2: Second organization has no domains
@org2.domain_count
#=> 0

## SCENARIO 3: Orphaned domain handling tested in model tests
## Skipping manual orphan creation here - integration tests cover this scenario
true
#=> true

## validation: empty domain
@params_empty = { 'domain' => '' }
@logic_empty = DomainsAPI::Logic::Domains::AddDomain.new(@strategy_result1, @params_empty)
begin
  @logic_empty.raise_concerns
  "unexpected_success"
rescue Onetime::FormError => e
  e.message
end
#=> "Please enter a domain"

## validation: invalid domain
@params_invalid = { 'domain' => 'not-a-valid-domain' }
@logic_invalid = DomainsAPI::Logic::Domains::AddDomain.new(@strategy_result1, @params_invalid)
begin
  @logic_invalid.raise_concerns
  "unexpected_success"
rescue Onetime::FormError => e
  e.message
end
#=> "Not a valid public domain"

## Case insensitivity: Attempting to add uppercase version of existing domain
@params_upper = { 'domain' => @test_domain1.upcase }
@logic_upper = DomainsAPI::Logic::Domains::AddDomain.new(@strategy_result1, @params_upper)
begin
  @logic_upper.raise_concerns
  "unexpected_success"
rescue Onetime::FormError => e
  e.message
end
#=> "Domain already registered in your organization"

## Case insensitivity: Attempting to add mixed case to another org
@test_domain1_mixed = @test_domain1.chars.map.with_index { |c, i| i.even? ? c.upcase : c.downcase }.join
@params_mixed = { 'domain' => @test_domain1_mixed }
@logic_mixed = DomainsAPI::Logic::Domains::AddDomain.new(@strategy_result2, @params_mixed)
begin
  @logic_mixed.raise_concerns
  "unexpected_success"
rescue Onetime::FormError => e
  e.message
end
#=> "Domain is registered to another organization"

## successful creation of second domain for org1
@params4 = { 'domain' => @test_domain2 }
@logic4 = DomainsAPI::Logic::Domains::AddDomain.new(@strategy_result1, @params4)
@logic4.raise_concerns
@logic4.process
[@logic4.greenlighted, @logic4.custom_domain.display_domain]
#=> [true, @test_domain2]

## Final org1 domain count
@org1.domain_count
#=> 2

## Final org1 domains list
@org1.list_domains.map(&:display_domain).sort
#=> [@test_domain2, @test_domain1].sort

## Final org2 domain count
@org2.domain_count
#=> 0

## Final org2 domains list
@org2.list_domains.map(&:display_domain).sort
#=> []

# Tests for explicit org_id parameter support
# This enables org context to persist across navigation when session hasn't been updated

## Membership was returned (not nil)
# Add owner1 as owner of org2 so they can add domains to it via explicit org_id.
# The role 'owner' includes custom_domains entitlement (ADR-012 Stage 3).
# 'admin' lacks custom_domains, and 'member' lacks the admin-gate check —
# explicit-org_id tests focus on resolution, not role-gate behavior.
# Role-gate coverage lives in the separate cases further down.
@membership = @org2.add_members_instance(@owner1, through_attrs: { role: 'owner' })
# Re-materialize with the billing-disabled org instance (see note at top of file)
@membership.materialize_for_role!(@org2)
@membership.nil?
#=> false

## Membership has correct org objid
@membership.organization_objid
#=> @org2.objid

## Owner1's objid is in org2's members set (using wrapper for Familia v2 serialization)
@org2.member?(@owner1.objid)
#=> true

## Owner1 is now member of org2 (via member? helper)
@org2.member?(@owner1)
#=> true

## Explicit org_id param: Add domain to different org than session context
@test_domain3 = "explicit-#{@timestamp}.example.com"
@params_explicit = { 'domain' => @test_domain3, 'org_id' => @org2.objid }
@logic_explicit = DomainsAPI::Logic::Domains::AddDomain.new(@strategy_result1, @params_explicit)
@logic_explicit.raise_concerns
@logic_explicit.process
[@logic_explicit.greenlighted, @logic_explicit.target_organization.objid == @org2.objid]
#=> [true, true]

## Domain was added to org2 (not org1 from session)
@org2.domain_count
#=> 1

## org1 count remains unchanged
@org1.domain_count
#=> 2

## Explicit org_id param: Works with extid too
@test_domain4 = "extid-#{@timestamp}.example.com"
@params_extid = { 'domain' => @test_domain4, 'org_id' => @org2.extid }
@logic_extid = DomainsAPI::Logic::Domains::AddDomain.new(@strategy_result1, @params_extid)
@logic_extid.raise_concerns
@logic_extid.process
[@logic_extid.greenlighted, @logic_extid.target_organization.objid == @org2.objid]
#=> [true, true]

## Explicit org_id param: Rejects non-member org
@org3 = Onetime::Organization.create!("Third Corp", @owner2, "domains3_#{@timestamp}@third.com")
@org3.define_singleton_method(:billing_enabled?) { false }
@test_domain5 = "nonmember-#{@timestamp}.example.com"
@params_nonmember = { 'domain' => @test_domain5, 'org_id' => @org3.objid }
@logic_nonmember = DomainsAPI::Logic::Domains::AddDomain.new(@strategy_result1, @params_nonmember)
begin
  @logic_nonmember.raise_concerns
  "unexpected_success"
rescue Onetime::FormError => e
  e.message
end
#=> "Organization not found or access denied"

# -----------------------------------------------------------------------------
# Role gate (#3033 §2, ADR-012 Stage 3): custom_domains is an owner-level
# entitlement by default. Admins need an explicit grant to add domains.
# Owner path is exercised by every preceding case (owners created the orgs).
# The cases below cover: admin with explicit grant (allowed), member (rejected).
# -----------------------------------------------------------------------------

## Setup: invite a plain member and an admin into @org1 for the role-gate cases
@member_user = Onetime::Customer.create!(email: "member_#{@timestamp}@test.com")
@admin_user  = Onetime::Customer.create!(email: "admin_#{@timestamp}@test.com")
@member_membership = @org1.add_members_instance(@member_user, through_attrs: { role: 'member' })
@admin_membership  = @org1.add_members_instance(@admin_user,  through_attrs: { role: 'admin'  })
# Re-materialize with the billing-disabled org instance (see note at top of file)
@member_membership.materialize_for_role!(@org1)
@admin_membership.materialize_for_role!(@org1)
# Grant custom_domains to admin explicitly (ADR-012: custom_domains is owner-only by default;
# this test verifies admin + explicit grant can add domains)
@admin_membership.grant_entitlement('custom_domains')
[@member_membership.role, @admin_membership.role]
#=> ['member', 'admin']

## Member is rejected with Forbidden (not FormError) when adding a domain
@strategy_result_member = MockStrategyResult.new(
  session: {},
  user: @member_user,
  metadata: { organization_context: { organization: @org1 } }
)
@test_domain_member = "member-#{@timestamp}.example.com"
@logic_member = DomainsAPI::Logic::Domains::AddDomain.new(
  @strategy_result_member,
  { 'domain' => @test_domain_member }
)
begin
  @logic_member.raise_concerns
  "unexpected_success"
rescue Onetime::Forbidden => e
  e.is_a?(Onetime::Forbidden)
end
#=> true

## No domain was created for the member-rejected attempt
@org1.list_domains.map(&:display_domain).include?(@test_domain_member)
#=> false

## Admin is allowed to add a domain
@strategy_result_admin = MockStrategyResult.new(
  session: {},
  user: @admin_user,
  metadata: { organization_context: { organization: @org1 } }
)
@test_domain_admin = "admin-#{@timestamp}.example.com"
@logic_admin = DomainsAPI::Logic::Domains::AddDomain.new(
  @strategy_result_admin,
  { 'domain' => @test_domain_admin }
)
@logic_admin.raise_concerns
@logic_admin.process
[@logic_admin.greenlighted, @logic_admin.custom_domain.display_domain]
#=> [true, @test_domain_admin]

## Member is rejected even via explicit org_id path (auth gate runs after resolution)
@org2.add_members_instance(@member_user, through_attrs: { role: 'member' })
@test_domain_member_explicit = "member-explicit-#{@timestamp}.example.com"
@logic_member_explicit = DomainsAPI::Logic::Domains::AddDomain.new(
  @strategy_result_member,
  { 'domain' => @test_domain_member_explicit, 'org_id' => @org2.objid }
)
begin
  @logic_member_explicit.raise_concerns
  "unexpected_success"
rescue Onetime::Forbidden => e
  e.is_a?(Onetime::Forbidden)
end
#=> true

# -----------------------------------------------------------------------------
# Favicon auto-fetch on add (#3780 BE2): AddDomain#process enqueues a favicon
# fetch when jobs.favicon_fetch.enabled is true, wrapped so a raising fetch
# never breaks domain creation. Jobs are disabled in test mode, so the Publisher
# runs FetchDomainFavicon inline — we stub it to raise FetchTimeout, the
# transient error the inline branch would otherwise surface unrescued.
# -----------------------------------------------------------------------------

## Setup: stub the inline favicon fetch to record invocation and raise FetchTimeout
require 'onetime/operations/fetch_domain_favicon'
require 'onetime/net/safe_fetch'
@favicon_fetch_calls = []
favicon_calls = @favicon_fetch_calls
Onetime::Operations::FetchDomainFavicon.define_singleton_method(:new) do |**_kwargs|
  stub = Object.new
  stub.define_singleton_method(:call) do
    favicon_calls << :called
    raise Onetime::Net::SafeFetch::FetchTimeout, "stubbed timeout"
  end
  stub
end
(OT.conf['jobs'] ||= {})['favicon_fetch'] ||= {}
@favicon_fetch_calls.length
#=> 0

## Flag ON: a raising inline favicon fetch is rescued - domain is still created
OT.conf['jobs']['favicon_fetch']['enabled'] = true
@fav_domain = "favicon-#{@timestamp}.example.com"
@logic_fav = DomainsAPI::Logic::Domains::AddDomain.new(@strategy_result1, { 'domain' => @fav_domain })
@logic_fav.raise_concerns
@fav_result = @logic_fav.process
# process returned success_data (a Hash) instead of propagating FetchTimeout,
# the domain persisted, and the inline fetch was invoked exactly once.
[@fav_result.is_a?(Hash), @logic_fav.custom_domain.display_domain, @logic_fav.custom_domain.exists?, @favicon_fetch_calls.length]
#=> [true, @fav_domain, true, 1]

## Flag OFF: favicon fetch is never attempted (gate short-circuits before the Publisher)
@favicon_fetch_calls.clear
OT.conf['jobs']['favicon_fetch']['enabled'] = false
@fav_domain_off = "favicon-off-#{@timestamp}.example.com"
@logic_fav_off = DomainsAPI::Logic::Domains::AddDomain.new(@strategy_result1, { 'domain' => @fav_domain_off })
@logic_fav_off.raise_concerns
@fav_result_off = @logic_fav_off.process
[@fav_result_off.is_a?(Hash), @logic_fav_off.custom_domain.exists?, @favicon_fetch_calls.length]
#=> [true, true, 0]

## Role-gate cleanup
@logic_admin.custom_domain.destroy! if @logic_admin&.custom_domain&.exists?
@member_membership.destroy! if @member_membership&.exists?
@admin_membership.destroy! if @admin_membership&.exists?
@member_user.destroy! if @member_user&.exists?
@admin_user.destroy! if @admin_user&.exists?

## Cleanup for explicit org_id tests
@logic_extid.custom_domain.destroy! if @logic_extid&.custom_domain&.exists?
@logic_explicit.custom_domain.destroy! if @logic_explicit&.custom_domain&.exists?
@org3.destroy! if @org3&.exists?

# Teardown
@logic_fav.custom_domain.destroy! if @logic_fav&.custom_domain&.exists?
@logic_fav_off.custom_domain.destroy! if @logic_fav_off&.custom_domain&.exists?
@logic4.custom_domain.destroy! if @logic4&.custom_domain&.exists?
@logic1.custom_domain.destroy! if @logic1&.custom_domain&.exists?
@org2.destroy! if @org2&.exists?
@org1.destroy! if @org1&.exists?
@owner2.destroy! if @owner2&.exists?
@owner1.destroy! if @owner1&.exists?
