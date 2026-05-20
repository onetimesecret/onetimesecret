# try/unit/cli/housekeeping_command_try.rb
#
# frozen_string_literal: true

# Unit tests for the housekeeping CLI commands. Verifies the command classes
# are defined, inherit from the right bases, and can be instantiated.
# Runtime behavior (perform, stats, batching) is covered separately by
# try/jobs/housekeeping_job_try.rb.
#
# Run: bundle exec try try/unit/cli/housekeeping_command_try.rb

require_relative '../../support/test_helpers'
require 'onetime/cli'

# TRYOUTS

## HousekeepingCommand exists
defined?(Onetime::CLI::HousekeepingCommand)
#=> "constant"

## HousekeepingCommand inherits from Command
Onetime::CLI::HousekeepingCommand.ancestors.include?(Onetime::CLI::Command)
#=> true

## HousekeepingCommand is a Dry::CLI::Command
Onetime::CLI::HousekeepingCommand.new.is_a?(Dry::CLI::Command)
#=> true

## HousekeepingListCommand exists
defined?(Onetime::CLI::HousekeepingListCommand)
#=> "constant"

## HousekeepingListCommand inherits from Command
Onetime::CLI::HousekeepingListCommand.ancestors.include?(Onetime::CLI::Command)
#=> true

## HousekeepingListCommand is a Dry::CLI::Command
Onetime::CLI::HousekeepingListCommand.new.is_a?(Dry::CLI::Command)
#=> true

## HousekeepingRunCommand exists
defined?(Onetime::CLI::HousekeepingRunCommand)
#=> "constant"

## HousekeepingRunCommand inherits from Command
Onetime::CLI::HousekeepingRunCommand.ancestors.include?(Onetime::CLI::Command)
#=> true

## HousekeepingRunCommand is a Dry::CLI::Command
Onetime::CLI::HousekeepingRunCommand.new.is_a?(Dry::CLI::Command)
#=> true
