# try/unit/cli/housekeeping_command_try.rb
#
# frozen_string_literal: true

# Unit tests for the housekeeping CLI commands. Verifies registration,
# Dry::CLI inheritance, argument/option declarations. Runtime behavior is
# covered separately by try/jobs/housekeeping_job_try.rb.
#
# Run: bundle exec try try/unit/cli/housekeeping_command_try.rb

require_relative '../../support/test_helpers'
require 'onetime/cli'

# TRYOUTS

## HousekeepingCommand exists and inherits from Command
Onetime::CLI::HousekeepingCommand.ancestors.include?(Onetime::CLI::Command)
#=> true

## HousekeepingCommand is a Dry::CLI::Command
Onetime::CLI::HousekeepingCommand.new.is_a?(Dry::CLI::Command)
#=> true

## HousekeepingListCommand exists and inherits from Command
Onetime::CLI::HousekeepingListCommand.ancestors.include?(Onetime::CLI::Command)
#=> true

## HousekeepingRunCommand exists and inherits from Command
Onetime::CLI::HousekeepingRunCommand.ancestors.include?(Onetime::CLI::Command)
#=> true

## housekeeping is registered in the dry-cli registry
Onetime::CLI.get(['housekeeping']).command == Onetime::CLI::HousekeepingCommand
#=> true

## housekeeping list is registered as a subcommand
Onetime::CLI.get(['housekeeping', 'list']).command == Onetime::CLI::HousekeepingListCommand
#=> true

## housekeeping run is registered as a subcommand
Onetime::CLI.get(['housekeeping', 'run']).command == Onetime::CLI::HousekeepingRunCommand
#=> true

## housekeeping run declares a required model argument
arg = Onetime::CLI::HousekeepingRunCommand.arguments.find { |a| a.name == :model }
[arg.nil?, arg && arg.required?]
#=> [false, true]

## housekeeping run declares an optional chore argument
arg = Onetime::CLI::HousekeepingRunCommand.arguments.find { |a| a.name == :chore }
[arg.nil?, arg && arg.required?]
#=> [false, false]

## housekeeping run declares a --limit integer option
opt = Onetime::CLI::HousekeepingRunCommand.options.find { |o| o.name == :limit }
[opt.nil?, opt && opt.type]
#=> [false, :integer]
