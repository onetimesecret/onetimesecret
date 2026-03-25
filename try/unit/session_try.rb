# try/unit/session_try.rb
#
# frozen_string_literal: true

#
# Session Test Suite
#

# Setup - Load the real application
ENV['AUTHENTICATION_MODE'] = 'simple'  # Force simple mode before boot

require 'rack'

require_relative '../support/test_helpers'

require 'onetime'
require 'onetime/session'

OT.boot! :test, false

Session = Onetime::Session



# Helper class for mocking Rack requests
class MockRequest
  attr_accessor :cookies

  def initialize(cookies = {})
    @cookies = cookies
  end
end

# Helper class for mocking Rack apps
class MockApp
  def call(env)
    [200, {}, ["OK"]]
  end
end

# Setup
@app = MockApp.new
@secret = SecureRandom.hex(64)
@session_opts = {
  secret: @secret,
  key: 'test.session',
  expire_after: 3600,
  namespace: 'testsession'
}
@session = Session.new(@app, @session_opts)

# Helper method to access private methods for testing
def call_private_method(obj, method_name, *args)
  obj.send(method_name, *args)
end

## Session initializes using site secret fallback when secret not provided
begin
  session = Session.new(@app, { key: 'test' })
  # Falls back to site secret in test config, so this should succeed
  session.is_a?(Session)
rescue ArgumentError => e
  # Only fails if site secret is also not available
  false
end
#=> true

## Session initializes successfully with secret
session = Session.new(@app, @session_opts)
session.is_a?(Session)
#=> true

## Generate secure session ID with correct format (wrapped in SessionId)
sid = call_private_method(@session, :generate_sid)
# Parent class wraps in SessionId object
sid.is_a?(Rack::Session::SessionId) && sid.public_id.length == 64
#=> true

## Validate correct session ID format
valid_sid = SecureRandom.hex(32)
call_private_method(@session, :valid_session_id?, valid_sid)
#=> true

## Reject invalid session ID formats
invalid_sids = [nil, "", "short", "invalid-chars!", "x" * 63, "x" * 65]
invalid_sids.all? do |sid|
  !call_private_method(@session, :valid_session_id?, sid)
end
#=> true



## Derive consistent keys for different purposes
hmac_key1 = call_private_method(@session, :derive_key, 'hmac')
hmac_key2 = call_private_method(@session, :derive_key, 'hmac')
enc_key = call_private_method(@session, :derive_key, 'encryption')
hmac_key1 == hmac_key2 && hmac_key1 != enc_key
#=> true

## Encryption key is 32 bytes (64 hex chars) for AES-256
enc_key = call_private_method(@session, :derive_key, 'encryption')
enc_key.length == 64 && enc_key.match?(/\A[a-f0-9]+\z/)
#=> true

## Encryption key raw is 32 bytes for AES-256
enc_key_raw = @session.instance_variable_get(:@encryption_key_raw)
enc_key_raw.bytesize == 32
#=> true

## encrypt_data produces ciphertext with IV and auth_tag prefix (28+ bytes)
plaintext = '{"account_id":123}'
encrypted = call_private_method(@session, :encrypt_data, plaintext)
# Must be at least 28 bytes (12 IV + 16 auth_tag + encrypted data)
encrypted.bytesize >= 28
#=> true

## encrypt_data produces different ciphertext each time (random IV)
plaintext = '{"account_id":123}'
encrypted1 = call_private_method(@session, :encrypt_data, plaintext)
encrypted2 = call_private_method(@session, :encrypt_data, plaintext)
encrypted1 != encrypted2
#=> true

## decrypt_data recovers original plaintext
plaintext = '{"account_id":123}'
encrypted = call_private_method(@session, :encrypt_data, plaintext)
decrypted = call_private_method(@session, :decrypt_data, encrypted)
decrypted == plaintext
#=> true

## decrypt_data handles complex JSON data
complex_data = '{"account_id":456,"email":"test@example.com","mfa":true,"roles":["admin","user"]}'
encrypted = call_private_method(@session, :encrypt_data, complex_data)
decrypted = call_private_method(@session, :decrypt_data, encrypted)
decrypted == complex_data
#=> true

## decrypt_data returns nil for data too short (missing IV or auth_tag)
short_data = "x" * 20  # Less than 28 bytes minimum
result = call_private_method(@session, :decrypt_data, short_data)
result.nil?
#=> true

## decrypt_data returns nil for nil input
result = call_private_method(@session, :decrypt_data, nil)
result.nil?
#=> true

## decrypt_data returns nil for tampered ciphertext (auth_tag verification fails)
plaintext = '{"account_id":123}'
encrypted = call_private_method(@session, :encrypt_data, plaintext)
# Tamper with the ciphertext portion (after IV and auth_tag)
tampered = encrypted[0, 28] + "x" * (encrypted.bytesize - 28)
result = call_private_method(@session, :decrypt_data, tampered)
result.nil?
#=> true

## decrypt_data returns nil for tampered auth_tag
plaintext = '{"account_id":123}'
encrypted = call_private_method(@session, :encrypt_data, plaintext)
# Tamper with the auth_tag (bytes 12-27)
tampered = encrypted[0, 12] + ("x" * 16) + encrypted[28..]
result = call_private_method(@session, :decrypt_data, tampered)
result.nil?
#=> true

## Compute HMAC consistently for data
data = "test data"
hmac1 = call_private_method(@session, :compute_hmac, data)
hmac2 = call_private_method(@session, :compute_hmac, data)
hmac1 == hmac2 && hmac1.length == 64
#=> true

## Valid HMAC verification succeeds
data = "test data"
hmac = call_private_method(@session, :compute_hmac, data)
call_private_method(@session, :valid_hmac?, data, hmac)
#=> true

## Invalid HMAC verification fails
data = "test data"
bad_hmac = "invalid" + "0" * 58
!call_private_method(@session, :valid_hmac?, data, bad_hmac)
#=> true

## Create and retrieve StringKey instance
sid = SecureRandom.hex(32)
stringkey = call_private_method(@session, :get_stringkey, sid)
stringkey.is_a?(Familia::StringKey)
#=> true

## Create new StringKey instances each time (no caching)
sid = SecureRandom.hex(32)
key1 = call_private_method(@session, :get_stringkey, sid)
key2 = call_private_method(@session, :get_stringkey, sid)
# Each call creates a new instance, but they represent the same Redis key
key1.object_id != key2.object_id && key1.keystring == key2.keystring
#=> true

## Find session returns new session for new request
request = MockRequest.new({})
sid, data = call_private_method(@session, :find_session, request, nil)
# Parent class wraps in SessionId object
sid.is_a?(Rack::Session::SessionId) && sid.public_id.length == 64 && data == {}
#=> true

## Write and read session data successfully
request = MockRequest.new({})
sid = SecureRandom.hex(32)
session_data = { "user_id" => 123, "username" => "testuser" }
written_sid = call_private_method(@session, :write_session, request, sid, session_data, {})
# Also read it back in the same test
request_with_cookie = MockRequest.new('test.session' => sid)
found_sid, found_data = call_private_method(@session, :find_session, request_with_cookie, sid)
written_sid == sid && found_sid == sid && found_data == session_data
#=> true

## Delete session removes data and returns new SID
request = MockRequest.new({})
old_sid = SecureRandom.hex(32)
new_sid = call_private_method(@session, :delete_session, request, old_sid, {})
# Parent class wraps in SessionId object
new_sid.is_a?(Rack::Session::SessionId) && new_sid.public_id != old_sid
#=> true

## Tampered session data creates new session
# First write a legitimate session
sid = SecureRandom.hex(32)
session_data = { "user" => "legitimate" }
call_private_method(@session, :write_session, MockRequest.new, sid, session_data, {})

# Now tamper with the stored data
stringkey = call_private_method(@session, :get_stringkey, sid)
tampered = Base64.encode64('{"user":"hacker"}').gsub("\n", '') + "--invalidhmac"
stringkey.set(tampered)

# Try to read the tampered session
request = MockRequest.new('test.session' => sid)
new_sid, new_data = call_private_method(@session, :find_session, request, sid)
new_sid != sid && new_data == {}
#=> true

## Session with no HMAC creates new session
sid = SecureRandom.hex(32)
stringkey = call_private_method(@session, :get_stringkey, sid)
stringkey.set("data_without_hmac")

request = MockRequest.new('test.session' => sid)
new_sid, new_data = call_private_method(@session, :find_session, request, sid)
new_sid != sid && new_data == {}
#=> true

## Handle Redis connection errors gracefully
# Simulate error by using invalid session ID that would cause issues
sid = SecureRandom.hex(32)
session_data = { "test" => "data" }

# Mock a failing StringKey by creating one with invalid options
# This tests error handling in write_session
request = MockRequest.new({})
result = call_private_method(@session, :write_session, request, nil, session_data, {})
result == false
#=> true

## Session expiration configuration is correct
# The session is configured with expire_after: 3600
# We can verify the option is set correctly
@session.instance_variable_get(:@expire_after) == 3600
#=> true

## Session without redis_uri still initializes
session_no_redis = Session.new(@app, { secret: @secret })
session_no_redis.is_a?(Session)
#=> true

# Note: Redis TTL will automatically clean up test sessions
