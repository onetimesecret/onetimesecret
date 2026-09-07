# try/unit/logic/secrets/base_secret_action_try.rb
#
# frozen_string_literal: true

# Tests for V1 BaseSecretAction#validate_domain_permissions.
# Validates that non-owners are rejected with FormError when attempting
# to create a secret on a domain they don't own (canonical domain path).
#
# Also covers two V2 BaseSecretAction fixes from the 2026-07-29 API audit:
# - item 2: anonymous recipient raises Onetime::Unauthorized (401), not
#   FormError (422)
# - item 4: anonymous_max_ttl caps anonymous TTLs at the free-tier limit
#   when billing is enabled (fail-open at config max when disabled)

require_relative '../../../support/test_helpers'

OT.boot! :test, false

require 'v1/logic'
require 'v2/logic'
require 'api/domains/logic/base'
require 'api/domains/logic/domains/add_domain'

@timestamp = Familia.now.to_i
@owner = Onetime::Customer.create!(email: "domain_owner_#{@timestamp}@test.com")
@non_owner = Onetime::Customer.create!(email: "non_owner_#{@timestamp}@test.com")
@owner_org = Onetime::Organization.create!("Owner Corp", @owner, "owner_#{@timestamp}@test.com")
@non_owner_org = Onetime::Organization.create!("Other Corp", @non_owner, "other_#{@timestamp}@test.com")
@owner_org.define_singleton_method(:billing_enabled?) { false }
@non_owner_org.define_singleton_method(:billing_enabled?) { false }
@test_domain = "perm-test-#{@timestamp}.example.com"
@owner_strategy = MockStrategyResult.new(session: {}, user: @owner, metadata: { organization_context: { organization: @owner_org } })
@add_logic = DomainsAPI::Logic::Domains::AddDomain.new(@owner_strategy, { 'domain' => @test_domain })
@add_logic.raise_concerns
@add_logic.process
@sess = MockSession.new

## Non-owner is rejected when sharing with a domain they don't own
params = { 'secret' => 'test secret', 'share_domain' => @test_domain }
logic = V1::Logic::Secrets::ConcealSecret.new(@sess, @non_owner, params, 'en')
begin; logic.raise_concerns; "unexpected_success"; rescue Onetime::FormError => e; e.message; end
#==> /You do not have permission to use domain/.match?(_)

## Owner can share with their own domain without error
params = { 'secret' => 'owner secret', 'share_domain' => @test_domain }
logic = V1::Logic::Secrets::ConcealSecret.new(@sess, @owner, params, 'en')
begin; logic.raise_concerns; "no_error"; rescue Onetime::FormError => e; "unexpected_error: #{e.message}"; end
#=> 'no_error'

## V2: anonymous caller naming a recipient raises Unauthorized (401), not FormError (422)
# Account-required is an authentication failure; otto_hooks maps
# Onetime::Unauthorized to 401 where FormError would produce a 422.
params = { 'secret' => { 'secret' => 'v2 recipient test', 'recipient' => 'friend@example.com' } }
logic  = V2::Logic::Secrets::ConcealSecret.new(MockStrategyResult.anonymous, params, 'en')
begin
  logic.send(:validate_recipient)
  'unexpected_success'
rescue StandardError => ex
  ex.class.name
end
#=> 'Onetime::Unauthorized'

## V2: canonical guest policy applies the configured ceiling when billing is disabled
# Stock config leaves ttl_max_anonymous unset -> 7-day canonical-host default.
# Custom-domain guests resolve through the domain owner organization instead.
billing = Onetime::BillingConfig.instance
class << billing
  def enabled?
    false
  end
end
begin
  logic = V2::Logic::Secrets::ConcealSecret.new(MockStrategyResult.anonymous, { 'secret' => { 'secret' => 's' } }, 'en')
  logic.send(:anonymous_max_ttl, 2_592_000)
ensure
  class << billing
    remove_method :enabled?
  end
end
#=> 604_800

## V2: a config ttl_options max below the ceiling still wins (billing disabled)
billing = Onetime::BillingConfig.instance
class << billing
  def enabled?
    false
  end
end
begin
  logic = V2::Logic::Secrets::ConcealSecret.new(MockStrategyResult.anonymous, { 'secret' => { 'secret' => 's' } }, 'en')
  logic.send(:anonymous_max_ttl, 172_800)
ensure
  class << billing
    remove_method :enabled?
  end
end
#=> 172_800

## V2: a self-hosted operator can RAISE the canonical guest ceiling above 7 days
# With billing disabled there is no free tier to invert against, so the
# operator's canonical-host value stands.
billing = Onetime::BillingConfig.instance
class << billing
  def enabled?
    false
  end
end
prev = OT.conf['site']['secret_options']['ttl_max_anonymous']
OT.conf['site']['secret_options']['ttl_max_anonymous'] = 30 * 86_400
begin
  logic = V2::Logic::Secrets::ConcealSecret.new(MockStrategyResult.anonymous, { 'secret' => { 'secret' => 's' } }, 'en')
  logic.send(:anonymous_max_ttl, 2_592_000)
ensure
  class << billing
    remove_method :enabled?
  end
  OT.conf['site']['secret_options']['ttl_max_anonymous'] = prev
end
#=> 2_592_000

## V2: a raised ceiling is still bounded by the config ttl_options max
billing = Onetime::BillingConfig.instance
class << billing
  def enabled?
    false
  end
end
prev = OT.conf['site']['secret_options']['ttl_max_anonymous']
OT.conf['site']['secret_options']['ttl_max_anonymous'] = 30 * 86_400
begin
  logic = V2::Logic::Secrets::ConcealSecret.new(MockStrategyResult.anonymous, { 'secret' => { 'secret' => 's' } }, 'en')
  logic.send(:anonymous_max_ttl, 172_800)
ensure
  class << billing
    remove_method :enabled?
  end
  OT.conf['site']['secret_options']['ttl_max_anonymous'] = prev
end
#=> 172_800

## V2: a non-positive ttl_max_anonymous falls back to the default, not to 0
# "0" reads as "unset me", not "anonymous secrets expire immediately".
prev = OT.conf['site']['secret_options']['ttl_max_anonymous']
OT.conf['site']['secret_options']['ttl_max_anonymous'] = 0
begin
  Onetime::Models::Features::WithEntitlements.configured_anonymous_max_ttl
ensure
  OT.conf['site']['secret_options']['ttl_max_anonymous'] = prev
end
#==> _ == Onetime::Models::Features::WithEntitlements::ANONYMOUS_MAX_TTL

## V2: a malformed ttl_max_anonymous falls back to the default
prev = OT.conf['site']['secret_options']['ttl_max_anonymous']
OT.conf['site']['secret_options']['ttl_max_anonymous'] = 'not-a-number'
begin
  Onetime::Models::Features::WithEntitlements.configured_anonymous_max_ttl
ensure
  OT.conf['site']['secret_options']['ttl_max_anonymous'] = prev
end
#==> _ == Onetime::Models::Features::WithEntitlements::ANONYMOUS_MAX_TTL

## V2: ttl_max_anonymous is bounded by MAX_TTL (365 days)
prev = OT.conf['site']['secret_options']['ttl_max_anonymous']
OT.conf['site']['secret_options']['ttl_max_anonymous'] = 999_999_999
begin
  Onetime::Models::Features::WithEntitlements.configured_anonymous_max_ttl
ensure
  OT.conf['site']['secret_options']['ttl_max_anonymous'] = prev
end
#==> _ == Onetime::Models::Features::WithEntitlements::MAX_TTL

## V2: canonical guest policy uses the configured ceiling when billing is enabled
# Stock: canonical ceiling 7d, free-tier limit 14d. The lower of the two wins.
billing = Onetime::BillingConfig.instance
class << billing
  def enabled?
    true
  end
end
Onetime::Organization.reset_free_tier_limits!
begin
  logic = V2::Logic::Secrets::ConcealSecret.new(MockStrategyResult.anonymous, { 'secret' => { 'secret' => 's' } }, 'en')
  logic.send(:anonymous_max_ttl, 2_592_000)
ensure
  class << billing
    remove_method :enabled?
  end
  Onetime::Organization.reset_free_tier_limits!
end
#==> _ == Onetime::Models::Features::WithEntitlements::ANONYMOUS_MAX_TTL

## V2: with billing enabled, the free-tier limit caps a raised ceiling
# This is the audit invariant (anonymous grant <= authenticated free-tier grant)
# holding where tiers actually exist: the operator raised the anonymous ceiling
# to 30 days, but the free-tier limit is 14 days, so 14 wins.
billing = Onetime::BillingConfig.instance
class << billing
  def enabled?
    true
  end
end
prev = OT.conf['site']['secret_options']['ttl_max_anonymous']
OT.conf['site']['secret_options']['ttl_max_anonymous'] = 30 * 86_400
Onetime::Organization.reset_free_tier_limits!
begin
  logic = V2::Logic::Secrets::ConcealSecret.new(MockStrategyResult.anonymous, { 'secret' => { 'secret' => 's' } }, 'en')
  logic.send(:anonymous_max_ttl, 2_592_000)
ensure
  class << billing
    remove_method :enabled?
  end
  OT.conf['site']['secret_options']['ttl_max_anonymous'] = prev
  Onetime::Organization.reset_free_tier_limits!
end
#==> _ == Onetime::Models::Features::WithEntitlements::DEFAULT_FREE_TTL

## V2: lowering the free-tier limit below the ceiling still applies
# TTL_MAX_ANONYMOUS also moves free_tier_limits on billing-enabled deployments.
billing = Onetime::BillingConfig.instance
class << billing
  def enabled?
    true
  end
end
ENV['TTL_MAX_ANONYMOUS'] = (3 * 86_400).to_s
Onetime::Organization.reset_free_tier_limits!
begin
  logic = V2::Logic::Secrets::ConcealSecret.new(MockStrategyResult.anonymous, { 'secret' => { 'secret' => 's' } }, 'en')
  logic.send(:anonymous_max_ttl, 2_592_000)
ensure
  class << billing
    remove_method :enabled?
  end
  ENV.delete('TTL_MAX_ANONYMOUS')
  Onetime::Organization.reset_free_tier_limits!
end
#=> 259_200
