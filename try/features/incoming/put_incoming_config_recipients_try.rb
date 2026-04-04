# try/features/incoming/put_incoming_config_recipients_try.rb
#
# frozen_string_literal: true

# Tests for PutIncomingConfig logic class: recipients preservation behavior.
#
# Bug fix coverage (#2865):
# 1. PUT with only `enabled` preserves existing recipients (the bug fix)
# 2. PUT with `recipients` explicitly provided updates them
# 3. PUT with empty `recipients: []` clears recipients
# 4. PUT with `recipients` null/undefined preserves existing
#
# These tests verify the API logic layer, not just the model layer.
# The key fix is checking `params.key?('recipients')` to distinguish:
# - "recipients was not sent" (preserve existing)
# - "recipients was sent as []" (explicitly clear)

require_relative '../../support/test_helpers'

OT.boot! :test, false

# Store original config and enable incoming feature
@original_conf = YAML.load(YAML.dump(OT.conf))

def enable_incoming_feature
  new_conf = YAML.load(YAML.dump(OT.conf))
  new_conf['features'] ||= {}
  new_conf['features']['incoming'] ||= {}
  new_conf['features']['incoming']['enabled'] = true
  OT.send(:conf=, new_conf)
end

def restore_original_config(original_conf)
  OT.send(:conf=, original_conf)
end

# Enable incoming feature for all tests
enable_incoming_feature

require 'apps/api/domains/logic/base'
require 'apps/api/domains/logic/incoming_config/base'
require 'apps/api/domains/logic/incoming_config/put_incoming_config'
require 'onetime/models/custom_domain/incoming_config'

IncomingConfig = Onetime::CustomDomain::IncomingConfig
PutIncomingConfig = DomainsAPI::Logic::IncomingConfig::PutIncomingConfig

@ts = Familia.now.to_i
@entropy = SecureRandom.hex(4)

# --- SETUP: Create test fixtures ---

@test_email = "put_recip_#{@ts}_#{@entropy}@test.com"
@test_cust = Onetime::Customer.create!(email: @test_email)
@test_org = Onetime::Organization.create!("Put Recipients Test #{@ts}", @test_cust, "org_put_#{@ts}@test.com")

# Note: Billing is disabled in tests, so organizations get STANDALONE_ENTITLEMENTS
# which includes 'incoming_secrets' automatically.

@test_domain_display = "put-recip-#{@ts}-#{@entropy}.example.com"
@test_domain = Onetime::CustomDomain.create!(@test_domain_display, @test_org.objid)

# Helper to create a strategy result with domain metadata for API integration tests
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

# Create initial IncomingConfig with recipients for testing
@initial_recipients = [
  { email: 'alice@example.com', name: 'Alice' },
  { email: 'bob@example.com', name: 'Bob' }
]

@incoming_config = IncomingConfig.create!(
  domain_id: @test_domain.identifier,
  enabled: true,
  recipients: @initial_recipients
)

# --- PREREQUISITE TESTS ---

## Fixture: Test domain exists
@test_domain.exists?
#=> true

## Fixture: Initial config has 2 recipients
@incoming_config.recipients.size
#=> 2

## Fixture: Initial config is enabled
@incoming_config.enabled?
#=> true

## Fixture: Organization has incoming_secrets entitlement
@test_org.can?('incoming_secrets')
#=> true

# --- BUG FIX TEST: PUT with only `enabled` preserves existing recipients ---
# This is the primary bug fix test. Previously, toggling enabled would wipe recipients.

## PUT with only enabled=false preserves existing recipients
strategy = create_strategy_with_domain(@test_cust, @test_domain_display)
params = {
  'extid' => @test_domain.extid,
  'enabled' => false
  # Note: 'recipients' key is NOT present in params
}
logic = PutIncomingConfig.new(strategy, params)
logic.process_params
logic.raise_concerns
result = logic.process

# Verify enabled changed
reloaded = IncomingConfig.load(@test_domain.identifier)
reloaded.enabled?
#=> false

## Recipients preserved after enabled-only toggle
reloaded = IncomingConfig.load(@test_domain.identifier)
reloaded.recipients.size
#=> 2

## Recipients content preserved after enabled-only toggle
reloaded = IncomingConfig.load(@test_domain.identifier)
emails = reloaded.recipients.map { |r| r[:email] }.sort
emails
#=> ["alice@example.com", "bob@example.com"]

## PUT with only enabled=true preserves recipients (round-trip)
strategy = create_strategy_with_domain(@test_cust, @test_domain_display)
params = {
  'extid' => @test_domain.extid,
  'enabled' => true
  # Note: 'recipients' key is NOT present in params
}
logic = PutIncomingConfig.new(strategy, params)
logic.process_params
logic.raise_concerns
logic.process

reloaded = IncomingConfig.load(@test_domain.identifier)
[reloaded.enabled?, reloaded.recipients.size]
#=> [true, 2]

# --- EXPLICIT RECIPIENTS UPDATE TESTS ---

## PUT with recipients explicitly provided updates them
strategy = create_strategy_with_domain(@test_cust, @test_domain_display)
params = {
  'extid' => @test_domain.extid,
  'enabled' => true,
  'recipients' => [
    { 'email' => 'charlie@example.com', 'name' => 'Charlie' }
  ]
}
logic = PutIncomingConfig.new(strategy, params)
logic.process_params
logic.raise_concerns
logic.process

reloaded = IncomingConfig.load(@test_domain.identifier)
reloaded.recipients.size
#=> 1

## Recipients content updated when explicitly provided
reloaded = IncomingConfig.load(@test_domain.identifier)
reloaded.recipients.first[:email]
#=> "charlie@example.com"

# --- EMPTY RECIPIENTS ARRAY TEST ---

## PUT with empty recipients array clears recipients
strategy = create_strategy_with_domain(@test_cust, @test_domain_display)
params = {
  'extid' => @test_domain.extid,
  'enabled' => true,
  'recipients' => []  # Explicitly empty array
}
logic = PutIncomingConfig.new(strategy, params)
logic.process_params
logic.raise_concerns
logic.process

reloaded = IncomingConfig.load(@test_domain.identifier)
reloaded.recipients.size
#=> 0

## Enabled state preserved when recipients cleared
reloaded = IncomingConfig.load(@test_domain.identifier)
reloaded.enabled?
#=> true

# --- RESTORE RECIPIENTS FOR FURTHER TESTS ---

## Restore recipients for additional tests
@incoming_config = IncomingConfig.load(@test_domain.identifier)
@incoming_config.recipients = @initial_recipients
@incoming_config.save
@incoming_config.recipients.size
#=> 2

# --- MULTIPLE SEQUENTIAL TOGGLES ---

## Multiple enabled toggles without recipients in params preserve recipients
strategy = create_strategy_with_domain(@test_cust, @test_domain_display)

# First toggle: enabled -> disabled
logic = PutIncomingConfig.new(strategy, { 'extid' => @test_domain.extid, 'enabled' => false })
logic.process_params
logic.raise_concerns
logic.process

# Second toggle: disabled -> enabled
logic = PutIncomingConfig.new(strategy, { 'extid' => @test_domain.extid, 'enabled' => true })
logic.process_params
logic.raise_concerns
logic.process

# Third toggle: enabled -> disabled
logic = PutIncomingConfig.new(strategy, { 'extid' => @test_domain.extid, 'enabled' => false })
logic.process_params
logic.raise_concerns
logic.process

reloaded = IncomingConfig.load(@test_domain.identifier)
[reloaded.enabled?, reloaded.recipients.size]
#=> [false, 2]

# --- TIMESTAMP VERIFICATION ---

## Timestamp updated when only enabled changes (no recipients in params)
@incoming_config = IncomingConfig.load(@test_domain.identifier)
initial_updated = @incoming_config.updated.to_i
sleep 1.01 # Cross second boundary for integer timestamps

strategy = create_strategy_with_domain(@test_cust, @test_domain_display)
logic = PutIncomingConfig.new(strategy, { 'extid' => @test_domain.extid, 'enabled' => true })
logic.process_params
logic.raise_concerns
logic.process

reloaded = IncomingConfig.load(@test_domain.identifier)
reloaded.updated.to_i > initial_updated
#=> true

# --- NEW CONFIG CREATION TESTS ---
# Test that creating a new config still works correctly

## Setup: Create new domain without IncomingConfig
@new_domain_display = "new-config-#{@ts}-#{@entropy}.example.com"
@new_domain = Onetime::CustomDomain.create!(@new_domain_display, @test_org.objid)
@new_domain.exists?
#=> true

## PUT to create new config with enabled only (no recipients key)
strategy = create_strategy_with_domain(@test_cust, @new_domain_display)
params = {
  'extid' => @new_domain.extid,
  'enabled' => true
  # Note: 'recipients' key is NOT present
}
logic = PutIncomingConfig.new(strategy, params)
logic.process_params
logic.raise_concerns
logic.process

new_config = IncomingConfig.load(@new_domain.identifier)
[new_config.enabled?, new_config.recipients.size]
#=> [true, 0]

## PUT to create new config with both enabled and recipients
@another_domain_display = "another-config-#{@ts}-#{@entropy}.example.com"
@another_domain = Onetime::CustomDomain.create!(@another_domain_display, @test_org.objid)

strategy = create_strategy_with_domain(@test_cust, @another_domain_display)
params = {
  'extid' => @another_domain.extid,
  'enabled' => true,
  'recipients' => [
    { 'email' => 'new@example.com', 'name' => 'New' }
  ]
}
logic = PutIncomingConfig.new(strategy, params)
logic.process_params
logic.raise_concerns
logic.process

another_config = IncomingConfig.load(@another_domain.identifier)
[another_config.enabled?, another_config.recipients.size]
#=> [true, 1]

# --- RESPONSE FORMAT TESTS ---

## Response includes serialized config with recipients
strategy = create_strategy_with_domain(@test_cust, @test_domain_display)
params = {
  'extid' => @test_domain.extid,
  'enabled' => true
}
logic = PutIncomingConfig.new(strategy, params)
logic.process_params
logic.raise_concerns
@response_result = logic.process

@response_result[:record].key?(:recipients)
#=> true

## Response record includes enabled field
@response_result[:record].key?(:enabled)
#=> true

# --- TEARDOWN ---

## Cleanup test fixtures
begin
  restore_original_config(@original_conf)
  IncomingConfig.find_by_domain_id(@test_domain.identifier)&.destroy!
  IncomingConfig.find_by_domain_id(@new_domain.identifier)&.destroy!
  IncomingConfig.find_by_domain_id(@another_domain.identifier)&.destroy!
  @test_domain.destroy!
  @new_domain.destroy!
  @another_domain.destroy!
  @test_org.destroy!
  @test_cust.destroy!
  true
rescue => e
  "cleanup_error: #{e.class}: #{e.message}"
end
#=> true
