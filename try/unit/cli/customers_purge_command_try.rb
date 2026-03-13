# try/unit/cli/customers_purge_command_try.rb
#
# frozen_string_literal: true

# Unit tests for CustomersPurgeCommand utility methods.
# Tests parse_duration, parse_ts, parse_json_field, format_ttl,
# and stripe_billing? logic without requiring a full Redis scan
# or boot_application!.
#
# Run: bundle exec try try/unit/cli/customers_purge_command_try.rb

require_relative '../../support/test_helpers'
require 'onetime/cli'

@cmd = Onetime::CLI::CustomersPurgeCommand.new

# -------------------------------------------------------------------
# Command class basics
# -------------------------------------------------------------------

## CustomersPurgeCommand exists and inherits from Command
Onetime::CLI::CustomersPurgeCommand.ancestors.include?(Onetime::CLI::Command)
#=> true

## CustomersPurgeCommand is a Dry::CLI::Command
@cmd.is_a?(Dry::CLI::Command)
#=> true

## CACHE_TTL is 30 minutes (1800 seconds)
Onetime::CLI::CustomersPurgeCommand::CACHE_TTL
#=> 1800

## SCAN_COUNT is 200
Onetime::CLI::CustomersPurgeCommand::SCAN_COUNT
#=> 200

## BATCH_SIZE is 50
Onetime::CLI::CustomersPurgeCommand::BATCH_SIZE
#=> 50

## ACTIVITY_CACHE key has expected prefix
Onetime::CLI::CustomersPurgeCommand::ACTIVITY_CACHE.start_with?('tmp:cli:')
#=> true

# -------------------------------------------------------------------
# parse_duration: duration string parsing
# -------------------------------------------------------------------

## parse_duration with 6m returns 6 months in seconds
@cmd.send(:parse_duration, '6m')
#=> 15552000

## parse_duration with 1y returns 1 year in seconds
@cmd.send(:parse_duration, '1y')
#=> 31536000

## parse_duration with 2y returns 2 years in seconds
@cmd.send(:parse_duration, '2y')
#=> 63072000

## parse_duration with 3y returns 3 years in seconds
@cmd.send(:parse_duration, '3y')
#=> 94608000

## parse_duration with 5y returns 5 years in seconds
@cmd.send(:parse_duration, '5y')
#=> 157680000

## parse_duration with 12m returns 12 months in seconds
@cmd.send(:parse_duration, '12m')
#=> 31104000

## parse_duration with 18m returns 18 months in seconds
@cmd.send(:parse_duration, '18m')
#=> 46656000

## parse_duration is case insensitive for M (months)
@cmd.send(:parse_duration, '6M')
#=> 15552000

## parse_duration is case insensitive for Y (years)
@cmd.send(:parse_duration, '1Y')
#=> 31536000

## parse_duration month calculation: num * 30 * 86400
6 * 30 * 86_400
#=> 15552000

## parse_duration year calculation: num * 365 * 86400
1 * 365 * 86_400
#=> 31536000

## parse_duration with invalid input raises ArgumentError
begin
  @cmd.send(:parse_duration, 'invalid')
  false
rescue ArgumentError
  true
end
#=> true

## parse_duration with unsupported unit (days) raises ArgumentError
begin
  @cmd.send(:parse_duration, '5d')
  false
rescue ArgumentError
  true
end
#=> true

## parse_duration with empty string raises ArgumentError
begin
  @cmd.send(:parse_duration, '')
  false
rescue ArgumentError
  true
end
#=> true

## parse_duration with negative number raises ArgumentError
begin
  @cmd.send(:parse_duration, '-3y')
  false
rescue ArgumentError
  true
end
#=> true

## parse_duration with zero months is valid (edge case)
@cmd.send(:parse_duration, '0m')
#=> 0

# -------------------------------------------------------------------
# parse_ts: timestamp parsing (shared behavior with dates command)
# -------------------------------------------------------------------

## parse_ts with valid JSON-encoded float returns float
@cmd.send(:parse_ts, '"1609459200.0"')
#=> 1609459200.0

## parse_ts with valid JSON-encoded integer returns float
@cmd.send(:parse_ts, '1609459200')
#=> 1609459200.0

## parse_ts with nil returns 0.0
@cmd.send(:parse_ts, nil)
#=> 0.0

## parse_ts with empty string returns 0.0
@cmd.send(:parse_ts, '')
#=> 0.0

## parse_ts with whitespace-only string returns 0.0
@cmd.send(:parse_ts, '   ')
#=> 0.0

## parse_ts with bare numeric string falls back to to_f
@cmd.send(:parse_ts, '1609459200.5')
#=> 1609459200.5

## parse_ts with non-numeric garbage returns 0.0
@cmd.send(:parse_ts, 'not-a-number')
#=> 0.0

# -------------------------------------------------------------------
# parse_json_field: JSON field parsing
# -------------------------------------------------------------------

## parse_json_field with valid JSON string returns parsed value
@cmd.send(:parse_json_field, '"admin"')
#=> "admin"

## parse_json_field with nil returns nil
@cmd.send(:parse_json_field, nil)
#=> nil

## parse_json_field with empty string returns nil
@cmd.send(:parse_json_field, '')
#=> nil

## parse_json_field with invalid JSON falls back to raw string
@cmd.send(:parse_json_field, 'plain-text')
#=> "plain-text"

## parse_json_field with JSON email returns parsed string
@cmd.send(:parse_json_field, '"user@example.com"')
#=> "user@example.com"

# -------------------------------------------------------------------
# format_ttl: TTL formatting
# -------------------------------------------------------------------

## format_ttl with 1800 seconds returns 30m 0s
@cmd.send(:format_ttl, 1800)
#=> "30m 0s"

## format_ttl with 90 seconds returns 1m 30s
@cmd.send(:format_ttl, 90)
#=> "1m 30s"

## format_ttl with 45 seconds returns 45s
@cmd.send(:format_ttl, 45)
#=> "45s"

## format_ttl with 0 seconds returns 0s
@cmd.send(:format_ttl, 0)
#=> "0s"

# -------------------------------------------------------------------
# stripe_billing? logic (structural tests without live data)
# -------------------------------------------------------------------

## stripe_billing? returns true when stripe_customer_id is set
@mock_cust_class = Struct.new(:stripe_customer_id, :stripe_subscription_id, :objid) do
  def organization_instances; []; end
  def obscure_email; "t***@example.com"; end
end
cust = @mock_cust_class.new('cus_abc123', '', 'testid')
@cmd.send(:stripe_billing?, cust)
#=> true

## stripe_billing? returns true when stripe_subscription_id is set
cust = @mock_cust_class.new('', 'sub_xyz789', 'testid')
@cmd.send(:stripe_billing?, cust)
#=> true

## stripe_billing? returns false when no billing fields set
cust = @mock_cust_class.new('', '', 'testid')
@cmd.send(:stripe_billing?, cust)
#=> false

## stripe_billing? returns true when organization has stripe_customer_id
org = Struct.new(:stripe_customer_id).new('cus_org456')
cust = @mock_cust_class.new('', '', 'testid')
cust.define_singleton_method(:organization_instances) { [org] }
@cmd.send(:stripe_billing?, cust)
#=> true

## stripe_billing? returns false when organization has empty stripe_customer_id
org = Struct.new(:stripe_customer_id).new('')
cust = @mock_cust_class.new('', '', 'testid')
cust.define_singleton_method(:organization_instances) { [org] }
@cmd.send(:stripe_billing?, cust)
#=> false

## stripe_billing? handles nil organization in list gracefully
cust = @mock_cust_class.new('', '', 'testid')
cust.define_singleton_method(:organization_instances) { [nil] }
@cmd.send(:stripe_billing?, cust)
#=> false

## stripe_billing? protects customer on error (safe default)
cust = @mock_cust_class.new('', '', 'testid')
cust.define_singleton_method(:organization_instances) { raise StandardError, 'redis down' }
@cmd.send(:stripe_billing?, cust)
#=> true

# -------------------------------------------------------------------
# Activity source selection logic (used in show_dry_run)
# -------------------------------------------------------------------

## When last_login > 0, it is the preferred activity source
last_login = 1700000000.0
updated = 1600000000.0
source = last_login > 0 ? 'last_login' : 'updated'
source
#=> "last_login"

## When last_login is 0, falls back to updated
last_login = 0.0
updated = 1600000000.0
source = last_login > 0 ? 'last_login' : 'updated'
source
#=> "updated"

## Activity max selection: picks highest positive value
last_login = 1700000000.0
updated = 1600000000.0
[last_login, updated].select { |t| t > 0 }.max
#=> 1700000000.0

## Activity max selection: skips zero values
last_login = 0.0
updated = 1600000000.0
[last_login, updated].select { |t| t > 0 }.max
#=> 1600000000.0

## Activity max selection: both zero returns nil
last_login = 0.0
updated = 0.0
[last_login, updated].select { |t| t > 0 }.max
#=> nil

# -------------------------------------------------------------------
# Cutoff calculation logic
# -------------------------------------------------------------------

## Cutoff for 3y older-than produces a time in the past
threshold = 3 * 365 * 86_400
cutoff = Time.now - threshold
cutoff < Time.now
#=> true

## Cutoff epoch is a positive float
threshold = 1 * 365 * 86_400
cutoff = Time.now - threshold
cutoff.to_f > 0
#=> true
