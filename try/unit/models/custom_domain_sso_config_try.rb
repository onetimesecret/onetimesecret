# try/unit/models/custom_domain_sso_config_try.rb
#
# frozen_string_literal: true

# Unit tests for CustomDomain::SsoConfig boolean handling (#3951).
#
# SsoConfig declares three boolean fields, all storage :string
# ('true'/'false'): enabled, enforce_sso_only, grant_org_scope. The
# boolean_encoding feature gives each a tolerant predicate (accepts
# true/'true'/1/'1') and a normalizing setter (any truthy input persists the
# STRING 'true'; any non-nil falsy input persists 'false'; nil passes
# through). Pre-#3951 these fields had strict to_s == 'true' predicates and
# raw setters, so `cfg.enabled = true` persisted a real boolean that other
# strict readers could misread.
#
# Covers:
#   - init defaults: all three fields default to string 'false'
#   - The three predicates under BOTH encodings (string and boolean input)
#   - Normalizing setter: `cfg.enabled = true` now persists the string 'true'
#     (raw hash bytes are the JSON-quoted '"true"')
#   - Read tolerance for values planted around the setter (legacy in-memory)
#   - create! path still works (encrypted credentials + enabled: true)
#   - enable!/disable! helpers and round-trip through save/load
#
# Run:
#   try try/unit/models/custom_domain_sso_config_try.rb --agent

require_relative '../../support/test_models'

OT.boot! :test

Familia.dbclient.flushdb
OT.info "Cleaned Redis for SsoConfig test run"

# Familia encryption config required by SsoConfig encrypted fields
@key_v1 = 'test_encryption_key_32bytes_ok!!'
@key_v2 = 'another_test_key_for_testing_!!'

# Tryouts share a single process, so global Familia config set here leaks
# into every file that runs after this one. Capture originals for teardown.
@original_encryption_keys = Familia.config.encryption_keys
@original_key_version = Familia.config.current_key_version
@original_personalization = Familia.config.encryption_personalization

Familia.configure do |config|
  config.encryption_keys = {
    v1: Base64.strict_encode64(@key_v1),
    v2: Base64.strict_encode64(@key_v2),
  }
  config.current_key_version = :v1
  config.encryption_personalization = 'SsoConfigTest'
end

@ts = Familia.now.to_i
@entropy = SecureRandom.hex(4)

@owner = Onetime::Customer.create!(email: "sso_owner_#{@ts}_#{@entropy}@test.com")
@org = Onetime::Organization.create!("SSO Test Org #{@ts}", @owner, "sso_#{@ts}@test.com")
@domain = Onetime::CustomDomain.create!("sso-test-#{@ts}-#{@entropy}.example.com", @org.objid)

# --- init defaults ---

## New SsoConfig defaults enabled to string 'false'
@fresh = Onetime::CustomDomain::SsoConfig.new(domain_id: 'init_test_1')
@fresh.enabled
#=> 'false'

## New SsoConfig defaults enforce_sso_only to string 'false'
@fresh.enforce_sso_only
#=> 'false'

## New SsoConfig defaults grant_org_scope to string 'false'
@fresh.grant_org_scope
#=> 'false'

## All three predicates read false on a fresh config
[@fresh.enabled?, @fresh.enforce_sso_only?, @fresh.grant_org_scope?]
#=> [false, false, false]

# --- Predicates under the STRING encoding (declared storage) ---

## enabled? reads true for string 'true'
@str = Onetime::CustomDomain::SsoConfig.new(domain_id: 'pred_str_1')
@str.enabled = 'true'
@str.enabled?
#=> true

## enabled? reads false for string 'false'
@str.enabled = 'false'
@str.enabled?
#=> false

## enforce_sso_only? reads true for string 'true'
@str.enforce_sso_only = 'true'
@str.enforce_sso_only?
#=> true

## enforce_sso_only? reads false for string 'false'
@str.enforce_sso_only = 'false'
@str.enforce_sso_only?
#=> false

## grant_org_scope? reads true for string 'true'
@str.grant_org_scope = 'true'
@str.grant_org_scope?
#=> true

## grant_org_scope? reads false for string 'false'
@str.grant_org_scope = 'false'
@str.grant_org_scope?
#=> false

# --- Predicates under the BOOLEAN encoding (#3951 tolerance) ---
# Real booleans arrive from console assignments and pre-#3951 callers.
# The normalizing setter encodes them to strings, so the predicate reads
# them correctly no matter which encoding the caller used.

## enabled? reads true when assigned boolean true
@bool = Onetime::CustomDomain::SsoConfig.new(domain_id: 'pred_bool_1')
@bool.enabled = true
@bool.enabled?
#=> true

## enabled = true normalizes the in-memory value to the string 'true'
@bool.enabled
#=> 'true'

## enabled? reads false when assigned boolean false
@bool.enabled = false
@bool.enabled?
#=> false

## enforce_sso_only? reads true when assigned boolean true
@bool.enforce_sso_only = true
[@bool.enforce_sso_only?, @bool.enforce_sso_only]
#=> [true, 'true']

## grant_org_scope? reads true when assigned boolean true
@bool.grant_org_scope = true
[@bool.grant_org_scope?, @bool.grant_org_scope]
#=> [true, 'true']

## Read tolerance without the setter: a boolean planted directly in the ivar
## (legacy record loaded before #3951, or a writer bypassing the accessor)
## still reads enabled
@planted = Onetime::CustomDomain::SsoConfig.new(domain_id: 'pred_planted_1')
@planted.instance_variable_set(:@enabled, true)
@planted.enabled?
#=> true

## nil passes through the setter unchanged and reads false (conservative)
@bool.enabled = nil
[@bool.enabled.nil?, @bool.enabled?]
#=> [true, false]

# --- Normalizing setter persists the STRING encoding ---

## 'cfg.enabled = true' now persists the string 'true': the raw hash value is
## the JSON-quoted string '"true"', NOT the unquoted boolean bytes 'true'
@persist = Onetime::CustomDomain::SsoConfig.new(domain_id: @domain.identifier)
@persist.enabled = true
@persist.save
Familia.dbclient.hget(@persist.dbkey, 'enabled')
#=> '"true"'

## Reloading the persisted record reads enabled? true
Onetime::CustomDomain::SsoConfig.find_by_domain_id(@domain.identifier).enabled?
#=> true

## Boolean assignments to the other two fields persist strings the same way
@persist.enforce_sso_only = true
@persist.grant_org_scope = true
@persist.save
[
  Familia.dbclient.hget(@persist.dbkey, 'enforce_sso_only'),
  Familia.dbclient.hget(@persist.dbkey, 'grant_org_scope'),
]
#=> ['"true"', '"true"']

## Round-trip: reloaded record reads all three predicates true
@reloaded = Onetime::CustomDomain::SsoConfig.find_by_domain_id(@domain.identifier)
[@reloaded.enabled?, @reloaded.enforce_sso_only?, @reloaded.grant_org_scope?]
#=> [true, true, true]

# --- create! path ---

## create! with encrypted credentials and enabled: true still works
## (destroy the ad-hoc record first so create! can claim the domain, 1:1 keying)
@persist.destroy!
@created = Onetime::CustomDomain::SsoConfig.create!(
  domain_id: @domain.identifier,
  provider_type: 'oidc',
  client_id: "client-#{@entropy}",
  client_secret: "secret-#{@entropy}",
  issuer: 'https://auth.example.com',
  display_name: 'SSO Boolean Test',
  enabled: true,
)
@created.class
#=> Onetime::CustomDomain::SsoConfig

## create! enabled: true reads enabled? (create! does .to_s, the normalizing
## setter keeps it the string 'true')
@created.enabled?
#=> true

## create! persisted the string encoding for enabled
Familia.dbclient.hget(@created.dbkey, 'enabled')
#=> '"true"'

## create! defaults the enforcement fields to 'false' / predicates false
[@created.enforce_sso_only?, @created.grant_org_scope?]
#=> [false, false]

## create! round-trips through the finder with predicates intact
@found = Onetime::CustomDomain::SsoConfig.find_by_domain_id(@domain.identifier)
[@found.enabled?, @found.provider_type]
#=> [true, 'oidc']

## Encrypted credential survives (create! path unaffected by the feature)
@found.client_id.reveal { it }
#=> "client-#{@entropy}"

# --- enable!/disable! helpers ---

## disable! persists string 'false' and reads disabled
@found.disable!
[@found.enabled?, Familia.dbclient.hget(@found.dbkey, 'enabled')]
#=> [false, '"false"']

## enable! persists string 'true' and reads enabled
@found.enable!
[@found.enabled?, Familia.dbclient.hget(@found.dbkey, 'enabled')]
#=> [true, '"true"']

# Teardown
Familia.dbclient.flushdb

# Restore original Familia encryption config to avoid polluting other test files
Familia.configure do |config|
  config.encryption_keys = @original_encryption_keys if @original_encryption_keys
  config.current_key_version = @original_key_version if @original_key_version
  config.encryption_personalization = @original_personalization if @original_personalization
end
