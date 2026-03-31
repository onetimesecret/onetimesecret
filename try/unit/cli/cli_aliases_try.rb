# try/unit/cli/cli_aliases_try.rb
#
# frozen_string_literal: true

# Unit tests for CLI command aliases.
# Verifies that aliases register correctly and expose the same subcommands
# as their primary commands.
#
# Context: PR #2840 - Fix CLI subcommand display by using Dry::CLI aliases
#
# Run: bundle exec try try/unit/cli/cli_aliases_try.rb

require_relative '../../support/test_helpers'
require 'onetime/cli'

# Helper to access CLI registry internals
def cli_registry
  Onetime::CLI.instance_variable_get(:@commands)
end

def cli_root
  cli_registry.instance_variable_get(:@root)
end

def cli_children
  cli_root.instance_variable_get(:@children)
end

def cli_aliases
  cli_root.instance_variable_get(:@aliases)
end

def get_command_class(node)
  node.instance_variable_get(:@command)
end

def get_subcommands(node)
  node.instance_variable_get(:@children).keys
end

# -------------------------------------------------------------------
# Verify aliases are registered
# -------------------------------------------------------------------

## 'customer' alias is registered in CLI
cli_aliases.key?('customer')
#=> true

## 'workers' alias is registered in CLI
cli_aliases.key?('workers')
#=> true

## 'build' alias is registered in CLI
cli_aliases.key?('build')
#=> true

# -------------------------------------------------------------------
# Verify aliases point to same command class as primary
# -------------------------------------------------------------------

## 'customer' alias uses same command class as 'customers'
alias_cmd = get_command_class(cli_aliases['customer'])
primary_cmd = get_command_class(cli_children['customers'])
alias_cmd == primary_cmd
#=> true

## 'customer' alias command is CustomersCommand
get_command_class(cli_aliases['customer'])
#=> Onetime::CLI::CustomersCommand

## 'workers' alias uses same command class as 'worker'
alias_cmd = get_command_class(cli_aliases['workers'])
primary_cmd = get_command_class(cli_children['worker'])
alias_cmd == primary_cmd
#=> true

## 'workers' alias command is WorkerCommand
get_command_class(cli_aliases['workers'])
#=> Onetime::CLI::WorkerCommand

## 'build' alias uses same command class as 'version'
alias_cmd = get_command_class(cli_aliases['build'])
primary_cmd = get_command_class(cli_children['version'])
alias_cmd == primary_cmd
#=> true

## 'build' alias command is VersionCommand
get_command_class(cli_aliases['build'])
#=> Onetime::CLI::VersionCommand

# -------------------------------------------------------------------
# Verify subcommands are accessible via both primary and alias
# -------------------------------------------------------------------

## 'customers' has subcommands registered
subcommands = get_subcommands(cli_children['customers'])
subcommands.length > 0
#=> true

## 'customers' includes 'dates' subcommand
get_subcommands(cli_children['customers']).include?('dates')
#=> true

## 'customers' includes 'purge' subcommand
get_subcommands(cli_children['customers']).include?('purge')
#=> true

## 'customers' includes 'sync-auth-accounts' subcommand
get_subcommands(cli_children['customers']).include?('sync-auth-accounts')
#=> true

## 'customer' alias has same subcommands as 'customers'
alias_subs = get_subcommands(cli_aliases['customer'])
primary_subs = get_subcommands(cli_children['customers'])
alias_subs.sort == primary_subs.sort
#=> true

## 'workers' alias node matches 'worker' primary node structure
# Note: 'worker' command uses options, not subcommands, so both should have
# the same (empty) subcommand structure
alias_subs = get_subcommands(cli_aliases['workers'])
primary_subs = get_subcommands(cli_children['worker'])
alias_subs == primary_subs
#=> true

# -------------------------------------------------------------------
# Verify primary commands are properly registered (not replaced by aliases)
# -------------------------------------------------------------------

## 'customers' (primary) is registered as a child, not alias
cli_children.key?('customers')
#=> true

## 'worker' (primary) is registered as a child, not alias
cli_children.key?('worker')
#=> true

## 'version' (primary) is registered as a child, not alias
cli_children.key?('version')
#=> true

## 'customers' is NOT in aliases (it's the primary)
cli_aliases.key?('customers')
#=> false

## 'customer' is NOT in children (it's the alias)
cli_children.key?('customer')
#=> false

# -------------------------------------------------------------------
# Regression test: aliases don't create duplicate registrations
# -------------------------------------------------------------------

## Only one 'customers' entry exists (not duplicated)
cli_children.keys.count('customers')
#=> 1

## Only one 'customer' alias exists
cli_aliases.keys.count('customer')
#=> 1

# -------------------------------------------------------------------
# Verify command descriptions are accessible via both paths
# -------------------------------------------------------------------

## CustomersCommand has a description
Onetime::CLI::CustomersCommand.respond_to?(:description)
#=> true

## WorkerCommand has a description
Onetime::CLI::WorkerCommand.respond_to?(:description)
#=> true

## VersionCommand has a description
Onetime::CLI::VersionCommand.respond_to?(:description)
#=> true
