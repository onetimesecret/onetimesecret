# try/unit/models/custom_domain_signup_config_try.rb
#
# frozen_string_literal: true

# Integration tests for CustomDomain::SignupConfig model
#
# Covers:
#   - SignupConfig creation with valid attributes
#   - Validation (missing domain_id, missing strategy, invalid strategy)
#   - Strategy metadata (requires_allowlist, network_validation)
#   - valid_signup_email? dispatch for each strategy
#   - valid_email_domain? against allowed_signup_domains
#   - find_by_domain_id, exists_for_domain?, delete_for_domain!
#   - enable!/disable! state management
#
# Run:
#   try try/unit/models/custom_domain_signup_config_try.rb --agent

require_relative '../../support/test_models'

OT.boot! :test

Familia.dbclient.flushdb
OT.info "Cleaned Redis for SignupConfig test run"

@ts = Familia.now.to_i
@entropy = SecureRandom.hex(4)
@owner = Onetime::Customer.create!(email: "sc_owner_#{@ts}_#{@entropy}@test.com")
@org = Onetime::Organization.create!("SC Test Org #{@ts}", @owner, "sc_#{@ts}@test.com")
@domain = Onetime::CustomDomain.create!("sc-test-#{@ts}.example.com", @org.objid)

# --- Constants ---

## SignupConfig defines STRATEGY_TYPES constant
Onetime::CustomDomain::SignupConfig::STRATEGY_TYPES
#=> ["passthrough", "domain_allowlist", "mx", "smtp"]

## STRATEGY_METADATA includes all strategies
Onetime::CustomDomain::SignupConfig::STRATEGY_METADATA.keys.sort
#=> ["domain_allowlist", "mx", "passthrough", "smtp"]

# --- Creation ---

## SignupConfig.create! with passthrough strategy returns SignupConfig
@config = Onetime::CustomDomain::SignupConfig.create!(
  domain_id: @domain.identifier,
  validation_strategy: 'passthrough',
  enabled: true,
)
@config.class
#=> Onetime::CustomDomain::SignupConfig

## Created config has correct domain_id
@config.domain_id
#=> @domain.identifier

## Created config has correct strategy
@config.validation_strategy
#=> 'passthrough'

## Config is enabled
@config.enabled?
#=> true

## SignupConfig.exists_for_domain? returns true after creation
Onetime::CustomDomain::SignupConfig.exists_for_domain?(@domain.identifier)
#=> true

## SignupConfig.find_by_domain_id loads the config
@loaded = Onetime::CustomDomain::SignupConfig.find_by_domain_id(@domain.identifier)
@loaded.validation_strategy
#=> 'passthrough'

# --- Strategy Metadata ---

## passthrough does not require allowlist
@config.requires_allowlist?
#=> false

## passthrough is not network validation
@config.network_validation?
#=> false

## domain_allowlist strategy requires allowlist
@cfg_allowlist = Onetime::CustomDomain::SignupConfig.new(domain_id: 'test_dummy', validation_strategy: 'domain_allowlist')
@cfg_allowlist.requires_allowlist?
#=> true

## mx strategy is network validation
@cfg_mx = Onetime::CustomDomain::SignupConfig.new(domain_id: 'test_dummy2', validation_strategy: 'mx')
@cfg_mx.network_validation?
#=> true

# --- Enable / Disable ---

## disable! sets enabled to false
@config.disable!
@config.enabled?
#=> false

## enable! sets enabled to true
@config.enable!
@config.enabled?
#=> true

# --- Validation Errors ---

## new config without domain_id has validation errors
@empty_config = Onetime::CustomDomain::SignupConfig.new
@empty_config.validation_errors.include?('domain_id is required')
#=> true

## valid? returns false for invalid config
@empty_config.valid?
#=> false

## domain_allowlist without domains is invalid
@allowlist_only = Onetime::CustomDomain::SignupConfig.new(
  domain_id: 'dummy_id',
  validation_strategy: 'domain_allowlist',
)
@allowlist_only.validation_errors.any? { |e| e.include?('allowed_signup_domains') }
#=> true

# --- valid_signup_email? Dispatch ---

## passthrough strategy accepts valid email format
@config.validation_strategy = 'passthrough'
@config.valid_signup_email?('user@example.com')
#=> true

## passthrough strategy rejects malformed email
@config.valid_signup_email?('not-an-email')
#=> false

## domain_allowlist accepts email from allowed domain
@ts2 = Familia.now.to_i
@domain2 = Onetime::CustomDomain.create!("sc-allowlist-#{@ts2}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@allowlist_config = Onetime::CustomDomain::SignupConfig.create!(
  domain_id: @domain2.identifier,
  validation_strategy: 'domain_allowlist',
  allowed_signup_domains: ['acme.com', 'corp.com'],
  enabled: true,
)
@allowlist_config.valid_signup_email?('user@acme.com')
#=> true

## domain_allowlist rejects email from non-allowed domain
@allowlist_config.valid_signup_email?('user@evil.com')
#=> false

## domain_allowlist normalizes case
@allowlist_config.valid_signup_email?('USER@ACME.COM')
#=> true

# --- allowed_signup_domains roundtrip ---

## allowed_signup_domains stores as JSON
@allowlist_config.allowed_signup_domains.sort
#=> ['acme.com', 'corp.com']

## allowed_signup_domains can be cleared
@allowlist_config.allowed_signup_domains = []
@allowlist_config.allowed_signup_domains
#=> []

# --- valid_email_domain? ---

## valid_email_domain? returns true when allowlist is empty
@allowlist_config.allowed_signup_domains = []
@allowlist_config.valid_email_domain?('anyone@anywhere.com')
#=> true

## valid_email_domain? checks against allowlist
@allowlist_config.allowed_signup_domains = ['acme.com']
@allowlist_config.valid_email_domain?('user@acme.com')
#=> true

## valid_email_domain? rejects non-allowed
@allowlist_config.valid_email_domain?('user@other.com')
#=> false

# --- Class Methods ---

## class returns strategy_metadata
Onetime::CustomDomain::SignupConfig.strategy_metadata.is_a?(Hash)
#=> true

## metadata_for returns metadata for a strategy
Onetime::CustomDomain::SignupConfig.metadata_for('passthrough')[:description].is_a?(String)
#=> true

## metadata_for returns empty hash for unknown
Onetime::CustomDomain::SignupConfig.metadata_for('unknown')
#=> {}

# --- Deletion ---

## delete_for_domain! removes the config
Onetime::CustomDomain::SignupConfig.delete_for_domain!(@domain.identifier)
#=> true

## After deletion, find_by_domain_id returns nil
Onetime::CustomDomain::SignupConfig.find_by_domain_id(@domain.identifier)
#=> nil

## delete_for_domain! returns false for nonexistent
Onetime::CustomDomain::SignupConfig.delete_for_domain!('nonexistent_id')
#=> false

## create! raises Problem if config already exists
@dup_config = Onetime::CustomDomain::SignupConfig.create!(
  domain_id: @domain.identifier,
  validation_strategy: 'passthrough',
)
begin
  Onetime::CustomDomain::SignupConfig.create!(
    domain_id: @domain.identifier,
    validation_strategy: 'mx',
  )
  :no_error
rescue Onetime::Problem
  :raised_problem
end
#=> :raised_problem

# --- Corrupted JSON Fail-Open Behavior ---
#
# Security note: When allowed_signup_domains_json contains invalid JSON,
# allowed_signup_domains silently returns [] which makes valid_email_domain?
# return true for ANY email. This is intentional fail-open behavior to avoid
# blocking legitimate signups due to data corruption, but operators should
# monitor for JSON parse errors in production logs.

## Create config with valid allowlist to corrupt
@ts3 = Familia.now.to_i
@domain3 = Onetime::CustomDomain.create!("sc-corrupt-#{@ts3}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@corrupt_config = Onetime::CustomDomain::SignupConfig.create!(
  domain_id: @domain3.identifier,
  validation_strategy: 'domain_allowlist',
  allowed_signup_domains: ['valid.com'],
  enabled: true,
)
@corrupt_config.allowed_signup_domains
#=> ['valid.com']

## Manually corrupt the JSON field
@corrupt_config.allowed_signup_domains_json = '{invalid json['
@corrupt_config.save
@corrupt_config.allowed_signup_domains_json
#=> '{invalid json['

## allowed_signup_domains returns empty array on corrupted JSON
@corrupt_config.allowed_signup_domains
#=> []

## valid_email_domain? returns true for ANY email when allowlist is corrupted (fail-open)
@corrupt_config.valid_email_domain?('anyone@anywhere.com')
#=> true

## valid_email_domain? returns true for previously-restricted domain
@corrupt_config.valid_email_domain?('attacker@evil.com')
#=> true

## valid_signup_email? with domain_allowlist strategy still validates format
@corrupt_config.valid_signup_email?('not-an-email')
#=> false

## valid_signup_email? allows any valid email format when JSON is corrupted
@corrupt_config.valid_signup_email?('anyone@anywhere.com')
#=> true

# --- Cleanup ---

Familia.dbclient.flushdb
OT.info "Cleaned Redis after SignupConfig test run"
