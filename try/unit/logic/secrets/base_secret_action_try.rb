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

## V2: anonymous_max_ttl enforces the 7-day cap even when billing is disabled
# Diverges from V1's resolve_ttl_limit, which fails open to the config max:
# the cap is a product rule about anonymous callers, not about billing.
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

## V2: a config ttl_options max below the cap still wins (billing disabled)
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

## V2: anonymous_max_ttl caps at ANONYMOUS_MAX_TTL when billing is enabled
# Stock PLAN_TTL_ANONYMOUS (unset -> DEFAULT_FREE_TTL, 14d) is above the 7d cap.
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

## V2: raising PLAN_TTL_ANONYMOUS cannot lift the anonymous ceiling above 7 days
# The env var moves free_tier_limits (asserted in the pair below), but the
# anonymous clamp mins it against the ANONYMOUS_MAX_TTL product cap.
billing = Onetime::BillingConfig.instance
class << billing
  def enabled?
    true
  end
end
raised = 24 * 86_400
ENV['PLAN_TTL_ANONYMOUS'] = raised.to_s
Onetime::Organization.reset_free_tier_limits!
begin
  logic = V2::Logic::Secrets::ConcealSecret.new(MockStrategyResult.anonymous, { 'secret' => { 'secret' => 's' } }, 'en')
  [Onetime::Organization.free_tier_limits['secret_lifetime.max'], logic.send(:anonymous_max_ttl, raised)]
ensure
  class << billing
    remove_method :enabled?
  end
  ENV.delete('PLAN_TTL_ANONYMOUS')
  Onetime::Organization.reset_free_tier_limits!
end
#==> _ == [24 * 86_400, Onetime::Models::Features::WithEntitlements::ANONYMOUS_MAX_TTL]

## V2: lowering PLAN_TTL_ANONYMOUS below the cap still applies
billing = Onetime::BillingConfig.instance
class << billing
  def enabled?
    true
  end
end
ENV['PLAN_TTL_ANONYMOUS'] = (3 * 86_400).to_s
Onetime::Organization.reset_free_tier_limits!
begin
  logic = V2::Logic::Secrets::ConcealSecret.new(MockStrategyResult.anonymous, { 'secret' => { 'secret' => 's' } }, 'en')
  logic.send(:anonymous_max_ttl, 2_592_000)
ensure
  class << billing
    remove_method :enabled?
  end
  ENV.delete('PLAN_TTL_ANONYMOUS')
  Onetime::Organization.reset_free_tier_limits!
end
#=> 259_200
