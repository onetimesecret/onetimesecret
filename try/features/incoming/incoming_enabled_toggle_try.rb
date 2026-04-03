# try/features/incoming/incoming_enabled_toggle_try.rb
#
# frozen_string_literal: true

# Tests for the explicit enabled toggle feature on IncomingConfig.
#
# Key coverage:
# 1. enabled=true with recipients -> incoming secrets work normally
# 2. enabled=false with recipients -> incoming secrets rejected (NEW BEHAVIOR)
# 3. enabled=true without recipients -> effectively disabled (no recipients to notify)
# 4. enable!/disable! transitions -> state changes correctly
# 5. RecipientResolver.enabled? -> returns correct value based on IncomingConfig.enabled
#
# The critical behavior change is #2: previously, enabled was derived from
# whether recipients existed. Now there's an explicit toggle that can disable
# incoming secrets while preserving recipient configuration.
#
# Architecture Note:
# - IncomingConfig (new model): stores explicit `enabled` field + `recipients_json`
# - IncomingSecretsConfig (legacy): stored in CustomDomain's jsonkey, has_incoming_recipients?
# - RecipientResolver: uses IncomingConfig.enabled? when present, else legacy fallback
# - RecipientResolver.public_recipients: reads from IncomingSecretsConfig for display

require_relative '../../support/test_logic'
require 'apps/api/incoming/logic/incoming'

OT.boot! :test, false

require 'onetime/models/custom_domain/incoming_config'
require_relative '../../../lib/onetime/incoming/recipient_resolver'

IncomingConfig = Onetime::CustomDomain::IncomingConfig
RecipientResolver = Onetime::Incoming::RecipientResolver

@ts = Familia.now.to_i
@entropy = SecureRandom.hex(4)

# --- SETUP: Create test fixtures ---

@test_email = "enabled_toggle_#{@ts}_#{@entropy}@test.com"
@test_cust = Onetime::Customer.create!(email: @test_email)
@test_org = Onetime::Organization.create!("Enabled Toggle Test #{@ts}", @test_cust, "org_toggle_#{@ts}@test.com")
@test_domain_display = "toggle-test-#{@ts}-#{@entropy}.example.com"
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

# --- IncomingConfig ENABLED STATE TESTS ---

## New IncomingConfig defaults to disabled
config = IncomingConfig.create!(domain_id: "default_state_#{@ts}_1")
result = config.enabled?
config.destroy!
result
#=> false

## IncomingConfig can be created with enabled: true
config = IncomingConfig.create!(domain_id: "create_enabled_#{@ts}_1", enabled: true)
result = config.enabled?
config.destroy!
result
#=> true

## IncomingConfig can be created with enabled: false explicitly
config = IncomingConfig.create!(domain_id: "create_disabled_#{@ts}_1", enabled: false)
result = config.enabled?
config.destroy!
result
#=> false

## enable! transitions from false to true
config = IncomingConfig.create!(domain_id: "enable_trans_#{@ts}_1")
config.enabled?  # starts false
config.enable!
result = config.enabled?
config.destroy!
result
#=> true

## disable! transitions from true to false
config = IncomingConfig.create!(domain_id: "disable_trans_#{@ts}_1", enabled: true)
config.enabled?  # starts true
config.disable!
result = config.enabled?
config.destroy!
result
#=> false

## enable! is idempotent (calling twice stays true)
config = IncomingConfig.create!(domain_id: "enable_idem_#{@ts}_1")
config.enable!
config.enable!
result = config.enabled?
config.destroy!
result
#=> true

## disable! is idempotent (calling twice stays false)
config = IncomingConfig.create!(domain_id: "disable_idem_#{@ts}_1", enabled: true)
config.disable!
config.disable!
result = config.enabled?
config.destroy!
result
#=> false

## enable! persists state change (verify via reload)
config = IncomingConfig.create!(domain_id: "enable_persist_#{@ts}_1")
config.enable!
reloaded = IncomingConfig.load("enable_persist_#{@ts}_1")
result = reloaded.enabled?
config.destroy!
result
#=> true

## disable! persists state change (verify via reload)
config = IncomingConfig.create!(domain_id: "disable_persist_#{@ts}_1", enabled: true)
config.disable!
reloaded = IncomingConfig.load("disable_persist_#{@ts}_1")
result = reloaded.enabled?
config.destroy!
result
#=> false

# --- CRITICAL CASE: DISABLED WITH RECIPIENTS (NEW BEHAVIOR) ---

## Disabled config with recipients reports disabled
config = IncomingConfig.create!(domain_id: "disabled_with_recip_#{@ts}_1")
config.recipients = [{ email: 'test@example.com', name: 'Test' }]
config.save
config.disable!
result = [config.enabled?, config.recipients.size]
config.destroy!
result
#=> [false, 1]

## Recipients can be modified while disabled
config = IncomingConfig.create!(domain_id: "modify_while_disabled_#{@ts}_1")
config.disable!
config.recipients = [
  { email: 'first@example.com', name: 'First' },
  { email: 'second@example.com', name: 'Second' }
]
config.save
result = [config.enabled?, config.recipients.size]
config.destroy!
result
#=> [false, 2]

## Enabling after adding recipients preserves recipients
config = IncomingConfig.create!(domain_id: "enable_after_recip_#{@ts}_1")
config.recipients = [{ email: 'preserved@example.com', name: 'Preserved' }]
config.save
config.enable!
result = [config.enabled?, config.recipients.first[:email]]
config.destroy!
result
#=> [true, "preserved@example.com"]

## Disabling preserves recipients (round-trip)
config = IncomingConfig.create!(domain_id: "disable_preserve_#{@ts}_1", enabled: true)
config.recipients = [{ email: 'roundtrip@example.com', name: 'RoundTrip' }]
config.save
config.disable!
config.enable!
config.disable!
result = [config.enabled?, config.recipients.first[:email]]
config.destroy!
result
#=> [false, "roundtrip@example.com"]

# --- ENABLED WITHOUT RECIPIENTS ---

## Enabled without recipients has no public_recipients
config = IncomingConfig.create!(domain_id: "enabled_no_recip_#{@ts}_1", enabled: true)
result = [config.enabled?, config.public_recipients.size]
config.destroy!
result
#=> [true, 0]

## Enabled without recipients: lookup returns nil for any hash
config = IncomingConfig.create!(domain_id: "enabled_no_recip_lookup_#{@ts}_1", enabled: true)
result = config.lookup_recipient_email('any_hash_value')
config.destroy!
result
#=> nil

# --- RECIPIENT RESOLVER WITH IncomingConfig (NEW MODEL) ---
# RecipientResolver uses IncomingConfig.enabled? when IncomingConfig exists,
# and reads recipients from IncomingSecretsConfig (legacy store) for public display.

## Setup: Create IncomingConfig for test domain with enabled=true
@incoming_config = IncomingConfig.create!(
  domain_id: @test_domain.identifier,
  enabled: true,
  recipients: [{ email: 'resolver-test@example.com', name: 'Resolver Test' }]
)
# Also populate legacy IncomingSecretsConfig so RecipientResolver can read recipients
legacy_config = @test_domain.incoming_secrets_config
legacy_config.set_incoming_recipients([{ 'email' => 'resolver-test@example.com', 'name' => 'Resolver Test' }])
@test_domain.update_incoming_secrets_config(legacy_config)
@test_domain.exists?
#=> true

## RecipientResolver uses IncomingConfig.enabled? when IncomingConfig exists
resolver = RecipientResolver.new(domain_strategy: :custom, display_domain: @test_domain_display)
resolver.enabled?
#=> true

## RecipientResolver returns false when IncomingConfig.enabled=false (even with recipients)
@incoming_config.disable!
resolver = RecipientResolver.new(domain_strategy: :custom, display_domain: @test_domain_display)
resolver.enabled?
#=> false

## RecipientResolver.public_recipients returns recipients from legacy config when disabled
# Recipients are available for UI display even when incoming is disabled
resolver = RecipientResolver.new(domain_strategy: :custom, display_domain: @test_domain_display)
resolver.public_recipients.size
#=> 1

## RecipientResolver.enabled? returns true after re-enabling
@incoming_config.enable!
resolver = RecipientResolver.new(domain_strategy: :custom, display_domain: @test_domain_display)
resolver.enabled?
#=> true

## RecipientResolver config_data reflects enabled=false state with recipients visible
@incoming_config.disable!
resolver = RecipientResolver.new(domain_strategy: :custom, display_domain: @test_domain_display)
data = resolver.config_data
[data[:enabled], data[:recipients].size]
#=> [false, 1]

## RecipientResolver config_data shows enabled=true when enabled
@incoming_config.enable!
resolver = RecipientResolver.new(domain_strategy: :custom, display_domain: @test_domain_display)
data = resolver.config_data
data[:enabled]
#=> true

# --- LEGACY FALLBACK BEHAVIOR ---
# When no IncomingConfig exists, RecipientResolver falls back to
# IncomingSecretsConfig.has_incoming_recipients?

## Create second domain without IncomingConfig for legacy fallback test
@legacy_domain_display = "legacy-#{@ts}-#{@entropy}.example.com"
@legacy_domain = Onetime::CustomDomain.create!(@legacy_domain_display, @test_org.objid)
@legacy_domain.exists?
#=> true

## Legacy fallback: no recipients means disabled
resolver = RecipientResolver.new(domain_strategy: :custom, display_domain: @legacy_domain_display)
resolver.enabled?
#=> false

## Legacy fallback: adding recipients via IncomingSecretsConfig enables
legacy_config = @legacy_domain.incoming_secrets_config
legacy_config.set_incoming_recipients([{ 'email' => 'legacy@example.com', 'name' => 'Legacy' }])
@legacy_domain.update_incoming_secrets_config(legacy_config)
resolver = RecipientResolver.new(domain_strategy: :custom, display_domain: @legacy_domain_display)
resolver.enabled?
#=> true

# --- API-LEVEL INTEGRATION TESTS ---
# These tests verify that the API logic classes (ValidateRecipient, CreateIncomingSecret)
# correctly reject requests when IncomingConfig.enabled=false, even with recipients configured.
# This exercises the full production flow, not just the RecipientResolver primitive.

## API Integration: Setup domain with enabled=false and recipients configured
@api_domain_display = "api-toggle-#{@ts}-#{@entropy}.example.com"
@api_domain = Onetime::CustomDomain.create!(@api_domain_display, @test_org.objid)
@api_recipient_email = "api-recipient+#{@ts}@example.com"
api_incoming_secrets_config = Onetime::CustomDomain::IncomingSecretsConfig.new({
  'recipients' => [{ 'email' => @api_recipient_email, 'name' => 'API Test Recipient' }],
  'memo_max_length' => 100,
  'default_ttl' => 604800
})
@api_domain.update_incoming_secrets_config(api_incoming_secrets_config)
site_secret = OT.conf.dig('site', 'secret')
@api_recipient_hash = @api_domain.incoming_secrets_config.public_incoming_recipients(site_secret).first['hash']
@api_incoming_config = IncomingConfig.create!(
  domain_id: @api_domain.identifier,
  enabled: false,
  recipients: [{ email: @api_recipient_email, name: 'API Test Recipient' }]
)
@api_domain.exists?
#=> true

## API Integration: ValidateRecipient rejects when IncomingConfig.enabled=false
# Even though recipients are configured, the API should reject validation requests
# when the explicit enabled toggle is false.
strategy = create_strategy_with_domain(@test_cust, @api_domain_display)
logic = Incoming::Logic::ValidateRecipient.new(strategy, { 'recipient' => @api_recipient_hash })
logic.process_params
begin
  logic.raise_concerns
  false # Should not reach here
rescue OT::FormError => e
  e.message.include?('not enabled')
end
#=> true

## API Integration: CreateIncomingSecret rejects when IncomingConfig.enabled=false
# The secret creation endpoint should also reject when enabled=false.
strategy = create_strategy_with_domain(@test_cust, @api_domain_display)
logic = Incoming::Logic::CreateIncomingSecret.new(strategy, {
  'secret' => {
    'memo' => 'Test memo',
    'secret' => 'Sensitive content',
    'recipient' => @api_recipient_hash
  }
})
logic.process_params
begin
  logic.raise_concerns
  false # Should not reach here
rescue OT::FormError => e
  e.message.include?('not enabled')
end
#=> true

## API Integration: ValidateRecipient succeeds after enabling IncomingConfig
# Re-enable and verify the API accepts requests
@api_incoming_config.enable!
strategy = create_strategy_with_domain(@test_cust, @api_domain_display)
logic = Incoming::Logic::ValidateRecipient.new(strategy, { 'recipient' => @api_recipient_hash })
logic.process_params
logic.raise_concerns
result = logic.process
result[:valid]
#=> true

## API Integration: CreateIncomingSecret succeeds after enabling IncomingConfig
strategy = create_strategy_with_domain(@test_cust, @api_domain_display)
logic = Incoming::Logic::CreateIncomingSecret.new(strategy, {
  'secret' => {
    'memo' => 'Enabled memo',
    'secret' => 'Enabled secret content',
    'recipient' => @api_recipient_hash
  }
})
logic.process_params
logic.raise_concerns
result = logic.process
result[:success]
#=> true

## API Integration: Disabling again blocks requests (round-trip)
@api_incoming_config.disable!
strategy = create_strategy_with_domain(@test_cust, @api_domain_display)
logic = Incoming::Logic::ValidateRecipient.new(strategy, { 'recipient' => @api_recipient_hash })
logic.process_params
begin
  logic.raise_concerns
  false
rescue OT::FormError => e
  e.message.include?('not enabled')
end
#=> true

## API Integration: GetConfig returns enabled=false with recipients visible
# The config endpoint should still return recipients (for UI display) even when disabled
@api_incoming_config.disable!
strategy = create_strategy_with_domain(@test_cust, @api_domain_display)
logic = Incoming::Logic::GetConfig.new(strategy, {})
logic.process_params
logic.raise_concerns
result = logic.process
[result[:config][:enabled], result[:config][:recipients].size > 0]
#=> [false, true]

## API Integration: GetConfig returns enabled=true when enabled
@api_incoming_config.enable!
strategy = create_strategy_with_domain(@test_cust, @api_domain_display)
logic = Incoming::Logic::GetConfig.new(strategy, {})
logic.process_params
logic.raise_concerns
result = logic.process
result[:config][:enabled]
#=> true

## Cleanup API integration test fixtures
@api_incoming_config.disable! # Leave in disabled state for final cleanup
@api_incoming_config.destroy! rescue nil
@api_domain.destroy! rescue nil
true
#=> true

# --- TEARDOWN ---

## Cleanup test fixtures
begin
  @incoming_config.destroy! rescue nil
  @test_domain.destroy! rescue nil
  @legacy_domain.destroy! rescue nil
  @test_org.destroy! rescue nil
  @test_cust.destroy! rescue nil
  true
rescue => e
  "cleanup_error: #{e.class}"
end
#=> true
