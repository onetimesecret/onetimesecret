# apps/web/billing/try/cli/helpers_try.rb
#
# frozen_string_literal: true

require_relative '../../../../../try/support/test_helpers'

# Unit tests for BillingHelpers module
#
# Tests helper methods used across billing CLI commands.
# These are pure unit tests that don't require Stripe API access.

require 'onetime/cli'
require_relative '../../cli/helpers'

# Create a test class that includes the helpers
@helper_class = Class.new { include Onetime::CLI::BillingHelpers }

## Test: format_amount converts cents to dollars
helper = @helper_class.new
helper.format_amount(1000, 'usd')
#=> 'USD 10.00'

## Test: format_amount handles zero
helper = @helper_class.new
helper.format_amount(0, 'usd')
#=> 'USD 0.00'

## Test: format_amount handles large amounts
helper = @helper_class.new
helper.format_amount(99999, 'usd')
#=> 'USD 999.99'

## Test: format_amount handles nil amount
helper = @helper_class.new
helper.format_amount(nil, 'usd')
#=> 'N/A'

## Test: format_amount handles nil currency
helper = @helper_class.new
helper.format_amount(1000, nil)
#=> 'USD 10.00'

## Test: format_amount uppercases currency
helper = @helper_class.new
helper.format_amount(500, 'eur')
#=> 'EUR 5.00'

## Test: format_timestamp converts unix time
helper = @helper_class.new
# Fixed timestamp: 2024-01-15 12:00:00 UTC
helper.format_timestamp(1705320000)
#=~ /2024-01-15.*12:00:00.*UTC/

## Test: format_timestamp handles nil
helper = @helper_class.new
helper.format_timestamp(nil)
#=> 'N/A'

## Test: format_timestamp handles string timestamp
helper = @helper_class.new
helper.format_timestamp('1705320000')
#=~ /2024-01-15.*UTC/

## Test: format_timestamp handles non-numeric string (converts to 0/epoch)
helper = @helper_class.new
# 'invalid'.to_i returns 0, which is the Unix epoch
helper.format_timestamp('invalid')
#=~ /1969-12-31|1970-01-01/

## Test: format_stripe_error for InvalidRequestError
require 'stripe'
helper = @helper_class.new
error = Stripe::InvalidRequestError.new('No such customer', 'customer')
helper.format_stripe_error('Failed', error)
#=~ /Invalid parameters.*No such customer/

## Test: format_stripe_error for AuthenticationError
helper = @helper_class.new
error = Stripe::AuthenticationError.new('Invalid API key')
helper.format_stripe_error('Failed', error)
#=~ /Authentication failed.*STRIPE_KEY/

## Test: format_stripe_error for RateLimitError
helper = @helper_class.new
error = Stripe::RateLimitError.new('Too many requests')
helper.format_stripe_error('Failed', error)
#=~ /Rate limited/

## Test: format_stripe_error for APIConnectionError
helper = @helper_class.new
error = Stripe::APIConnectionError.new('Network unreachable')
helper.format_stripe_error('Failed', error)
#=~ /Network error/

## Test: format_stripe_error for CardError
helper = @helper_class.new
error = Stripe::CardError.new('Card declined', 'card_number', code: 'card_declined')
helper.format_stripe_error('Failed', error)
#=~ /Card error.*Card declined/

## Test: format_stripe_error for generic StripeError
helper = @helper_class.new
error = Stripe::StripeError.new('Something went wrong')
helper.format_stripe_error('Failed', error)
#=~ /Failed.*Something went wrong/

## Test: measure_api_time returns result and elapsed time
helper = @helper_class.new
result, elapsed = helper.measure_api_time { sleep(0.01); 'done' }
result
#=> 'done'

## Test: measure_api_time elapsed is positive
helper = @helper_class.new
result, elapsed = helper.measure_api_time { sleep(0.01); 'done' }
elapsed >= 10
#=> true

## Test: validate_product_metadata detects missing fields
helper = @helper_class.new
# Mock a product with minimal metadata
product = OpenStruct.new(metadata: { 'app' => 'onetimesecret' })
errors = helper.validate_product_metadata(product)
errors.any? { |e| e.include?('Missing required') }
#=> true

## Test: validate_product_metadata accepts valid app
helper = @helper_class.new
product = OpenStruct.new(metadata: {
  'app' => 'onetimesecret',
  'plan_id' => 'test_v1',
  'tier' => 'basic',
  'region' => 'global',
  'capabilities' => 'test',
  'tenancy' => 'single'
})
errors = helper.validate_product_metadata(product)
errors.none? { |e| e.include?("Invalid app metadata") }
#=> true

## Test: validate_product_metadata rejects wrong app
helper = @helper_class.new
product = OpenStruct.new(metadata: { 'app' => 'wrong_app' })
errors = helper.validate_product_metadata(product)
errors.any? { |e| e.include?("Invalid app metadata") }
#=> true
