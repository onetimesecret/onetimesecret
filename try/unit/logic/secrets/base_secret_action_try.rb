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

## V2: anonymous_max_ttl fails open to the config max when billing is disabled
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
#=> 2592000

## V2: anonymous_max_ttl caps at the free-tier secret_lifetime limit when billing is enabled
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
#==> _ == [Onetime::Organization.free_tier_limits['secret_lifetime.max'], 2_592_000].min
