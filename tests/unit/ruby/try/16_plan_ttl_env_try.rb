# tests/unit/ruby/try/16_plan_ttl_env_try.rb

# These tryouts test the Plan.parse_ttl_env method which allows
# plan TTL limits to be configured via environment variables.
#
# Test cases cover:
# 1. Default value when env var is not set
# 2. Default value for empty string
# 3. Default value for non-positive values (0, negative)
# 4. Valid positive integer parsing
# 5. Capping at MAX_TTL for oversized values
# 6. Default value for non-numeric strings
# 7. Strict parsing rejects partial matches (e.g., "123abc")
# 8. Strict parsing rejects decimal numbers (e.g., "3600.5")

require_relative './test_helpers'

# Use the default config file for tests
OT.boot! :test, false

# Store original env values to restore later
ORIGINAL_TEST_TTL = ENV['TEST_TTL']

## MAX_TTL is defined as 365 days
OT::Plan::MAX_TTL
#=> 31536000

## Returns default when env var is not set (nil)
ENV.delete('TEST_TTL')
OT::Plan.parse_ttl_env('TEST_TTL', 1000)
#=> 1000

## Returns default for empty string
ENV['TEST_TTL'] = ''
OT::Plan.parse_ttl_env('TEST_TTL', 1000)
#=> 1000

## Returns default for zero value
ENV['TEST_TTL'] = '0'
OT::Plan.parse_ttl_env('TEST_TTL', 1000)
#=> 1000

## Returns default for negative value
ENV['TEST_TTL'] = '-100'
OT::Plan.parse_ttl_env('TEST_TTL', 1000)
#=> 1000

## Returns parsed value for valid positive integer
ENV['TEST_TTL'] = '2592000'
OT::Plan.parse_ttl_env('TEST_TTL', 1000)
#=> 2592000

## Returns parsed value for small valid integer
ENV['TEST_TTL'] = '3600'
OT::Plan.parse_ttl_env('TEST_TTL', 1000)
#=> 3600

## Caps at MAX_TTL for oversized values
ENV['TEST_TTL'] = '99999999999'
OT::Plan.parse_ttl_env('TEST_TTL', 1000)
#=> 31536000

## Caps at MAX_TTL for value just over MAX_TTL
ENV['TEST_TTL'] = '31536001'
OT::Plan.parse_ttl_env('TEST_TTL', 1000)
#=> 31536000

## Returns exactly MAX_TTL when set to MAX_TTL
ENV['TEST_TTL'] = '31536000'
OT::Plan.parse_ttl_env('TEST_TTL', 1000)
#=> 31536000

## Returns default for non-numeric string (to_i returns 0)
ENV['TEST_TTL'] = 'invalid'
OT::Plan.parse_ttl_env('TEST_TTL', 1000)
#=> 1000

## Returns default for string with leading text
ENV['TEST_TTL'] = 'abc123'
OT::Plan.parse_ttl_env('TEST_TTL', 1000)
#=> 1000

## Returns default for string with trailing text (strict parsing rejects partial matches)
ENV['TEST_TTL'] = '123abc'
OT::Plan.parse_ttl_env('TEST_TTL', 1000)
#=> 1000

## Returns default for decimal numbers (strict integer parsing)
ENV['TEST_TTL'] = '3600.5'
OT::Plan.parse_ttl_env('TEST_TTL', 1000)
#=> 1000

## Handles values with leading/trailing whitespace (Integer() strips whitespace)
ENV['TEST_TTL'] = '  3600  '
OT::Plan.parse_ttl_env('TEST_TTL', 1000)
#=> 3600

## Plan TTL env vars work for anonymous plan
ENV['PLAN_TTL_ANONYMOUS'] = '1209600'
OT::Plan.load_plans!
OT::Plan.plan(:anonymous).options[:ttl]
#=> 1209600

## Plan TTL env vars are capped at MAX_TTL
ENV['PLAN_TTL_ANONYMOUS'] = '99999999999'
OT::Plan.load_plans!
OT::Plan.plan(:anonymous).options[:ttl]
#=> 31536000

# Clean up environment variables after tests
ENV['TEST_TTL'] = ORIGINAL_TEST_TTL
ENV.delete('PLAN_TTL_ANONYMOUS')
ENV.delete('PLAN_TTL_BASIC')
ENV.delete('PLAN_TTL_IDENTITY')

# Reload plans with default values
OT::Plan.load_plans!
