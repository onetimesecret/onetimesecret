# try/features/homepage/put_homepage_config_cidrs_try.rb
#
# frozen_string_literal: true

# Tests for PutHomepageConfig / GetHomepageConfig: the homepage network
# rules (allowed_cidrs / denied_cidrs).
#
# Merge semantics: an omitted/null list leaves the stored one unchanged,
# [] clears it, anything else replaces it with the normalized entries.
# Refusals are field-tagged 422s with locale keys, raised in raise_concerns
# before any write. Responses echo the NORMALIZED lists — what the gate
# evaluates — not the entries as typed.

require_relative '../../support/test_helpers'
require_relative '../../../apps/web/billing/lib/test_support/billing_helpers'

OT.boot! :test, false

require 'api/domains/logic/base'
require 'api/domains/logic/homepage_config/base'
require 'api/domains/logic/homepage_config/get_homepage_config'
require 'api/domains/logic/homepage_config/put_homepage_config'

HomepageConfig    = Onetime::CustomDomain::HomepageConfig
PutHomepageConfig = DomainsAPI::Logic::HomepageConfig::PutHomepageConfig
GetHomepageConfig = DomainsAPI::Logic::HomepageConfig::GetHomepageConfig

@ts      = Familia.now.to_i
@entropy = SecureRandom.hex(4)

@test_cust   = Onetime::Customer.create!(email: "put_hpcidr_#{@ts}_#{@entropy}@test.com")
@test_org    = Onetime::Organization.create!("Put HpCidr Test #{@ts}", @test_cust, "org_hpcidr_#{@ts}_#{@entropy}@test.com")
@test_domain = Onetime::CustomDomain.create!("put-hpcidr-#{@ts}-#{@entropy}.example.com", @test_org.objid)

def create_strategy_with_domain(customer, domain_fqdn, domain_strategy: :custom)
  session = MockSession.new
  org = customer.organization_instances.to_a.first
  org_context = {
    organization: org,
    organization_id: org.objid,
    expires_at: Familia.now.to_i + 300,
  }
  MockStrategyResult.new(
    session: session,
    user: customer,
    auth_method: 'session',
    metadata: {
      organization_context: org_context,
      domain_strategy: domain_strategy,
      display_domain: domain_fqdn,
    }
  )
end

def run_put(customer, domain, params)
  strategy = create_strategy_with_domain(customer, domain.display_domain)
  logic = PutHomepageConfig.new(strategy, params.merge('extid' => domain.extid))
  logic.process_params
  logic.raise_concerns
  logic.process
end

def run_get(customer, domain)
  strategy = create_strategy_with_domain(customer, domain.display_domain)
  logic = GetHomepageConfig.new(strategy, { 'extid' => domain.extid })
  logic.process_params
  logic.raise_concerns
  logic.process
end

# --- PREREQUISITES ---

## Fixture: test domain exists with the bootstrap HomepageConfig and no rules
cfg = HomepageConfig.find_by_domain_id(@test_domain.identifier)
[@test_domain.exists?, cfg.allowed_cidrs, cfg.denied_cidrs]
#=> [true, [], []]

## GET echoes empty lists for an unrestricted homepage
record = run_get(@test_cust, @test_domain)[:record]
[record[:allowed_cidrs], record[:denied_cidrs]]
#=> [[], []]

# --- PUT: set and normalize ---

## PUT stores allowed ranges and echoes them normalized and de-duplicated
record = run_put(@test_cust, @test_domain, {
  'enabled' => true,
  'allowed_cidrs' => ['10.1.2.3/8', ' 10.0.0.0/8', '2001:DB8::/32', '203.0.113.7'],
})[:record]
record[:allowed_cidrs]
#=> ['10.0.0.0/8', '2001:db8::/32', '203.0.113.7/32']

## PUT with the lists omitted leaves them unchanged (merge semantics)
record = run_put(@test_cust, @test_domain, { 'enabled' => true, 'secrets_mode' => 'create' })[:record]
[record[:allowed_cidrs], record[:denied_cidrs]]
#=> [['10.0.0.0/8', '2001:db8::/32', '203.0.113.7/32'], []]

## PUT with null leaves a list unchanged too
record = run_put(@test_cust, @test_domain, { 'enabled' => true, 'allowed_cidrs' => nil, 'denied_cidrs' => ['192.168.0.0/16'] })[:record]
[record[:allowed_cidrs].length, record[:denied_cidrs]]
#=> [3, ['192.168.0.0/16']]

## PUT with [] clears a list
record = run_put(@test_cust, @test_domain, { 'enabled' => true, 'allowed_cidrs' => [] })[:record]
[record[:allowed_cidrs], record[:denied_cidrs]]
#=> [[], ['192.168.0.0/16']]

## GET reflects the stored lists
record = run_get(@test_cust, @test_domain)[:record]
[record[:allowed_cidrs], record[:denied_cidrs]]
#=> [[], ['192.168.0.0/16']]

# --- PUT: refusals (field-tagged, before any write) ---

## An unparseable entry is a 422 tagged with the field and the locale key, naming the entry
begin
  run_put(@test_cust, @test_domain, { 'enabled' => false, 'allowed_cidrs' => ['10.0.0.0/8', 'office.example.com'] })
  :no_raise
rescue Onetime::FormError => ex
  [ex.field.to_s, ex.error_key, ex.args, ex.message]
end
#=> ['allowed_cidrs', 'api.domains.errors.homepage_cidr_invalid', { cidr: 'office.example.com' }, 'Invalid CIDR: office.example.com']

## The refused request wrote nothing: enabled is still true and the lists are intact
cfg = HomepageConfig.find_by_domain_id(@test_domain.identifier)
[cfg.enabled?, cfg.allowed_cidrs, cfg.denied_cidrs]
#=> [true, [], ['192.168.0.0/16']]

## A non-array value is a 422 tagged with the field
begin
  run_put(@test_cust, @test_domain, { 'enabled' => true, 'denied_cidrs' => '192.168.0.0/16' })
  :no_raise
rescue Onetime::FormError => ex
  [ex.field.to_s, ex.message]
end
#=> ['denied_cidrs', 'denied_cidrs must be an array of strings']

## An array holding a non-string is a 422 tagged with the field
begin
  run_put(@test_cust, @test_domain, { 'enabled' => true, 'denied_cidrs' => ['192.168.0.0/16', 42] })
  :no_raise
rescue Onetime::FormError => ex
  ex.field.to_s
end
#=> 'denied_cidrs'

## More than MAX_CIDRS distinct ranges is a 422 with the max in args
too_many = (0..HomepageConfig::MAX_CIDRS).map { |i| "10.#{i / 256}.#{i % 256}.0/24" }
begin
  run_put(@test_cust, @test_domain, { 'enabled' => true, 'allowed_cidrs' => too_many })
  :no_raise
rescue Onetime::FormError => ex
  [ex.field.to_s, ex.error_key, ex.args]
end
#=> ['allowed_cidrs', 'api.domains.errors.homepage_cidrs_max_exceeded', { max: HomepageConfig::MAX_CIDRS }]

## Exactly MAX_CIDRS distinct ranges is accepted
exactly = (0...HomepageConfig::MAX_CIDRS).map { |i| "10.#{i / 256}.#{i % 256}.0/24" }
run_put(@test_cust, @test_domain, { 'enabled' => true, 'allowed_cidrs' => exactly })[:record][:allowed_cidrs].length
#=> HomepageConfig::MAX_CIDRS

# --- PUT: plan gating (homepage_network_rules) ---
#
# Billing is disabled in tests, where STANDALONE_ENTITLEMENTS grants every
# entitlement. To reach the refusal, enable billing with a plan shaped like
# the free tier (homepage_secrets and manage_org, no homepage_network_rules)
# and re-materialize the owner's entitlements from it. Same setup as
# try/integration/api/domains/signin_config_authorization_try.rb.

## Fixture: a free-shaped plan has homepage_secrets but not homepage_network_rules
@gating = BillingTestHelpers.with_billing_enabled(plans: [
  {
    plan_id: 'hpcidr_free_test_month',
    name: 'Free-shaped Test',
    tier: 'free',
    interval: 'month',
    region: 'default',
    entitlements: %w[create_secrets view_receipt api_access custom_domains homepage_secrets manage_org],
    limits: { 'secrets_per_day' => '100' },
  },
]) do
  @test_org.planid = 'hpcidr_free_test_month'
  @test_org.save
  @test_org.materialized_entitlements.clear
  @test_org.materialized_entitlements_at = ''
  @test_org.commit_fields

  membership = Onetime::OrganizationMembership.find_by_org_customer(@test_org.objid, @test_cust.objid)
  if membership
    membership.materialized_entitlements.clear
    membership.materialized_entitlements_at = ''
    membership.commit_fields
    membership.apply_entitlements
  end
  org = Onetime::Organization.load(@test_org.objid)

  refused = begin
    run_put(@test_cust, @test_domain, { 'enabled' => true, 'denied_cidrs' => [] })
    :no_raise
  rescue Onetime::FormError => ex
    [ex.field.to_s, ex.error_key, ex.error_type]
  end
  selector = run_put(@test_cust, @test_domain, { 'enabled' => true, 'secrets_mode' => 'create' })[:record]

  {
    preconditions: [org.can?('homepage_secrets'), org.can?('homepage_network_rules')],
    refused: refused,
    selector_lists: [selector[:allowed_cidrs].length, selector[:denied_cidrs]],
  }
end
@gating[:preconditions]
#=> [true, false]

## Sending a list without the entitlement is a forbidden error on that field, clearing included
@gating[:refused]
#=> ['denied_cidrs', 'api.entitlements.errors.homepage_network_rules_required', :forbidden]

## The experience selector's write still works, and the stored rules stay in force (frozen, not dropped)
@gating[:selector_lists]
#=> [HomepageConfig::MAX_CIDRS, ['192.168.0.0/16']]

# --- teardown ---
HomepageConfig.delete_for_domain!(@test_domain.identifier)
@test_domain.destroy!
@test_org.destroy!
@test_cust.destroy!
