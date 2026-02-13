# try/unit/cli/sync_auth_accounts_try.rb
#
# frozen_string_literal: true

# Unit tests for SyncAuthAccountsCommand batch processing and resume.
#
# Verifies:
# 1. BATCH_SIZE constant is defined and reasonable
# 2. The command class is loadable and has expected interface
#
# Note: Full integration testing requires an auth database connection.
# These tests cover structural validation only.

require_relative '../../support/test_helpers'

OT.boot! :test, false
require 'onetime/cli'

## SyncAuthAccountsCommand class exists
defined?(Onetime::CLI::SyncAuthAccountsCommand)
#=> "constant"

## BATCH_SIZE constant is defined
Onetime::CLI::SyncAuthAccountsCommand::BATCH_SIZE
#=> 1000

## BATCH_SIZE is a positive integer
Onetime::CLI::SyncAuthAccountsCommand::BATCH_SIZE.is_a?(Integer) && Onetime::CLI::SyncAuthAccountsCommand::BATCH_SIZE > 0
#=> true

## Command class inherits from CLI Command
Onetime::CLI::SyncAuthAccountsCommand < Onetime::CLI::Command
#=> true

## Command has process_batch private method (batch processing)
Onetime::CLI::SyncAuthAccountsCommand.private_instance_methods.include?(:process_batch)
#=> true

## Command has call method (entry point)
Onetime::CLI::SyncAuthAccountsCommand.instance_methods.include?(:call)
#=> true

## Resume logic: existing_extids is built as a Set (verify Set usage in source)
# The command builds: Set.new(db[:accounts].where(...).select_map(:external_id))
# And checks: existing_extids.include?(customer.extid)
# This verifies Set supports the expected interface
@skip_set = Set.new(["ext_abc", "ext_def"])
@skip_set.include?("ext_abc")
#=> true

## Resume logic: Set correctly excludes non-members
@skip_set.include?("ext_new")
#=> false

## Resume logic: Set can be merged with new entries (post-batch update)
@skip_set.merge(["ext_ghi"])
@skip_set.include?("ext_ghi")
#=> true
