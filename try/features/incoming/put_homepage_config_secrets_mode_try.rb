# try/features/incoming/put_homepage_config_secrets_mode_try.rb
#
# frozen_string_literal: true

# Tests for PutHomepageConfig logic class: secrets_mode validation.
#
# The homepage secrets_mode selects which interactive experience an enabled
# homepage presents ('create' | 'incoming'). Selecting 'incoming' requires:
#   1. the instance feature flag (features.incoming.enabled)
#   2. the org's incoming_secrets entitlement (granted automatically in
#      tests — billing disabled means STANDALONE_ENTITLEMENTS)
#   3. a ready IncomingConfig (enabled with at least one recipient)
#
# Also covers the merge semantics (omitted mode leaves the stored value
# unchanged) and the documented write-path bypass: re-enabling a homepage
# whose STORED mode is incoming does not re-validate readiness — the
# bootstrap serializer's effective-enabled downgrade is the read-path guard.

require_relative '../../support/test_helpers'

OT.boot! :test, false

# Store original config and enable incoming feature
@original_conf = YAML.load(YAML.dump(OT.conf))

def set_incoming_feature(enabled)
  new_conf = YAML.load(YAML.dump(OT.conf))
  new_conf['features'] ||= {}
  new_conf['features']['incoming'] ||= {}
  new_conf['features']['incoming']['enabled'] = enabled
  OT.send(:conf=, new_conf)
end

set_incoming_feature(true)

require 'api/domains/logic/base'
require 'api/domains/logic/homepage_config/base'
require 'api/domains/logic/homepage_config/put_homepage_config'

HomepageConfig = Onetime::CustomDomain::HomepageConfig
IncomingConfig = Onetime::CustomDomain::IncomingConfig
PutHomepageConfig = DomainsAPI::Logic::HomepageConfig::PutHomepageConfig

@ts = Familia.now.to_i
@entropy = SecureRandom.hex(4)

@test_email = "put_hpsm_#{@ts}_#{@entropy}@test.com"
@test_cust = Onetime::Customer.create!(email: @test_email)
@test_org = Onetime::Organization.create!("Put HpSm Test #{@ts}", @test_cust, "org_hpsm_#{@ts}@test.com")

@test_domain_display = "put-hpsm-#{@ts}-#{@entropy}.example.com"
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

## Fixture: test domain exists with the bootstrap HomepageConfig
[@test_domain.exists?, HomepageConfig.exists_for_domain?(@test_domain.identifier)]
#=> [true, true]

## Fixture: organization has incoming_secrets entitlement (standalone mode)
@test_org.can?('incoming_secrets')
#=> true

# --- secrets_mode=incoming rejected while incoming is not ready ---

## Rejected when the domain has no IncomingConfig at all
begin
  run_put(@test_cust, @test_domain, { 'enabled' => true, 'secrets_mode' => 'incoming' })
  'unexpected_success'
rescue OT::FormError => e
  e.message.include?('at least one recipient')
end
#=> true

## Rejected when IncomingConfig is enabled but has zero recipients
IncomingConfig.create!(domain_id: @test_domain.identifier, enabled: true, recipients: [])
begin
  run_put(@test_cust, @test_domain, { 'enabled' => true, 'secrets_mode' => 'incoming' })
  'unexpected_success'
rescue OT::FormError => e
  e.message.include?('at least one recipient')
end
#=> true

## Rejected when recipients exist but incoming is disabled
@incoming = IncomingConfig.find_by_domain_id(@test_domain.identifier)
@incoming.add_recipient(email: "sec_#{@entropy}@example.com", name: 'Security')
@incoming.disable!
begin
  run_put(@test_cust, @test_domain, { 'enabled' => true, 'secrets_mode' => 'incoming' })
  'unexpected_success'
rescue OT::FormError => e
  e.message.include?('at least one recipient')
end
#=> true

# --- secrets_mode=incoming accepted once ready ---

## Accepted when incoming is enabled with a recipient; response carries the mode
@incoming.enable!
@result = run_put(@test_cust, @test_domain, { 'enabled' => true, 'secrets_mode' => 'incoming' })
[@result[:record][:enabled], @result[:record][:secrets_mode]]
#=> [true, 'incoming']

## Stored record reflects the selection
HomepageConfig.find_by_domain_id(@test_domain.identifier).secrets_mode_value
#=> 'incoming'

# --- merge semantics ---

## PUT without secrets_mode leaves the stored incoming selection unchanged
@result = run_put(@test_cust, @test_domain, { 'enabled' => false })
[@result[:record][:enabled], @result[:record][:secrets_mode]]
#=> [false, 'incoming']

## Documented write-path bypass: re-enabling with stored mode incoming does
## not re-validate readiness (the serializer's effective-enabled downgrade
## is the read-path guard for the drift state)
@incoming.disable!
@result = run_put(@test_cust, @test_domain, { 'enabled' => true })
[@result[:record][:enabled], @result[:record][:secrets_mode]]
#=> [true, 'incoming']

## Switching back to create mode always succeeds
@result = run_put(@test_cust, @test_domain, { 'enabled' => true, 'secrets_mode' => 'create' })
@result[:record][:secrets_mode]
#=> 'create'

# --- invalid values ---

## An unrecognised secrets_mode is rejected loudly (not silently coerced)
begin
  run_put(@test_cust, @test_domain, { 'enabled' => true, 'secrets_mode' => 'bogus' })
  'unexpected_success'
rescue OT::FormError => e
  e.message
end
#=> 'Invalid secrets_mode: bogus'

# --- instance feature flag ---

## secrets_mode=incoming is rejected when features.incoming.enabled is off
@incoming.enable!
set_incoming_feature(false)
begin
  run_put(@test_cust, @test_domain, { 'enabled' => true, 'secrets_mode' => 'incoming' })
  'unexpected_success'
rescue OT::FormError => e
  e.message.include?('not enabled on this instance')
end
#=> true

## create mode is unaffected by the incoming feature flag
@result = run_put(@test_cust, @test_domain, { 'enabled' => true, 'secrets_mode' => 'create' })
@result[:record][:secrets_mode]
#=> 'create'

# Teardown
OT.send(:conf=, @original_conf)
@test_domain.destroy!
@test_cust.destroy!
