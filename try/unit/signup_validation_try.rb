# try/unit/signup_validation_try.rb
#
# frozen_string_literal: true

# Integration tests for Onetime::SignupValidation module
#
# Covers:
#   - Global config fallback when no display_domain provided
#   - Per-domain SignupConfig resolution when display_domain provided
#   - Fallback to global when SignupConfig is disabled
#   - Fallback to global when SignupConfig doesn't exist
#
# Run:
#   try try/unit/signup_validation_try.rb --agent

require_relative '../support/test_models'

OT.boot! :test

Familia.dbclient.flushdb
OT.info "Cleaned Redis for SignupValidation test run"

@ts = Familia.now.to_i
@entropy = SecureRandom.hex(4)
@owner = Onetime::Customer.create!(email: "sv_owner_#{@ts}_#{@entropy}@test.com")
@org = Onetime::Organization.create!("SV Test Org #{@ts}", @owner, "sv_#{@ts}@test.com")
@display_domain = "sv-test-#{@ts}-#{@entropy}.example.com"
@domain = Onetime::CustomDomain.create!(@display_domain, @org.objid)

# Stash original config to restore later
@original_allowed = OT.conf.dig('site', 'authentication', 'allowed_signup_domains')

# --- Global Config Fallback ---

## When no display_domain provided, uses global config
OT.conf['site'] ||= {}
OT.conf['site']['authentication'] ||= {}
OT.conf['site']['authentication']['allowed_signup_domains'] = nil
Onetime::SignupValidation.valid_signup_email?('user@anywhere.com')
#=> true

## Global config with restrictions allows matching domain
OT.conf['site']['authentication']['allowed_signup_domains'] = ['allowed.com']
Onetime::SignupValidation.valid_signup_email?('user@allowed.com')
#=> true

## Global config with restrictions rejects non-matching domain
Onetime::SignupValidation.valid_signup_email?('user@evil.com')
#=> false

## Empty allowed_signup_domains allows any email
OT.conf['site']['authentication']['allowed_signup_domains'] = []
Onetime::SignupValidation.valid_signup_email?('user@anywhere.com')
#=> true

# --- Per-Domain Resolution ---

## Create a SignupConfig and verify it persists
Onetime::CustomDomain::SignupConfig.create!(
  domain_id: @domain.identifier,
  validation_strategy: 'domain_allowlist',
  allowed_signup_domains: ['tenant.com'],
  enabled: true,
)
Onetime::CustomDomain::SignupConfig.exists_for_domain?(@domain.identifier)
#=> true

## Restore global config restriction (verifies per-domain takes precedence)
OT.conf['site']['authentication']['allowed_signup_domains'] = ['globally-allowed.com']
OT.conf.dig('site', 'authentication', 'allowed_signup_domains')
#=> ['globally-allowed.com']

## Per-domain config rejects emails not in its allowlist
Onetime::SignupValidation.valid_signup_email?('user@globally-allowed.com', display_domain: @display_domain)
#=> false

## Per-domain config accepts emails in its allowlist
Onetime::SignupValidation.valid_signup_email?('user@tenant.com', display_domain: @display_domain)
#=> true

# --- Disabled SignupConfig Falls Back to Global ---

## When SignupConfig is disabled, falls back to global config
cfg = Onetime::CustomDomain::SignupConfig.find_by_domain_id(@domain.identifier)
cfg.disable!
Onetime::SignupValidation.valid_signup_email?('user@globally-allowed.com', display_domain: @display_domain)
#=> true

## Disabled config does not block via its own allowlist
Onetime::SignupValidation.valid_signup_email?('user@tenant.com', display_domain: @display_domain)
#=> false

# --- Nonexistent Domain Falls Back to Global ---

## Unknown display_domain falls back to global config
Onetime::SignupValidation.valid_signup_email?('user@globally-allowed.com', display_domain: 'nonexistent.example.com')
#=> true

# --- resolve_signup_config Helper ---

## resolve_signup_config returns nil when disabled
Onetime::SignupValidation.resolve_signup_config(@display_domain)
#=> nil

## resolve_signup_config returns config when enabled
cfg2 = Onetime::CustomDomain::SignupConfig.find_by_domain_id(@domain.identifier)
cfg2.enable!
result = Onetime::SignupValidation.resolve_signup_config(@display_domain)
result.is_a?(Onetime::CustomDomain::SignupConfig)
#=> true

## resolve_signup_config returns nil for nonexistent domain
Onetime::SignupValidation.resolve_signup_config('nonexistent.example.com')
#=> nil

## resolve_signup_config returns nil for nil display_domain
Onetime::SignupValidation.resolve_signup_config(nil)
#=> nil

# --- structurally_valid_email? mirrors the accounts.valid_email CHECK (#3971) ---
#
# constraint :valid_email, email: /^[^,;@ \r\n]+@[^,@; \r\n]+\.[^,@; \r\n]+$/
# (apps/web/auth/migrations/001_initial.rb). Every shape below that the CHECK
# rejects but a naive `email.split('@').length == 2` guard accepts previously
# reached the INSERT and raised Sequel::CheckConstraintViolation -> 500 on the
# SSO callback (the frozen-loading-screen failure #3478 exists to prevent).

## A normal email is structurally valid
Onetime::SignupValidation.structurally_valid_email?('alice@contoso.com')
#=> true

## An internal space in the local part is rejected (PG CHECK rejects it too)
Onetime::SignupValidation.structurally_valid_email?('al ice@contoso.com')
#=> false

## A comma in the local part is rejected
Onetime::SignupValidation.structurally_valid_email?('al,ice@contoso.com')
#=> false

## A semicolon in the domain is rejected
Onetime::SignupValidation.structurally_valid_email?('alice@cont;oso.com')
#=> false

## A dotless domain is rejected (plausible from internal AD FS / OIDC issuers)
Onetime::SignupValidation.structurally_valid_email?('alice@contoso')
#=> false

## An empty claim is rejected
Onetime::SignupValidation.structurally_valid_email?('')
#=> false

## A claim with no '@' is rejected
Onetime::SignupValidation.structurally_valid_email?('alice.contoso.com')
#=> false

## A blank local part (leading '@') is rejected
Onetime::SignupValidation.structurally_valid_email?('@contoso.com')
#=> false

## \A/\z anchoring rejects an embedded newline that ^/$ would let through
## ("ok@example.com\nbad" would pass a ^/$-anchored guard here and still be
## rejected by PG, whose ^/$ are string anchors -- reintroducing the 500)
Onetime::SignupValidation.structurally_valid_email?("ok@example.com\nbad")
#=> false

# --- Cleanup ---

OT.conf['site']['authentication']['allowed_signup_domains'] = @original_allowed
Familia.dbclient.flushdb
OT.info "Cleaned Redis after SignupValidation test run"
