# try/unit/logic/secrets/base_secret_action_try.rb
#
# frozen_string_literal: true

# Tests for V1 BaseSecretAction#validate_domain_permissions.
# Validates that non-owners are rejected with FormError when attempting
# to create a secret on a domain they don't own (canonical domain path).

require_relative '../../../support/test_helpers'

OT.boot! :test, false

require 'v1/logic'
require 'apps/api/domains/logic/base'
require 'apps/api/domains/logic/domains/add_domain'

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
