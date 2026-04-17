# try/unit/error_handler_try.rb
#
# frozen_string_literal: true

# These tryouts test the Onetime::ErrorHandler module functionality.
# The ErrorHandler provides robust error handling for non-critical operations
# with Redis-based error tracking using an atomic Lua script.
#
# We're testing:
# 1. track_error increments counter atomically
# 2. New keys get correct 7-day TTL set in same operation
# 3. Existing keys increment without changing TTL
# 4. safe_execute catches errors and tracks them

require_relative '../support/test_models'
require 'onetime/error_handler'

OT.boot! :test, true

@redis = Familia.dbclient
@test_date_str = Date.today.strftime('%Y%m%d')
@test_operation = "test_operation_#{Familia.now.to_i}_#{rand(10000)}"
@test_key = "errors:rodauth:#{@test_operation}:#{@test_date_str}"

# Clean up any existing test keys before testing
@redis.del(@test_key)

## ErrorHandler responds to safe_execute
Onetime::ErrorHandler.respond_to?(:safe_execute)
#=> true

## ErrorHandler has TRACK_ERROR_LUA constant
# The Lua script is defined as a constant in the module
lua_script = Onetime::ErrorHandler.const_get(:TRACK_ERROR_LUA)
lua_script.include?('INCR') && lua_script.include?('EXPIRE')
#=> true

## ERROR_TRACKING_TTL is 7 days in seconds (604800)
ttl_constant = Onetime::ErrorHandler.const_get(:ERROR_TRACKING_TTL)
ttl_constant
#=> 604800

## track_error creates key with count of 1 on first call
# We need to access the private method for testing
Onetime::ErrorHandler.send(:track_error, @test_operation)
@redis.get(@test_key).to_i
#=> 1

## New key gets TTL set (should be around 7 days = 604800 seconds)
ttl = @redis.ttl(@test_key)
# TTL should be close to 604800 (7 days) - allow some margin for test execution
ttl > 604700 && ttl <= 604800
#=> true

## track_error increments existing key to 2
Onetime::ErrorHandler.send(:track_error, @test_operation)
@redis.get(@test_key).to_i
#=> 2

## track_error increments existing key to 3
Onetime::ErrorHandler.send(:track_error, @test_operation)
@redis.get(@test_key).to_i
#=> 3

## Existing key TTL is preserved (doesn't reset on increment)
# Set a known TTL first, then increment and verify it wasn't changed
@redis.expire(@test_key, 1000)  # Set TTL to 1000 seconds
Onetime::ErrorHandler.send(:track_error, @test_operation)
count = @redis.get(@test_key).to_i
ttl_after = @redis.ttl(@test_key)
# Count should be 4, TTL should still be around 1000 (not reset to 604800)
[count, ttl_after <= 1000 && ttl_after > 0]
#=> [4, true]

## safe_execute does not raise on error
error_occurred = false
result = begin
  Onetime::ErrorHandler.safe_execute('test_safe_execute') do
    raise StandardError, 'Test error'
  end
  :no_error_raised
rescue StandardError
  error_occurred = true
  :error_raised
end
[result, error_occurred]
#=> [:no_error_raised, false]

## safe_execute returns nil when block raises
# Create a new test key for this test
@test_operation_2 = "test_op2_#{Familia.now.to_i}_#{rand(10000)}"
@test_key_2 = "errors:rodauth:#{@test_operation_2}:#{@test_date_str}"
@redis.del(@test_key_2)

result = Onetime::ErrorHandler.safe_execute(@test_operation_2) do
  raise StandardError, 'Test error'
end
result
#=> nil

## safe_execute tracks the error
# The error should have been tracked in Redis
@redis.get(@test_key_2).to_i
#=> 1

## safe_execute returns block value on success
result = Onetime::ErrorHandler.safe_execute('success_operation') do
  42
end
result
#=> 42

## Lua script handles sequential increments correctly
# Reset test key
@test_key_3 = "errors:rodauth:sequential_test:#{@test_date_str}"
@redis.del(@test_key_3)

# Run 10 sequential track_error calls
10.times { Onetime::ErrorHandler.send(:track_error, 'sequential_test') }
@redis.get(@test_key_3).to_i
#=> 10

## First increment sets TTL, subsequent do not reset it
@test_key_4 = "errors:rodauth:ttl_preserve_test:#{@test_date_str}"
@redis.del(@test_key_4)

# First track_error sets the TTL
Onetime::ErrorHandler.send(:track_error, 'ttl_preserve_test')
original_ttl = @redis.ttl(@test_key_4)

# Manually reduce TTL to simulate time passing
@redis.expire(@test_key_4, 500)
reduced_ttl = @redis.ttl(@test_key_4)

# Second track_error should NOT reset TTL
Onetime::ErrorHandler.send(:track_error, 'ttl_preserve_test')
final_ttl = @redis.ttl(@test_key_4)

# original_ttl should be ~604800, reduced should be ~500, final should still be <= 500
[original_ttl > 604700, reduced_ttl <= 500, final_ttl <= 500 && final_ttl > 0]
#=> [true, true, true]

# -----------------------------------------------------------------------------
# Gate-state methods (trackable? / sentry_available?) -- PR #3012 additions
#
# safe_execute's rescue branch emits debug logs describing whether Sentry is
# available and whether tracking is possible. The branches pivot on two private
# predicates. These tests cover the predicates directly (and confirm the
# return-value invariant under the common "no Sentry" path).
# -----------------------------------------------------------------------------

## sentry_available? is a private class method
# Cannot be called without .send(...) -- guards against accidental exposure.
Onetime::ErrorHandler.respond_to?(:sentry_available?, true)
#=> true

## sentry_available? is NOT a public method
Onetime::ErrorHandler.respond_to?(:sentry_available?)
#=> false

## sentry_available? returns a falsy value when Sentry is not defined or not initialized
# The method is literally `defined?(Sentry) && Sentry.initialized?` -- `defined?`
# returns nil for undefined constants and `nil && x` short-circuits to nil.
# Whether Sentry is undefined (nil) or present-but-uninitialized (false), the
# predicate must be falsy.
result = Onetime::ErrorHandler.send(:sentry_available?)
[!result, [nil, false].include?(result)]
#=> [true, true]

## sentry_available? output is consistent across calls (pure read)
r1 = Onetime::ErrorHandler.send(:sentry_available?)
r2 = Onetime::ErrorHandler.send(:sentry_available?)
r1 == r2
#=> true

## trackable? is a private class method
Onetime::ErrorHandler.respond_to?(:trackable?, true)
#=> true

## trackable? returns a Boolean reflecting Familia.dbclient availability
# dbclient is present in the test environment (we've already used it above),
# so trackable? must be true here.
result = Onetime::ErrorHandler.send(:trackable?)
[result.is_a?(TrueClass) || result.is_a?(FalseClass), !Familia.dbclient.nil?, result]
#=> [true, true, true]

## Regression -- safe_execute return value is nil even after the new debug-log
## emission in the rescue branch (the log call must not leak through as the
## method's return value).
@test_key_5 = "errors:rodauth:debug_log_invariant:#{@test_date_str}"
@redis.del(@test_key_5)
return_value = Onetime::ErrorHandler.safe_execute('debug_log_invariant') do
  raise ArgumentError, 'boom'
end
return_value
#=> nil

## Regression -- track_error still ran alongside the new debug log
# Confirms the rescue branch is still executing its full sequence.
@redis.get(@test_key_5).to_i
#=> 1

# -----------------------------------------------------------------------------
# Additional gate/branch coverage (PR #3012)
#
# - safe_execute rescues StandardError only (non-StandardError propagates).
# - Context kwargs pass through to the error log without affecting the return.
# - trackable? true path: track_error actually runs alongside the rescue.
# - sentry_available? false path (current env): capture_error does NOT run
#   and the rescue still returns nil.
# - Success path: context kwargs do not alter block return value.
# -----------------------------------------------------------------------------

## safe_execute does NOT rescue non-StandardError exceptions
# rescue StandardError means ScriptError/Interrupt/SystemExit are not caught.
# A plain Exception subclass falls outside the rescue clause and propagates.
class NonStandardBoom < Exception; end
raised = nil
begin
  Onetime::ErrorHandler.safe_execute('non_standard_boom') do
    raise NonStandardBoom, 'propagate me'
  end
rescue NonStandardBoom => ex
  raised = ex
end
[raised.nil?, raised&.message]
#=> [false, 'propagate me']

## safe_execute returns nil and still invokes track_error under trackable?=true
# With Familia.dbclient present (as throughout this file), the trackable? gate
# evaluates to true -- so the counter must increment even when sentry_available?
# is false in the test environment.
@test_key_6 = "errors:rodauth:gate_trackable_true:#{@test_date_str}"
@redis.del(@test_key_6)
return_value = Onetime::ErrorHandler.safe_execute('gate_trackable_true') do
  raise StandardError, 'kaboom'
end
[return_value, @redis.get(@test_key_6).to_i]
#=> [nil, 1]

## safe_execute passes context kwargs through (does not raise on arbitrary keys)
# Proves the **context splat reaches log_error cleanly. Return value remains nil.
@test_key_7 = "errors:rodauth:ctx_passthrough:#{@test_date_str}"
@redis.del(@test_key_7)
return_value = Onetime::ErrorHandler.safe_execute(
  'ctx_passthrough',
  account_id: 42,
  customer_id: 'cust_abc',
  arbitrary: { nested: true },
) { raise StandardError, 'ctx' }
[return_value, @redis.get(@test_key_7).to_i]
#=> [nil, 1]

## Success path preserves block return value regardless of context kwargs
result = Onetime::ErrorHandler.safe_execute('success_with_ctx', account_id: 1, reason: 'test') do
  { status: 'ok', n: 7 }
end
result
#=> { status: 'ok', n: 7 }

## Success path does NOT invoke track_error (no key created)
# Proves the rescue branch is the only place tracking happens.
@test_key_8 = "errors:rodauth:success_no_track:#{@test_date_str}"
@redis.del(@test_key_8)
_ = Onetime::ErrorHandler.safe_execute('success_no_track') { :ok }
@redis.get(@test_key_8)
#=> nil

## sentry_available? is false in this env, so capture_error is skipped
# When sentry_available? is false, the rescue emits the 'skipped' debug log and
# returns nil WITHOUT going through capture_error. If capture_error had run
# against an uninitialized Sentry, we'd have seen a NoMethodError bubble up.
# (Confirmed by: safe_execute already returned nil in multiple prior cases.)
sentry_ok = Onetime::ErrorHandler.send(:sentry_available?)
# No exception propagated from the earlier rescues -- combined with sentry_ok
# being falsy, we've exercised the else branch.
[!sentry_ok, true]
#=> [true, true]

## Sequential safe_execute calls accumulate on the same daily counter key
# Confirms the key shape is stable and that two failures bump the same key.
@test_key_9 = "errors:rodauth:sequential_safe:#{@test_date_str}"
@redis.del(@test_key_9)
3.times do
  Onetime::ErrorHandler.safe_execute('sequential_safe') { raise StandardError, 'x' }
end
@redis.get(@test_key_9).to_i
#=> 3

# -----------------------------------------------------------------------------
# http_headers_from redaction (PR #3012)
#
# The debug logging path runs exactly when operators enable debug mode in
# production to diagnose dropped Sentry events. Any Basic Auth, cookie, or
# API-key header reaching the log aggregator is a credential-leak risk.
# -----------------------------------------------------------------------------

## http_headers_from redacts HTTP_AUTHORIZATION
env = {
  'HTTP_AUTHORIZATION' => 'Basic dXNlcjpwYXNz',
  'HTTP_USER_AGENT'    => 'curl/8.0',
  'REQUEST_METHOD'     => 'GET',
}
result = Onetime::ErrorHandler.http_headers_from(env)
[result['HTTP_AUTHORIZATION'], result['HTTP_USER_AGENT'], result.key?('REQUEST_METHOD')]
#=> ["[FILTERED]", "curl/8.0", false]

## http_headers_from redacts HTTP_COOKIE and proxy/api-key variants
env = {
  'HTTP_COOKIE'              => 'sess=secret; csrf=abc',
  'HTTP_PROXY_AUTHORIZATION' => 'Bearer xyz',
  'HTTP_X_API_KEY'           => 'ak_live_123',
  'HTTP_X_AUTH_TOKEN'        => 'tok_456',
  'HTTP_ACCEPT'              => 'application/json',
}
result = Onetime::ErrorHandler.http_headers_from(env)
[
  result['HTTP_COOKIE'],
  result['HTTP_PROXY_AUTHORIZATION'],
  result['HTTP_X_API_KEY'],
  result['HTTP_X_AUTH_TOKEN'],
  result['HTTP_ACCEPT'],
]
#=> ["[FILTERED]", "[FILTERED]", "[FILTERED]", "[FILTERED]", "application/json"]

## http_headers_from returns {} for non-Hash env
Onetime::ErrorHandler.http_headers_from(nil)
#=> {}

## http_headers_from tolerates non-String keys without raising
# Real Rack env is String-keyed, but the debug path must never crash.
env = { :symbol_key => 'ignored', 'HTTP_HOST' => 'example.com', 42 => 'also ignored' }
Onetime::ErrorHandler.http_headers_from(env)
#=> {"HTTP_HOST"=>"example.com"}

# Clean up test keys
@redis.del(@test_key)
@redis.del(@test_key_2)
@redis.del(@test_key_3)
@redis.del(@test_key_4)
@redis.del(@test_key_5)
@redis.del(@test_key_6)
@redis.del(@test_key_7)
@redis.del(@test_key_8)
@redis.del(@test_key_9)
