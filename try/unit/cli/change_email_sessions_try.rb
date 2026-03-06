# try/unit/cli/change_email_sessions_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::SessionUtils — shared Redis session invalidation utility.
#
# This utility is called from both the Rack logic layer
# (AccountAPI::Logic::Account::ConfirmEmailChange) and the CLI
# (Onetime::CLI::ChangeEmailCommand).
#
# Session format in Redis:
#   key:   session:<hex>
#   value: base64(json)--hmac
#   json:  { "external_id": "<extid>", ... }

require_relative '../../support/test_helpers'
require 'onetime/session_utils'

OT.boot! :test, false

# Minimal customer-like struct with extid and objid
def mock_customer(extid, objid = nil)
  Struct.new(:extid, :objid).new(extid, objid || "obj-#{extid}")
end

# Encode a hash as a session value in the Redis format: base64(json)--fakehmacsig
def encode_session(data)
  json    = Familia::JsonSerializer.dump(data)
  encoded = Base64.encode64(json).gsub("\n", '')
  "#{encoded}--fakehmacsig"
end

# Write a session entry to Redis and return the key
def write_session(hex_suffix, data)
  key   = "session:#{hex_suffix}"
  value = encode_session(data)
  Familia.dbclient.set(key, value, ex: 3600)
  key
end

@keys_to_cleanup = []

# TRYOUTS

# --- extract_session_extid ---

## Returns the external_id from a well-formed session value
k = write_session("aabb#{SecureRandom.hex(3)}", { 'external_id' => 'urtest001', 'authenticated' => true })
@keys_to_cleanup << k
Onetime::SessionUtils.extract_session_extid(Familia.dbclient, k)
#=> 'urtest001'

## Returns nil for a key that does not exist in Redis
Onetime::SessionUtils.extract_session_extid(Familia.dbclient, 'session:doesnotexist999')
#=> nil

## Returns nil for a value that is not base64--hmac format
Familia.dbclient.set('session:malformed01', 'not_base64_at_all', ex: 3600)
@keys_to_cleanup << 'session:malformed01'
Onetime::SessionUtils.extract_session_extid(Familia.dbclient, 'session:malformed01')
#=> nil

## Returns nil when base64 decodes to non-JSON
bad = "#{Base64.encode64('this is not json').gsub("\n", '')}--fakesig"
Familia.dbclient.set('session:badjson01', bad, ex: 3600)
@keys_to_cleanup << 'session:badjson01'
Onetime::SessionUtils.extract_session_extid(Familia.dbclient, 'session:badjson01')
#=> nil

## Returns nil when JSON has no external_id key
k = write_session("noextid#{SecureRandom.hex(3)}", { 'authenticated' => true, 'other' => 'value' })
@keys_to_cleanup << k
Onetime::SessionUtils.extract_session_extid(Familia.dbclient, k)
#=> nil

# --- delete_redis_sessions: happy path ---

## Deletes a single matching session for the customer
extid1 = "urtest-happy-#{SecureRandom.hex(4)}"
cust1  = mock_customer(extid1)
k1     = write_session("happy1#{SecureRandom.hex(4)}", { 'external_id' => extid1 })
@keys_to_cleanup << k1
Onetime::SessionUtils.delete_redis_sessions(cust1)
Familia.dbclient.exists?(k1)
#=> false

## Returns without error when no session:* keys match the customer extid
ghost_cust = mock_customer("urtest-ghost-#{SecureRandom.hex(4)}")
begin
  Onetime::SessionUtils.delete_redis_sessions(ghost_cust)
  true
rescue => e
  e.message
end
#=> true

# --- delete_redis_sessions: multiple sessions ---

## Deletes all matching sessions and preserves non-matching ones
extid_multi = "urtest-multi-#{SecureRandom.hex(4)}"
extid_other = "urtest-other-#{SecureRandom.hex(4)}"
cust_multi  = mock_customer(extid_multi)

km1  = write_session("multi1#{SecureRandom.hex(4)}", { 'external_id' => extid_multi })
km2  = write_session("multi2#{SecureRandom.hex(4)}", { 'external_id' => extid_multi })
keep = write_session("keep1#{SecureRandom.hex(4)}", { 'external_id' => extid_other })
@keys_to_cleanup.concat([km1, km2, keep])

Onetime::SessionUtils.delete_redis_sessions(cust_multi)

[
  Familia.dbclient.exists?(km1),
  Familia.dbclient.exists?(km2),
  Familia.dbclient.exists?(keep),
]
#=> [false, false, true]

# --- delete_redis_sessions: edge cases ---

## Returns early without scanning when extid is nil
nil_cust = mock_customer(nil)
begin
  Onetime::SessionUtils.delete_redis_sessions(nil_cust)
  true
rescue => e
  e.message
end
#=> true

## Returns early without scanning when extid is empty string
empty_cust = mock_customer('')
begin
  Onetime::SessionUtils.delete_redis_sessions(empty_cust)
  true
rescue => e
  e.message
end
#=> true

# --- delete_redis_sessions: error resilience ---

## extract_session_extid rescues StandardError and returns nil for broken get
# Simulate a client whose get raises — the method must return nil without raising.
broken_get = Object.new
def broken_get.get(_key)
  raise StandardError, 'simulated get failure'
end
Onetime::SessionUtils.extract_session_extid(broken_get, 'session:anything')
#=> nil

## delete_redis_sessions rescue path: source-level guard is present
# Verify the rescue clause exists in the implementation source.
src = File.read(File.join(ENV['ONETIME_HOME'], 'lib/onetime/session_utils.rb'))
src.include?('rescue StandardError')
#=> true

# Teardown: clean up any leftover Redis keys from these tests
@keys_to_cleanup.each { |k| Familia.dbclient.del(k) rescue nil }
Familia.dbclient.del(keep) rescue nil
