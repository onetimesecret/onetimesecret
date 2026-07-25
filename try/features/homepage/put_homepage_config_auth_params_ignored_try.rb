# try/features/homepage/put_homepage_config_auth_params_ignored_try.rb
#
# frozen_string_literal: true

# Tests for PutHomepageConfig logic class: deprecated auth-link params are
# ignored (#3672, ADR-030).
#
# signup_enabled/signin_enabled once toggled the homepage masthead auth links
# via HomepageConfig, but authority moved to the per-concern SigninConfig /
# SignupConfig records — the bootstrap serializer computes the masthead
# values from those resolvers, never from HomepageConfig's fields. The
# 2026-07-03 migration flipped all stored values to false.
#
# Contract under test: a raw-API client submitting these params gets a
# successful PUT (no 422 — GET still echoes the fields, so read-modify-write
# clients round-trip them back), a deprecation warning in the logs, and NO
# stored-state change: the fields remain false no matter what was submitted.
# All other submitted fields persist normally.

require_relative '../../support/test_helpers'

OT.boot! :test, false

require 'api/domains/logic/base'
require 'api/domains/logic/homepage_config/base'
require 'api/domains/logic/homepage_config/put_homepage_config'

HomepageConfig = Onetime::CustomDomain::HomepageConfig
PutHomepageConfig = DomainsAPI::Logic::HomepageConfig::PutHomepageConfig

@ts = Familia.now.to_i
@entropy = SecureRandom.hex(4)

@test_email = "put_hpauth_#{@ts}_#{@entropy}@test.com"
@test_cust = Onetime::Customer.create!(email: @test_email)
@test_org = Onetime::Organization.create!("Put HpAuth Test #{@ts}", @test_cust, "org_hpauth_#{@ts}@test.com")

@test_domain_display = "put-hpauth-#{@ts}-#{@entropy}.example.com"
@test_domain = Onetime::CustomDomain.create!(@test_domain_display, @test_org.objid)

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

# --- PREREQUISITES ---

## Fixture: test domain exists with the bootstrap HomepageConfig, auth links OFF
@config = HomepageConfig.find_by_domain_id(@test_domain.identifier)
[@test_domain.exists?, @config.signup_enabled?, @config.signin_enabled?]
#=> [true, false, false]

# --- deprecated params are accepted but ignored ---

## PUT submitting signin_enabled/signup_enabled true succeeds (no 422) and
## the response echo still reports the stored (false) values
@result = run_put(@test_cust, @test_domain, {
  'enabled' => true,
  'signup_enabled' => true,
  'signin_enabled' => true,
})
[@result[:record][:enabled], @result[:record][:signup_enabled], @result[:record][:signin_enabled]]
#=> [true, false, false]

## Stored HomepageConfig fields remain false — the params changed nothing
@stored = HomepageConfig.find_by_domain_id(@test_domain.identifier)
[@stored.signup_enabled?, @stored.signin_enabled?]
#=> [false, false]

## The deprecation warning is emitted exactly when deprecated params are
## present, and not on a clean PUT — intercept OT.lw so the logged half of
## the contract can't regress silently
captured = []
original_lw = OT.method(:lw)
OT.define_singleton_method(:lw) { |*msgs, **_payload| captured << msgs.join(' ') }
begin
  run_put(@test_cust, @test_domain, {
    'enabled' => true,
    'signup_enabled' => true,
    'signin_enabled' => true,
  })
  @deprecation_warning_count = captured.grep(/deprecated params ignored \(signup_enabled, signin_enabled\)/).length
  captured.clear
  run_put(@test_cust, @test_domain, { 'enabled' => true })
  @clean_put_warning_count = captured.grep(/deprecated params ignored/).length
ensure
  OT.define_singleton_method(:lw, original_lw)
end
[@deprecation_warning_count, @clean_put_warning_count]
#=> [1, 0]

## Other submitted fields still persist alongside the ignored params
@result = run_put(@test_cust, @test_domain, {
  'enabled' => true,
  'signup_enabled' => true,
  'signin_enabled' => true,
  'disabled_homepage_variant' => 'minimal',
  'secrets_mode' => 'create',
})
@stored = HomepageConfig.find_by_domain_id(@test_domain.identifier)
[
  @stored.enabled?,
  @stored.disabled_homepage_variant_value,
  @stored.secrets_mode_value,
  @stored.signup_enabled?,
  @stored.signin_enabled?,
]
#=> [true, 'minimal', 'create', false, false]

## String-valued booleans (form-encoded clients) are equally inert
@result = run_put(@test_cust, @test_domain, {
  'enabled' => true,
  'signup_enabled' => 'true',
  'signin_enabled' => 'true',
})
@stored = HomepageConfig.find_by_domain_id(@test_domain.identifier)
[@stored.signup_enabled?, @stored.signin_enabled?, @result[:record][:signup_enabled], @result[:record][:signin_enabled]]
#=> [false, false, false, false]

## A PUT without the deprecated params behaves identically (baseline)
@result = run_put(@test_cust, @test_domain, { 'enabled' => false })
[@result[:record][:enabled], @result[:record][:signup_enabled], @result[:record][:signin_enabled]]
#=> [false, false, false]

# Teardown — destroy each fixture independently so one failure doesn't leak
# the rest across runs
[@test_domain, @test_org, @test_cust].each do |record|
  record.destroy!
rescue StandardError => e
  OT.le "[teardown] #{record.class} destroy failed: #{e.message}"
end
