# try/unit/cli/cli_aliases_help_output_try.rb
#
# frozen_string_literal: true

# Integration tests for CLI alias help output.
# Verifies that alias commands produce equivalent help output to primary commands,
# including subcommand visibility.
#
# Context: PR #2840 - Fix CLI subcommand display by using Dry::CLI aliases
#
# Run: bundle exec try try/unit/cli/cli_aliases_help_output_try.rb

require_relative '../../support/test_helpers'
require 'open3'
require 'stringio'
require 'onetime/cli'

# Help output for a command, from the Dry::CLI registry in this process:
# starting bin/ots for each one costs seconds apiece. --help prints the
# banner to `out` and then exits, so the exit is caught here. The banner
# names the program after $PROGRAM_NAME, which is 'ots' under bin/ots.
def help_output(*args)
  out           = StringIO.new
  err           = StringIO.new
  program_name  = $PROGRAM_NAME
  $PROGRAM_NAME = 'ots'
  begin
    Dry::CLI.new(Onetime::CLI).call(arguments: [*args, '--help'], out: out, err: err)
  rescue SystemExit
    # --help exits 0 after printing the banner
  ensure
    $PROGRAM_NAME = program_name
  end
  out.string.empty? ? err.string : out.string
end

# Helper to run the real executable and capture output (smoke test only)
def run_cli(*args)
  env = { 'ONETIME_HOME' => ENV['ONETIME_HOME'] }
  cmd = ['bin/ots', *args]
  stdout, stderr, _status = Open3.capture3(env, *cmd)
  # Dry::CLI outputs help to stdout
  stdout.empty? ? stderr : stdout
end

# Helper to extract subcommands section from help output
def extract_subcommands(help_output)
  return [] unless help_output
  # Find lines between "Subcommands:" header and next section (Options: or end)
  in_subcommands = false
  subcommands = []
  help_output.each_line do |line|
    if line.strip.start_with?('Subcommands:')
      in_subcommands = true
      next
    elsif line.strip.start_with?('Options:') || line.strip.start_with?('Arguments:')
      in_subcommands = false
    elsif in_subcommands && line.strip =~ /^(\S+)\s+#/
      subcommands << $1
    end
  end
  subcommands.sort
end

# Helper to extract description from help output
def extract_description(help_output)
  return nil unless help_output
  help_output.match(/Description:\s*\n\s*(.+)/m)&.captures&.first&.strip&.split("\n")&.first
end

# Cache help outputs for all commands/aliases we test
@help_cache = {
  customers: help_output('customers'),
  customer: help_output('customer'),
  worker: help_output('worker'),
  workers: help_output('workers'),
  version: help_output('version'),
  build: help_output('build'),
}

# -------------------------------------------------------------------
# customers / customer alias equivalence
# -------------------------------------------------------------------

## 'ots customers --help' shows subcommands
@help_cache[:customers].include?('Subcommands:')
#=> true

## 'ots customer --help' shows subcommands (alias preserves subcommands)
@help_cache[:customer].include?('Subcommands:')
#=> true

## 'customers' help includes 'dates' subcommand
@help_cache[:customers].include?('dates')
#=> true

## 'customer' help includes 'dates' subcommand
@help_cache[:customer].include?('dates')
#=> true

## 'customers' help includes 'purge' subcommand
@help_cache[:customers].include?('purge')
#=> true

## 'customer' help includes 'purge' subcommand
@help_cache[:customer].include?('purge')
#=> true

## 'customers' help includes 'sync-auth-accounts' subcommand
@help_cache[:customers].include?('sync-auth-accounts')
#=> true

## 'customer' help includes 'sync-auth-accounts' subcommand
@help_cache[:customer].include?('sync-auth-accounts')
#=> true

## 'customers' and 'customer' have same subcommands listed
extract_subcommands(@help_cache[:customers]) == extract_subcommands(@help_cache[:customer])
#=> true

## 'customers' and 'customer' have same description
extract_description(@help_cache[:customers]) == extract_description(@help_cache[:customer])
#=> true

## 'customers' description is correct
extract_description(@help_cache[:customers])
#=> "Manage customer records"

# -------------------------------------------------------------------
# worker / workers alias equivalence
# -------------------------------------------------------------------

## 'ots worker --help' shows command info
@help_cache[:worker].include?('Command:')
#=> true

## 'ots workers --help' shows command info (alias works)
@help_cache[:workers].include?('Command:')
#=> true

## 'worker' and 'workers' have same description
extract_description(@help_cache[:worker]) == extract_description(@help_cache[:workers])
#=> true

## 'worker' description is correct
extract_description(@help_cache[:worker])
#=> "Start Sneakers job workers"

## 'worker' help includes --queues option
@help_cache[:worker].include?('--queues')
#=> true

## 'workers' help includes --queues option
@help_cache[:workers].include?('--queues')
#=> true

# -------------------------------------------------------------------
# version / build alias equivalence
# -------------------------------------------------------------------

## 'ots version --help' shows command info
@help_cache[:version].include?('Command:')
#=> true

## 'ots build --help' shows command info (alias works)
@help_cache[:build].include?('Command:')
#=> true

## 'version' and 'build' have same description
extract_description(@help_cache[:version]) == extract_description(@help_cache[:build])
#=> true

# -------------------------------------------------------------------
# Verify command name reflects what was invoked
# -------------------------------------------------------------------

## 'ots customers --help' shows "ots customers" in Command line
@help_cache[:customers].include?('ots customers')
#=> true

## 'ots customer --help' shows "ots customer" in Command line (not customers)
@help_cache[:customer].include?('ots customer')
#=> true

## 'ots worker --help' shows "ots worker" in Command line
@help_cache[:worker].include?('ots worker')
#=> true

## 'ots workers --help' shows "ots workers" in Command line (not worker)
@help_cache[:workers].include?('ots workers')
#=> true

# -------------------------------------------------------------------
# Smoke test: the executable prints the same help as the registry here
# -------------------------------------------------------------------

## 'bin/ots customer --help' as a separate process matches the in-process help
run_cli('customer', '--help') == @help_cache[:customer]
#=> true
