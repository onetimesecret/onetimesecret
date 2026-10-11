# try/unit/models/custom_domain/signup_config_try.rb
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
#   - allow_base_domain: the domain's own base_domain joins the allowlist
#   - find_by_domain_id, exists_for_domain?, delete_for_domain!
#   - enable!/disable! state management
#
# Run:
#   try try/unit/models/custom_domain/signup_config_try.rb --agent

require_relative '../../../support/test_models'

OT.boot! :test

Familia.dbclient.flushdb
OT.info "Cleaned Redis for SignupConfig test run"

@ts = Familia.now.to_i
@entropy = SecureRandom.hex(4)
@owner = Onetime::Customer.create!(email: "sc_owner_#{@ts}_#{@entropy}@test.com")
@org = Onetime::Organization.create!("SC Test Org #{@ts}", @owner, "sc_#{@ts}@test.com")
@domain = Onetime::CustomDomain.create!("sc-test-#{@ts}.example.com", @org.objid)

# Setup for the Network Validation section further down. Tryouts only executes
# bare code BEFORE the first `##` block, so capture-and-restore state must be
# established here (not mid-file between tests, which is silently ignored).
@original_truemail_validate = Truemail.method(:validate)

# Immutable mock shells matching the Truemail.validate -> .result.success
# call chain. Built once and reused so each test avoids re-allocating Structs.
TruemailMockResult    = Data.define(:success)
TruemailMockValidator = Data.define(:result)
TRUEMAIL_VALID_MOCK   = TruemailMockValidator.new(result: TruemailMockResult.new(success: true))
TRUEMAIL_INVALID_MOCK = TruemailMockValidator.new(result: TruemailMockResult.new(success: false))

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

# --- Corrupted JSON: display helpers fail open, the sign-up gate fails closed ---
#
# When allowed_signup_domains_json contains invalid JSON, allowed_signup_domains
# returns [] so config surfaces keep rendering, and valid_email_domain? reads
# that as "no allowlist". The sign-up gate must not inherit that reading: the
# operator chose domain_allowlist, so an unreadable or empty list denies every
# sign-up (allowed_signup_domains_corrupt?, validate_domain_allowlist) rather
# than silently admitting everyone. Same stance as SsoConfig on the SSO path.

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

## allowed_signup_domains_corrupt? is true for unreadable JSON
@corrupt_config.allowed_signup_domains_corrupt?
#=> true

## allowed_signup_domains_corrupt? is false for a readable list
@allowlist_config.allowed_signup_domains_corrupt?
#=> false

## allowed_signup_domains_corrupt? is false for the cleared (nil) state
@cfg_allowlist.allowed_signup_domains_corrupt?
#=> false

## allowed_signup_domains_corrupt? is true for well-formed JSON that is not an array
@corrupt_config.allowed_signup_domains_json = '{"acme.com": true}'
@corrupt_config.allowed_signup_domains_corrupt?
#=> true

## valid_signup_email? denies every address when the allowlist JSON is corrupted (fail-closed)
@corrupt_config.allowed_signup_domains_json = '{invalid json['
@corrupt_config.valid_signup_email?('anyone@anywhere.com')
#=> false

## valid_signup_email? denies the previously allowed domain too while the list is unreadable
@corrupt_config.valid_signup_email?('user@valid.com')
#=> false

## valid_signup_email? denies every address when domain_allowlist has no domains
@empty_allowlist = Onetime::CustomDomain::SignupConfig.new(
  domain_id: 'test_dummy_empty',
  validation_strategy: 'domain_allowlist',
)
@empty_allowlist.valid_signup_email?('anyone@anywhere.com')
#=> false

## valid_email_domain? alone still reads an empty list as unrestricted (display helper)
@empty_allowlist.valid_email_domain?('anyone@anywhere.com')
#=> true

# --- allow_base_domain: the domain's own registrable domain joins the allowlist ---
#
# secrets.corp.com → base_domain corp.com (PublicSuffix). With the flag set,
# @corp.com addresses sign up without corp.com being listed; the list stays
# for partners. The base domain is read from the CustomDomain record at
# validation time. Only the domain_allowlist gate consults it, and a missing
# base_domain adds nothing (fail closed) rather than falling back to allow-all.

## FIELD_SPECS declares allow_base_domain as a native boolean (colonel-writable)
Onetime::CustomDomain::SignupConfig::FIELD_SPECS['allow_base_domain']
#=> { type: :boolean, storage: :native }

## A new config defaults allow_base_domain to false (not nil)
@fresh_abd = Onetime::CustomDomain::SignupConfig.new(domain_id: 'abd_init')
[@fresh_abd.allow_base_domain, @fresh_abd.allow_base_domain?]
#=> [false, false]

## Setup: a tenant domain whose base_domain is example.com
@ts_abd     = Familia.now.to_i
@domain_abd = Onetime::CustomDomain.create!("sc-own-#{@ts_abd}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@domain_abd.base_domain
#=> 'example.com'

## create! with allow_base_domain and NO explicit list persists the flag
@abd_config = Onetime::CustomDomain::SignupConfig.create!(
  domain_id: @domain_abd.identifier,
  validation_strategy: 'domain_allowlist',
  allow_base_domain: true,
  enabled: true,
)
[@abd_config.allow_base_domain?, @abd_config.allowed_signup_domains]
#=> [true, []]

## The flag satisfies the domain_allowlist requirement (no validation error)
@abd_config.validation_errors
#=> []

## base_domain reads the owning domain's registrable domain
@abd_config.base_domain
#=> 'example.com'

## effective_allowed_signup_domains is the base domain alone when nothing is listed
@abd_config.effective_allowed_signup_domains
#=> ['example.com']

## The gate admits an address at the base domain
@abd_config.valid_signup_email?('user@example.com')
#=> true

## ...case-insensitively
@abd_config.valid_signup_email?('USER@Example.COM')
#=> true

## The gate refuses other domains
@abd_config.valid_signup_email?('user@other.com')
#=> false

## A subdomain of the base domain is not admitted by the flag (exact match, like a listed entry)
@abd_config.valid_signup_email?("user@#{@domain_abd.display_domain}")
#=> false

## Listed partners combine with the base domain, de-duplicated
@abd_config.allowed_signup_domains = ['partner.com', 'example.com']
@abd_config.effective_allowed_signup_domains.sort
#=> ['example.com', 'partner.com']

## Both the listed partner and the base domain are admitted
[@abd_config.valid_signup_email?('a@partner.com'), @abd_config.valid_signup_email?('b@example.com')]
#=> [true, true]

## With the flag off, only the list counts
@abd_config.allowed_signup_domains = ['partner.com']
@abd_config.allow_base_domain      = false
[@abd_config.effective_allowed_signup_domains, @abd_config.valid_signup_email?('b@example.com')]
#=> [['partner.com'], false]

## Flag off with an empty list is still the invalid configuration it always was
@abd_config.allowed_signup_domains = []
@abd_config.validation_errors.any? { |e| e.include?('allowed_signup_domains') }
#=> true

## The flag round-trips through save/load as a real boolean
@abd_config.allow_base_domain = true
@abd_config.save
Onetime::CustomDomain::SignupConfig.find_by_domain_id(@domain_abd.identifier).allow_base_domain?
#=> true

## A corrupt list still denies everyone, flag or not (nothing stored is trusted)
@abd_config.allowed_signup_domains_json = '{invalid json['
@abd_config.valid_signup_email?('user@example.com')
#=> false

## ...and validation_errors agrees: the flag cannot satisfy an unreadable list
errors = @abd_config.validation_errors
[
  @abd_config.allow_base_domain?,
  errors.include?(Onetime::CustomDomain::SignupConfig::ALLOWLIST_UNREADABLE_ERROR),
  errors.include?(Onetime::CustomDomain::SignupConfig::ALLOWLIST_REQUIRED_ERROR),
]
#=> [true, true, false]

## An unreadable list is not an error under a strategy that ignores the list
@abd_config.validation_strategy = 'mx'
result = @abd_config.validation_errors
@abd_config.validation_strategy = 'domain_allowlist'
result
#=> []

## Without a domain record there is no base domain: the flag adds nothing and the gate denies
@abd_orphan = Onetime::CustomDomain::SignupConfig.new(
  domain_id: 'abd_no_such_domain',
  validation_strategy: 'domain_allowlist',
  allow_base_domain: true,
)
[@abd_orphan.base_domain, @abd_orphan.effective_allowed_signup_domains, @abd_orphan.valid_signup_email?('user@example.com')]
#=> [nil, [], false]

## ...and validation_errors agrees with the gate: the flag cannot satisfy the list requirement
@abd_orphan.validation_errors.include?(Onetime::CustomDomain::SignupConfig::ALLOWLIST_REQUIRED_ERROR)
#=> true

## allowlist_requirement_met?: a listed domain satisfies domain_allowlist
Onetime::CustomDomain::SignupConfig.allowlist_requirement_met?(
  strategy: 'domain_allowlist', domains: ['partner.com'], allow_base_domain: false, base_domain: nil,
)
#=> true

## allowlist_requirement_met?: the flag counts only with a base domain to derive
[
  Onetime::CustomDomain::SignupConfig.allowlist_requirement_met?(
    strategy: 'domain_allowlist', domains: [], allow_base_domain: true, base_domain: 'example.com',
  ),
  Onetime::CustomDomain::SignupConfig.allowlist_requirement_met?(
    strategy: 'domain_allowlist', domains: [], allow_base_domain: true, base_domain: nil,
  ),
  Onetime::CustomDomain::SignupConfig.allowlist_requirement_met?(
    strategy: 'domain_allowlist', domains: nil, allow_base_domain: true, base_domain: '  ',
  ),
]
#=> [true, false, false]

## allowlist_requirement_met?: an empty list without the flag fails
Onetime::CustomDomain::SignupConfig.allowlist_requirement_met?(
  strategy: 'domain_allowlist', domains: [], allow_base_domain: false, base_domain: 'example.com',
)
#=> false

## allowlist_requirement_met?: strategies without an allowlist always pass
%w[passthrough mx smtp].map do |strategy|
  Onetime::CustomDomain::SignupConfig.allowlist_requirement_met?(
    strategy: strategy, domains: [], allow_base_domain: false, base_domain: nil,
  )
end
#=> [true, true, true]

## passthrough ignores the flag (format-only, as before)
@abd_orphan.validation_strategy = 'passthrough'
@abd_orphan.valid_signup_email?('anyone@anywhere.com')
#=> true

# --- Network Validation Strategy Tests (mx / smtp) ---
#
# These tests use Truemail stubbing to exercise the :mx and :smtp validation
# strategies without making real DNS / SMTP network calls. Coverage:
#   - Success path: Truemail validates -> valid_signup_email? returns true
#   - Failure path: Truemail rejects  -> valid_signup_email? returns false
#   - Early return: format check rejects malformed input before Truemail runs
#   - Rescue path:  Truemail raises   -> falls back to format-only validation
#   - build_truemail_config: copies global settings, sets requested type
#   - Truemail is invoked with custom_configuration: kwarg (not with:)
#
# Note: @original_truemail_validate, TRUEMAIL_VALID_MOCK, and TRUEMAIL_INVALID_MOCK
# are defined in the file's top-level setup (before the first `##` block).
# Tryouts only runs bare code before the first test marker.

## Setup: create a CustomDomain and SignupConfig for mx strategy
@ts_mx     = Familia.now.to_i
@domain_mx = Onetime::CustomDomain.create!("sc-mx-#{@ts_mx}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@mx_config = Onetime::CustomDomain::SignupConfig.create!(
  domain_id: @domain_mx.identifier,
  validation_strategy: 'mx',
  enabled: true,
)
@mx_config.validation_strategy
#=> 'mx'

## Setup: create a CustomDomain and SignupConfig for smtp strategy
@ts_smtp     = Familia.now.to_i
@domain_smtp = Onetime::CustomDomain.create!("sc-smtp-#{@ts_smtp}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@smtp_config = Onetime::CustomDomain::SignupConfig.create!(
  domain_id: @domain_smtp.identifier,
  validation_strategy: 'smtp',
  enabled: true,
)
@smtp_config.validation_strategy
#=> 'smtp'

# --- build_truemail_config (private helper) ---

## build_truemail_config returns a Truemail::Configuration instance
@mx_config.send(:build_truemail_config, validation_type: :mx).is_a?(Truemail::Configuration)
#=> true

## build_truemail_config sets default_validation_type to :mx
@mx_config.send(:build_truemail_config, validation_type: :mx).default_validation_type
#=> :mx

## build_truemail_config sets default_validation_type to :smtp
@mx_config.send(:build_truemail_config, validation_type: :smtp).default_validation_type
#=> :smtp

## build_truemail_config copies verifier_email from the global Truemail config
@mx_config.send(:build_truemail_config, validation_type: :mx).verifier_email == Truemail.configuration.verifier_email
#=> true

## build_truemail_config copies verifier_domain from the global Truemail config
@mx_config.send(:build_truemail_config, validation_type: :mx).verifier_domain == Truemail.configuration.verifier_domain
#=> true

## build_truemail_config copies connection_timeout from the global Truemail config
@mx_config.send(:build_truemail_config, validation_type: :mx).connection_timeout == Truemail.configuration.connection_timeout
#=> true

## build_truemail_config copies response_timeout from the global Truemail config
@mx_config.send(:build_truemail_config, validation_type: :mx).response_timeout == Truemail.configuration.response_timeout
#=> true

# --- mx strategy: success / failure / fallback paths ---

## mx strategy returns true when Truemail validates successfully
Truemail.define_singleton_method(:validate) do |_email, **_kwargs|
  TRUEMAIL_VALID_MOCK
end
@mx_config.valid_signup_email?('user@example.com')
#=> true

## mx strategy returns false when Truemail rejects the email
Truemail.define_singleton_method(:validate) do |_email, **_kwargs|
  TRUEMAIL_INVALID_MOCK
end
@mx_config.valid_signup_email?('user@example.com')
#=> false

## mx strategy rejects malformed email before invoking Truemail
Truemail.define_singleton_method(:validate) do |_email, **_kwargs|
  raise 'Truemail.validate should not be called for malformed input'
end
@mx_config.valid_signup_email?('not-an-email')
#=> false

## mx strategy falls back to format-only validation when Truemail raises (valid format passes)
Truemail.define_singleton_method(:validate) do |_email, **_kwargs|
  raise StandardError, 'DNS timeout'
end
@mx_config.valid_signup_email?('user@example.com')
#=> true

## mx strategy rejects malformed email when Truemail raises (format check runs before Truemail)
Truemail.define_singleton_method(:validate) do |_email, **_kwargs|
  raise StandardError, 'DNS timeout'
end
@mx_config.valid_signup_email?('not-an-email')
#=> false

# --- smtp strategy: success / failure / fallback paths ---

## smtp strategy returns true when Truemail validates successfully
Truemail.define_singleton_method(:validate) do |_email, **_kwargs|
  TRUEMAIL_VALID_MOCK
end
@smtp_config.valid_signup_email?('user@example.com')
#=> true

## smtp strategy returns false when Truemail rejects the email
Truemail.define_singleton_method(:validate) do |_email, **_kwargs|
  TRUEMAIL_INVALID_MOCK
end
@smtp_config.valid_signup_email?('user@example.com')
#=> false

## smtp strategy rejects malformed email before invoking Truemail
Truemail.define_singleton_method(:validate) do |_email, **_kwargs|
  raise 'Truemail.validate should not be called for malformed input'
end
@smtp_config.valid_signup_email?('not-an-email')
#=> false

## smtp strategy falls back to format-only validation when Truemail raises (valid format passes)
Truemail.define_singleton_method(:validate) do |_email, **_kwargs|
  raise StandardError, 'SMTP connection refused'
end
@smtp_config.valid_signup_email?('user@example.com')
#=> true

## smtp strategy rejects malformed email when Truemail raises (format check runs before Truemail)
Truemail.define_singleton_method(:validate) do |_email, **_kwargs|
  raise StandardError, 'SMTP connection refused'
end
@smtp_config.valid_signup_email?('not-an-email')
#=> false

# --- Verify Truemail.validate is invoked with custom_configuration kwarg ---
#
# The implementation must use custom_configuration: (per-call override) rather
# than with: (which would require mutating the global Truemail config).

## mx strategy invokes Truemail.validate with custom_configuration kwarg
captured = {}
Truemail.define_singleton_method(:validate) do |_email, **kwargs|
  captured[:kwargs] = kwargs
  TRUEMAIL_VALID_MOCK
end
@mx_config.valid_signup_email?('user@example.com')
captured[:kwargs].key?(:custom_configuration)
#=> true

## mx strategy's custom_configuration has default_validation_type=:mx
captured = {}
Truemail.define_singleton_method(:validate) do |_email, **kwargs|
  captured[:kwargs] = kwargs
  TRUEMAIL_VALID_MOCK
end
@mx_config.valid_signup_email?('user@example.com')
captured[:kwargs][:custom_configuration].default_validation_type
#=> :mx

## smtp strategy's custom_configuration has default_validation_type=:smtp
captured = {}
Truemail.define_singleton_method(:validate) do |_email, **kwargs|
  captured[:kwargs] = kwargs
  TRUEMAIL_VALID_MOCK
end
@smtp_config.valid_signup_email?('user@example.com')
captured[:kwargs][:custom_configuration].default_validation_type
#=> :smtp

## Truemail.validate receives the email argument unchanged
captured = {}
Truemail.define_singleton_method(:validate) do |email, **_kwargs|
  captured[:email] = email
  TRUEMAIL_VALID_MOCK
end
@mx_config.valid_signup_email?('user@example.com')
captured[:email]
#=> 'user@example.com'

## Restore the original Truemail.validate so subsequent code uses the real method
Truemail.define_singleton_method(:validate, @original_truemail_validate)
true
#=> true

# --- Cleanup ---

Familia.dbclient.flushdb
OT.info "Cleaned Redis after SignupConfig test run"
