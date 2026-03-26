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

# Clean up test keys
@redis.del(@test_key)
@redis.del(@test_key_2)
@redis.del(@test_key_3)
@redis.del(@test_key_4)
