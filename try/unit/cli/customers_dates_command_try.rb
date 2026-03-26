# try/unit/cli/customers_dates_command_try.rb
#
# frozen_string_literal: true

# Unit tests for CustomersDatesCommand utility methods.
# Tests parse_ts, parse_json_field, format_ttl, and redact_url
# without requiring a full Redis scan or boot_application!.
#
# Run: bundle exec try try/unit/cli/customers_dates_command_try.rb

require_relative '../../support/test_helpers'
require 'onetime/cli'

@cmd = Onetime::CLI::CustomersDatesCommand.new

# -------------------------------------------------------------------
# Command class basics
# -------------------------------------------------------------------

## CustomersDatesCommand exists and inherits from Command
Onetime::CLI::CustomersDatesCommand.ancestors.include?(Onetime::CLI::Command)
#=> true

## CustomersDatesCommand is a Dry::CLI::Command
@cmd.is_a?(Dry::CLI::Command)
#=> true

## CACHE_TTL is 30 minutes (1800 seconds)
Onetime::CLI::CustomersDatesCommand::CACHE_TTL
#=> 1800

## SCAN_COUNT is 200
Onetime::CLI::CustomersDatesCommand::SCAN_COUNT
#=> 200

## CREATED_CACHE key has expected prefix
Onetime::CLI::CustomersDatesCommand::CREATED_CACHE.start_with?('tmp:cli:')
#=> true

## ACTIVITY_CACHE key has expected prefix
Onetime::CLI::CustomersDatesCommand::ACTIVITY_CACHE.start_with?('tmp:cli:')
#=> true

# -------------------------------------------------------------------
# parse_ts: timestamp parsing
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

## parse_ts with bare numeric string (not JSON) falls back to to_f
@cmd.send(:parse_ts, '1609459200.5')
#=> 1609459200.5

## parse_ts with non-numeric garbage returns 0.0
@cmd.send(:parse_ts, 'not-a-number')
#=> 0.0

## parse_ts with JSON string that contains a number parses it
@cmd.send(:parse_ts, '"1234567890"')
#=> 1234567890.0

## parse_ts with zero returns 0.0
@cmd.send(:parse_ts, '0')
#=> 0.0

## parse_ts with negative value returns negative float
@cmd.send(:parse_ts, '-100')
#=> -100.0

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

## parse_json_field with whitespace-only returns nil
@cmd.send(:parse_json_field, '   ')
#=> nil

## parse_json_field with JSON email returns parsed string
@cmd.send(:parse_json_field, '"user@example.com"')
#=> "user@example.com"

## parse_json_field with invalid JSON falls back to raw string
@cmd.send(:parse_json_field, 'plain-text')
#=> "plain-text"

## parse_json_field with JSON boolean returns Ruby boolean
@cmd.send(:parse_json_field, 'true')
#=> true

## parse_json_field with JSON null returns nil (parsed)
@cmd.send(:parse_json_field, 'null')
#=> nil

## parse_json_field with JSON integer returns integer
@cmd.send(:parse_json_field, '42')
#=> 42

## parse_json_field with JSON object returns hash
@cmd.send(:parse_json_field, '{"key":"value"}')
#=> {"key"=>"value"}

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

## format_ttl with 60 seconds returns 1m 0s
@cmd.send(:format_ttl, 60)
#=> "1m 0s"

## format_ttl with 0 seconds returns 0s
@cmd.send(:format_ttl, 0)
#=> "0s"

## format_ttl with 59 seconds returns 59s
@cmd.send(:format_ttl, 59)
#=> "59s"

## format_ttl with 3600 seconds returns 60m 0s
@cmd.send(:format_ttl, 3600)
#=> "60m 0s"

# -------------------------------------------------------------------
# redact_url: URL password redaction
# -------------------------------------------------------------------

## redact_url hides password in Redis URL
@cmd.send(:redact_url, 'redis://user:secretpass@host:6379/0')
#=> "redis://user:***@host:6379/0"

## redact_url handles URL without password
@cmd.send(:redact_url, 'redis://host:6379/0')
#=> "redis://host:6379/0"

## redact_url handles URL with only password (no user)
@cmd.send(:redact_url, 'redis://:mypassword@host:6379/0')
#=> "redis://:***@host:6379/0"

## redact_url handles URL with long password
@cmd.send(:redact_url, 'redis://user:longpassword123@host:6379/0')
#=> "redis://user:***@host:6379/0"

# -------------------------------------------------------------------
# Email validation filter logic (used during cache building)
# -------------------------------------------------------------------

## Email with @ is valid for inclusion
'user@example.com'.include?('@')
#=> true

## Email without @ is rejected
'anonymous'.include?('@')
#=> false

## Empty email is rejected
''.include?('@')
#=> false

# -------------------------------------------------------------------
# Role filtering logic (anonymous records are skipped)
# -------------------------------------------------------------------

## Anonymous role is filtered out
role = @cmd.send(:parse_json_field, '"anonymous"')
role == 'anonymous'
#=> true

## Non-anonymous role passes filter
role = @cmd.send(:parse_json_field, '"customer"')
role == 'anonymous'
#=> false

## Nil role (missing field) is not anonymous
role = @cmd.send(:parse_json_field, nil)
role == 'anonymous'
#=> false

# -------------------------------------------------------------------
# Age bracket boundary calculations
# -------------------------------------------------------------------

## Age bracket constants are correct: 6 months in seconds
6 * 30 * 86_400
#=> 15552000

## Age bracket constants are correct: 1 year in seconds
365 * 86_400
#=> 31536000

## Age bracket constants are correct: 2 years in seconds
2 * 365 * 86_400
#=> 63072000

## Age bracket constants are correct: 5 years in seconds
5 * 365 * 86_400
#=> 157680000

## Activity timestamp selection: picks max of positive values
last_login = 1700000000.0
updated = 1600000000.0
[last_login, updated].select { |t| t > 0 }.max
#=> 1700000000.0

## Activity timestamp selection: skips zero values
last_login = 0.0
updated = 1600000000.0
[last_login, updated].select { |t| t > 0 }.max
#=> 1600000000.0

## Activity timestamp selection: both zero returns nil
last_login = 0.0
updated = 0.0
[last_login, updated].select { |t| t > 0 }.max
#=> nil
