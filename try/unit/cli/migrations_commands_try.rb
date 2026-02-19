# try/unit/cli/migrations_commands_try.rb
#
# Unit tests for migration CLI commands
#
# Run: bundle exec try try/unit/cli/migrations_commands_try.rb

require_relative '../../support/test_helpers'
require 'onetime/cli'

# Test command classes exist and inherit from Command

## BackfillEmailHashCommand exists
defined?(Onetime::CLI::BackfillEmailHashCommand)
#=> "constant"

## BackfillStripeEmailHashCommand exists
defined?(Onetime::CLI::BackfillStripeEmailHashCommand)
#=> "constant"

## BackfillEmailHashCommand inherits from Command
Onetime::CLI::BackfillEmailHashCommand.ancestors.include?(Onetime::CLI::Command)
#=> true

## BackfillStripeEmailHashCommand inherits from Command
Onetime::CLI::BackfillStripeEmailHashCommand.ancestors.include?(Onetime::CLI::Command)
#=> true

## BackfillEmailHashCommand is a Dry::CLI::Command
Onetime::CLI::BackfillEmailHashCommand.ancestors.include?(Dry::CLI::Command)
#=> true

## BackfillStripeEmailHashCommand has rate limit constant
Onetime::CLI::BackfillStripeEmailHashCommand::BATCH_DELAY_SECONDS
#=> 0.1

## BackfillStripeEmailHashCommand rate limit is conservative (10 req/sec or less)
Onetime::CLI::BackfillStripeEmailHashCommand::BATCH_DELAY_SECONDS >= 0.1
#=> true

## BackfillEmailHashCommand can be instantiated
cmd = Onetime::CLI::BackfillEmailHashCommand.new
cmd.is_a?(Dry::CLI::Command)
#=> true

## BackfillStripeEmailHashCommand can be instantiated
cmd = Onetime::CLI::BackfillStripeEmailHashCommand.new
cmd.is_a?(Dry::CLI::Command)
#=> true

## BackfillStripeEmailHashCommand has MAX_RATE_LIMIT_RETRIES constant
Onetime::CLI::BackfillStripeEmailHashCommand::MAX_RATE_LIMIT_RETRIES
#=> 3

## rate_limit_retries is initialized outside begin block (scoping fix #2471)
# Verify via source inspection: rate_limit_retries = 0 is at method level,
# begin block starts after it, so retry does not re-initialize the counter.
source_file = File.join(ENV['ONETIME_HOME'], 'lib/onetime/cli/migrations/backfill_stripe_email_hash_command.rb')
source = File.read(source_file)
method_match = source[/def process_stripe_customer.*?^      end/m]
lines = method_match.lines.map(&:strip)
init_idx = lines.index { |l| l.start_with?('rate_limit_retries = 0') }
begin_idx = lines.index { |l| l == 'begin' }
init_idx < begin_idx
#=> true
