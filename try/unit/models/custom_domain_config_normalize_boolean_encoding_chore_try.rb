# try/unit/models/custom_domain_config_normalize_boolean_encoding_chore_try.rb
#
# frozen_string_literal: true

# Tests for the :normalize_boolean_encoding housekeeping chore (#3951),
# registered on all seven CustomDomain config models by
# lib/onetime/models/custom_domain/chores/normalize_boolean_encoding.rb.
#
# The chore compares each spec'd boolean field's RAW stored bytes against
# the model's declared storage encoding (FIELD_SPECS) and rewrites
# recognized drift via the fast writer:
#
#   :native canonical -> 'true'/'false'       (JSON booleans)
#   :string canonical -> '"true"'/'"false"'   (JSON-quoted strings)
#
# Covered here:
#   - canonical bytes            -> silent skip, chore returns false
#   - string-encoded on :native  -> rewritten to native bytes, returns true
#   - native-encoded on :string  -> rewritten to quoted bytes, returns true
#   - 1/'1' numeric variants     -> rewritten to encoded true
#   - unrecognized garbage       -> left byte-for-byte, returns false
#   - absent field               -> skipped, never materialized
#   - idempotence                -> second run is a no-op
#   - registration               -> all seven models expose the chore
#
# Run:
#   try try/unit/models/custom_domain_config_normalize_boolean_encoding_chore_try.rb --agent

require_relative '../../support/test_models'

OT.boot! :test

Familia.dbclient.flushdb
OT.info 'Cleaned Redis for normalize_boolean_encoding chore test run'

CHORE = :normalize_boolean_encoding

# Raw hash bytes for a field, straight from Redis.
def raw(obj, field)
  Familia.dbclient.hget(obj.dbkey, field)
end

# Force specific raw bytes into the stored hash, bypassing all setters.
def force_raw(obj, field, bytes)
  Familia.dbclient.hset(obj.dbkey, field, bytes)
end

@ts      = Familia.now.to_i
@entropy = SecureRandom.hex(4)
@owner   = Onetime::Customer.create!(email: "chore_owner_#{@ts}_#{@entropy}@test.com")
@org     = Onetime::Organization.create!("Chore Test Org #{@ts}", @owner, "chore_#{@ts}@test.com")

# CustomDomain.create! bootstraps HomepageConfig + ApiConfig (disabled).
@domain = Onetime::CustomDomain.create!("chore-#{@ts}-#{@entropy}.example.com", @org.objid)
@did    = @domain.identifier

@signin = Onetime::CustomDomain::SigninConfig.create!(domain_id: @did) # :native booleans
@api    = Onetime::CustomDomain::ApiConfig.find_by_domain_id(@did)    # enabled :string

## All seven config models register the chore
Onetime::CustomDomain::ConfigRegistry::KINDS.values.map do |entry|
  entry[:model].chores.key?(CHORE)
end.uniq
#=> [true]

# --- Branch (a): canonical bytes -> silent skip ---

## SigninConfig create! saved native booleans; canonical bytes untouched,
## chore reports no modification
@signin.enabled = true
@signin.save
[@signin.do_chore!(CHORE), raw(@signin, 'enabled')]
#=> [false, 'true']

## ApiConfig enabled (:string) canonical quoted bytes -> skip
@api.enabled = true
@api.save
[@api.do_chore!(CHORE), raw(@api, 'enabled')]
#=> [false, '"true"']

# --- Branch (b): recognized divergent encoding -> rewrite ---

## String-encoded bytes on a :native field are rewritten to native bytes
## and the tolerant predicate still reads true after reload
force_raw(@signin, 'signin_enabled', '"true"')
@result = @signin.do_chore!(CHORE)
@signin.refresh!
[@result, raw(@signin, 'signin_enabled'), @signin.signin_enabled?]
#=> [true, 'true', true]

## Native-encoded bytes on a :string field are rewritten to quoted bytes
force_raw(@api, 'enabled', 'false')
[@api.do_chore!(CHORE), raw(@api, 'enabled')]
#=> [true, '"false"']

## Numeric truthy variant '1' on a :native field normalizes to native true
force_raw(@signin, 'sso_enabled', '1')
[@signin.do_chore!(CHORE), raw(@signin, 'sso_enabled')]
#=> [true, 'true']

## Quoted numeric variant '"1"' on a :string field normalizes to quoted true
force_raw(@api, 'enabled', '"1"')
[@api.do_chore!(CHORE), raw(@api, 'enabled')]
#=> [true, '"true"']

# --- Branch (c): unrecognized garbage -> log + leave alone ---

## Garbage bytes are preserved byte-for-byte (forensic evidence); the
## tolerant predicate reads them as false; chore reports no modification
force_raw(@signin, 'email_auth_enabled', '"banana"')
@garbage_result = @signin.do_chore!(CHORE)
@signin.refresh!
[@garbage_result, raw(@signin, 'email_auth_enabled'), @signin.email_auth_enabled?]
#=> [false, '"banana"', false]

# --- nil/absent fields: skipped, never materialized ---

## Deleting a field from the raw hash leaves it absent after the chore
Familia.dbclient.hdel(@signin.dbkey, 'sso_enabled')
[@signin.do_chore!(CHORE), raw(@signin, 'sso_enabled')]
#=> [false, nil]

# --- Idempotence: second run after a fix is a no-op ---

## Re-running after a rewrite finds only canonical bytes (garbage aside)
force_raw(@api, 'enabled', 'true')
@first  = @api.do_chore!(CHORE)
@second = @api.do_chore!(CHORE)
[@first, @second, raw(@api, 'enabled')]
#=> [true, false, '"true"']

# Teardown
@signin.destroy!
@domain.destroy!
@org.destroy!
@owner.destroy!
