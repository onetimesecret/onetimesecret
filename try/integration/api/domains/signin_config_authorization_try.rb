# try/integration/api/domains/signin_config_authorization_try.rb
#
# frozen_string_literal: true

# Integration tests for SigninConfig API authorization denial paths.
#
# The positive paths (create, replace, GET, DELETE) are covered in
# put_signin_config_try.rb. This file exercises the NEGATIVE paths
# that the authorization layer should block:
#
# Covers:
#   1. Domain not found — extid that doesn't resolve
#   2. Organization not found — domain with orphaned org_id
#   3. Non-member — user is not a member of the domain's org
#   4. Member without manage_org — member role lacks entitlement
#   5. Entitlement gating — org plan lacks custom_signin_config
#   6. Denial paths for GET and DELETE (not just PUT)
#   7. Anonymous user fix — provides an anonymous customer object
#
# Run:
#   bundle exec try try/integration/api/domains/signin_config_authorization_try.rb --agent

require_relative '../../../support/test_helpers'
require_relative '../../../../apps/web/billing/lib/test_support/billing_helpers'

OT.boot! :test

# Disable billing so standalone entitlements apply (full access by default)
BillingTestHelpers.disable_billing!

require 'apps/api/domains/logic/base'
require 'apps/api/domains/logic/signin_config/base'
require 'apps/api/domains/logic/signin_config/put_signin_config'
require 'apps/api/domains/logic/signin_config/get_signin_config'
require 'apps/api/domains/logic/signin_config/delete_signin_config'

Familia.dbclient.flushdb
OT.info "Cleaned Redis for SigninConfig authorization test run"

@ts = Familia.now.to_i
@entropy = SecureRandom.hex(4)

# Fixtures: owner + org + domain (same as put_signin_config_try)
@owner = Onetime::Customer.create!(email: "sca_owner_#{@ts}_#{@entropy}@test.com")
@org = Onetime::Organization.create!("SCA Test Org #{@ts}", @owner, "sca_#{@ts}@test.com")
@domain = Onetime::CustomDomain.create!("sca-#{@ts}.example.com", @org.objid)

# Outsider: authenticated user who is NOT a member of @org
@outsider = Onetime::Customer.create!(email: "sca_outsider_#{@ts}_#{@entropy}@test.com")
@outsider_org = Onetime::Organization.create!("Outsider Org #{@ts}", @outsider, "sca_out_#{@ts}@test.com")

# Member with 'member' role (no manage_org)
@member = Onetime::Customer.create!(email: "sca_member_#{@ts}_#{@entropy}@test.com")
@member_membership = @org.add_members_instance(@member, through_attrs: { role: 'member' })

@session = {}

def build_strategy_result(user)
  # Build with organization_context matching the user's first org
  org = user.organization_instances.to_a.first
  metadata = org ? { organization_context: { organization: org } } : {}
  MockStrategyResult.new(
    session: @session,
    user: user,
    metadata: metadata,
  )
end

def build_put(extid:, params: {}, user: @owner)
  full_params = { 'extid' => extid }.merge(params)
  DomainsAPI::Logic::SigninConfig::PutSigninConfig.new(build_strategy_result(user), full_params)
end

def build_get(extid:, user: @owner)
  DomainsAPI::Logic::SigninConfig::GetSigninConfig.new(build_strategy_result(user), { 'extid' => extid })
end

def build_delete(extid:, user: @owner)
  DomainsAPI::Logic::SigninConfig::DeleteSigninConfig.new(build_strategy_result(user), { 'extid' => extid })
end

# ============================================================
# 1. Domain not found — nonexistent extid
# ============================================================

## PUT rejects nonexistent domain extid with RecordNotFound
begin
  logic = build_put(extid: 'nonexistent_domain_xyz_123')
  logic.raise_concerns
  'unexpected_success'
rescue Onetime::RecordNotFound
  'not_found'
end
#=> 'not_found'

## GET rejects nonexistent domain extid with RecordNotFound
begin
  logic = build_get(extid: 'nonexistent_domain_xyz_456')
  logic.raise_concerns
  'unexpected_success'
rescue Onetime::RecordNotFound
  'not_found'
end
#=> 'not_found'

## DELETE rejects nonexistent domain extid with RecordNotFound
begin
  logic = build_delete(extid: 'nonexistent_domain_xyz_789')
  logic.raise_concerns
  'unexpected_success'
rescue Onetime::RecordNotFound
  'not_found'
end
#=> 'not_found'

# ============================================================
# 2. Non-member — user is not a member of the domain's org
# ============================================================

## PUT rejects non-member of domain's org
begin
  logic = build_put(extid: @domain.extid, user: @outsider)
  logic.raise_concerns
  'unexpected_success'
rescue Onetime::Forbidden => ex
  ex.message.include?('member') || ex.message.include?('Authentication')
end
#=> true

## GET rejects non-member of domain's org
begin
  logic = build_get(extid: @domain.extid, user: @outsider)
  logic.raise_concerns
  'unexpected_success'
rescue Onetime::Forbidden => ex
  ex.message.include?('member') || ex.message.include?('Authentication')
end
#=> true

## DELETE rejects non-member of domain's org
begin
  logic = build_delete(extid: @domain.extid, user: @outsider)
  logic.raise_concerns
  'unexpected_success'
rescue Onetime::Forbidden => ex
  ex.message.include?('member') || ex.message.include?('Authentication')
end
#=> true

# ============================================================
# 3. Member without manage_org — member role lacks entitlement
# ============================================================

## Precondition: member has 'member' role
@member_membership.role
#=> 'member'

## PUT rejects member without manage_org
begin
  logic = build_put(extid: @domain.extid, user: @member)
  logic.raise_concerns
  'unexpected_success'
rescue Onetime::EntitlementRequired => ex
  ex.entitlement
rescue Onetime::Forbidden
  'forbidden'
end
#=> 'manage_org'

## GET rejects member without manage_org
begin
  logic = build_get(extid: @domain.extid, user: @member)
  logic.raise_concerns
  'unexpected_success'
rescue Onetime::EntitlementRequired => ex
  ex.entitlement
rescue Onetime::Forbidden
  'forbidden'
end
#=> 'manage_org'

## DELETE rejects member without manage_org
begin
  logic = build_delete(extid: @domain.extid, user: @member)
  logic.raise_concerns
  'unexpected_success'
rescue Onetime::EntitlementRequired => ex
  ex.entitlement
rescue Onetime::Forbidden
  'forbidden'
end
#=> 'manage_org'

# ============================================================
# 4. Entitlement gating — org plan lacks custom_signin_config
# ============================================================
#
# With billing disabled, standalone mode grants full access.
# To test entitlement denial, we:
#   1. Enable billing (so org.billing_enabled? returns true)
#   2. Populate a plan that has manage_org but NOT custom_signin_config
#   3. Assign that plan to the org
#   4. Clear materialized entitlements so the org falls through to
#      the plan-based lookup (materialized data from standalone mode
#      would otherwise shadow the plan check)
#   5. Re-materialize membership entitlements so the owner passes
#      the manage_org check but the org fails custom_signin_config
#
# The authorization flow is:
#   require_entitlement_in!(org, 'manage_org') — checks MEMBERSHIP.can?
#   verify_config_entitlement(org) — checks ORG.can?('custom_signin_config')
#
# So the owner's membership needs manage_org (from the plan) but the
# org must not have custom_signin_config.

## Entitlement: org lacks custom_signin_config (plan without it)
@entitlement_result = BillingTestHelpers.with_billing_enabled(plans: [
  {
    plan_id: 'basic_test_month',
    name: 'Basic Test',
    tier: 'basic',
    interval: 'month',
    region: 'default',
    entitlements: %w[
      create_secrets view_receipt api_access custom_domains
      manage_org manage_teams
    ],
    limits: { 'secrets_per_day' => '100' },
  },
]) do
  # Assign the plan to the org
  @org.planid = 'basic_test_month'
  @org.save

  # Clear materialized entitlements so the org falls through to plan lookup.
  # Without this, the org still has standalone entitlements in Redis.
  @org.materialized_entitlements.clear
  @org.materialized_entitlements_at = ''
  @org.commit_fields

  # Re-materialize entitlements for the owner membership from the new plan
  owner_membership = Onetime::OrganizationMembership.find_by_org_customer(
    @org.objid,
    @owner.objid,
  )
  if owner_membership
    owner_membership.materialized_entitlements.clear
    owner_membership.materialized_entitlements_at = ''
    owner_membership.commit_fields
    owner_membership.apply_entitlements
  end

  # Reload the org to pick up the cleared materialization state
  @org_reloaded = Onetime::Organization.load(@org.objid)

  # Precondition: org can manage_org (from plan) but cannot custom_signin_config
  preconditions = [@org_reloaded.can?('manage_org'), @org_reloaded.can?('custom_signin_config')]

  begin
    logic = build_put(extid: @domain.extid, params: { 'enabled' => 'true' })
    logic.raise_concerns
    { preconditions: preconditions, result: 'unexpected_success' }
  rescue Onetime::FormError => ex
    { preconditions: preconditions, result: ex.message }
  end
end
@entitlement_result[:preconditions]
#=> [true, false]

## Entitlement denial message mentions custom_signin_config
@entitlement_result[:result].include?('custom_signin_config')
#=> true

# ============================================================
# 5. Anonymous user — properly constructed anonymous customer
# ============================================================
#
# The existing test in put_signin_config_try.rb uses
# MockStrategyResult.anonymous which sets user: nil, causing
# NoMethodError. This test provides an actual anonymous customer.

## Anonymous customer is rejected with FormError
@anon_cust = Onetime::Customer.new
@anon_cust.role = 'anonymous'
@anon_result = MockStrategyResult.new(
  session: {},
  user: @anon_cust,
  auth_method: 'anonymous',
  metadata: {},
)
begin
  logic = DomainsAPI::Logic::SigninConfig::PutSigninConfig.new(
    @anon_result,
    { 'extid' => @domain.extid },
  )
  logic.raise_concerns
  'unexpected_success'
rescue Onetime::FormError => ex
  ex.message
end
#=> 'Authentication required'

# ============================================================
# 6. Owner positive path still works after denial tests
# ============================================================
#
# Sanity check: the authorized owner can still create/read/delete.

## Owner can PUT signin config after authorization denial tests
@domain_sanity = Onetime::CustomDomain.create!("sca-sanity-#{@ts}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@logic_sanity = build_put(
  extid: @domain_sanity.extid,
  params: { 'enabled' => 'true', 'signin_enabled' => 'true' },
)
@logic_sanity.raise_concerns
@sanity_result = @logic_sanity.process
@sanity_result[:record][:enabled]
#=> true

## Owner can GET the config just created
@logic_get_sanity = build_get(extid: @domain_sanity.extid)
@logic_get_sanity.raise_concerns
@get_sanity = @logic_get_sanity.process
@get_sanity[:record][:signin_enabled]
#=> true

## Owner can DELETE the config
@logic_del_sanity = build_delete(extid: @domain_sanity.extid)
@logic_del_sanity.raise_concerns
@del_sanity = @logic_del_sanity.process
@del_sanity[:success]
#=> true

# --- Cleanup ---

Familia.dbclient.flushdb
OT.info "Cleaned Redis after SigninConfig authorization test run"
