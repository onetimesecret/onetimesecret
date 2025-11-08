# try/unit/session_try.rb
#
# frozen_string_literal: true

#
# Session Test Suite
#

# Setup - Load the real application
ENV['RACK_ENV'] = 'test'
ENV['AUTHENTICATION_MODE'] = 'basic'  # Force basic mode before boot
ENV['ONETIME_HOME'] ||= File.expand_path(File.join(__dir__, '..', '..')).freeze

require 'rack'
require 'ostruct'

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

## Session initializes with required secret
begin
  Session.new(@app, { key: 'test' })
  false
rescue ArgumentError => e
  e.message.include?("Secret required")
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
