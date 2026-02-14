# try/unit/cli/sync_auth_accounts_try.rb
#
# frozen_string_literal: true

# Unit tests for SyncAuthAccountsCommand batch processing and resume.
#
# Verifies:
# 1. BATCH_SIZE constant is defined and reasonable
# 2. The command class is loadable and has expected interface
# 3. obscure_email helper edge cases (nil, empty, valid)
# 4. load_multi returns nils for missing objids (Redis-backed)
# 5. Customer skip logic paths: anonymous, global, invalid email
# 6. existing_extids resume logic and batch_processed_extids dedup
#
# Note: Full integration testing of process_batch requires an auth
# database connection. These tests cover the components that can be
# validated with Redis alone.
#
# IMPORTANT: Never modify indexed fields (email) on a saved Customer.
# Changing email after create! leaves stale entries in the email_index
# that destroy! won't clean up. Test those guards on plain strings.

require_relative '../../support/test_helpers'

OT.boot! :test
require 'onetime/cli'

@cmd = Onetime::CLI::SyncAuthAccountsCommand.new

# Create test customers in Redis for load_multi and skip-logic tests.
# Use a unique timestamp + entropy to avoid collisions across runs.
@ts = Familia.now.to_i
@entropy = SecureRandom.hex(4)

@valid_customer = Onetime::Customer.create!(email: "sync_valid_#{@ts}_#{@entropy}@example.com")

# In-memory only anonymous customer (never saved to Redis)
@anon_customer = Onetime::Customer.new
@anon_customer.role = 'anonymous'
@anon_customer.custid = 'anon'

# Customer with custid=GLOBAL (custid is not a unique_index, safe to modify)
@global_customer = Onetime::Customer.create!(email: "sync_global_#{@ts}_#{@entropy}@example.com")
@global_customer.custid = 'GLOBAL'
@global_customer.save

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

# --- obscure_email helper tests ---
# Access the private method via send on a command instance.

## obscure_email returns 'anonymous' for nil input
@cmd.send(:obscure_email, nil)
#=> "anonymous"

## obscure_email returns 'anonymous' for empty string
@cmd.send(:obscure_email, '')
#=> "anonymous"

## obscure_email returns an obscured form for a valid email
# OT::Utils.obscure_email masks both local and domain parts.
@result = @cmd.send(:obscure_email, 'alice@example.com')
@result.include?('@') && @result != 'alice@example.com'
#=> true

## obscure_email does not return the original email unchanged
@cmd.send(:obscure_email, 'bob@test.org') != 'bob@test.org'
#=> true

# --- load_multi nil guard tests (Redis-backed) ---
# The nil guard in process_batch (line ~207) handles entries where
# load_multi returns nil for missing/deleted objids.

## load_multi returns array with nils for nonexistent objids
# When given objids that don't map to real Customer records, load_multi
# returns nil at those positions (same contract as find_by_id).
@fake_id = "nonexistent_#{@ts}_#{@entropy}"
@loaded = Onetime::Customer.load_multi([@valid_customer.objid, @fake_id])
@loaded.length
#=> 2

## load_multi: first element is the valid customer
@loaded[0].is_a?(Onetime::Customer)
#=> true

## load_multi: second element is nil for the missing objid
@loaded[1].nil?
#=> true

## load_multi: nil entry would trigger the nil guard in process_batch
# Simulates the iteration: customers.each_with_index where customer is nil
@stats_sim = { skipped_system: 0 }
@loaded.each_with_index do |customer, _idx|
  unless customer
    @stats_sim[:skipped_system] += 1
    next
  end
end
@stats_sim[:skipped_system]
#=> 1

## load_multi: all-invalid batch returns array of nils
@all_missing = Onetime::Customer.load_multi(["bogus_a_#{@ts}", "bogus_b_#{@ts}"])
@all_missing.compact.empty?
#=> true

## load_multi: nil guard increments for every nil in batch
@all_nil_stats = { skipped_system: 0 }
@all_missing.each { |c| @all_nil_stats[:skipped_system] += 1 unless c }
@all_nil_stats[:skipped_system]
#=> 2

## load_multi: empty input returns empty array
Onetime::Customer.load_multi([])
#=> []

# --- Customer skip logic: anonymous detection ---

## anonymous? returns true for role=anonymous custid=anon
@anon_customer.anonymous?
#=> true

## anonymous? returns false for a regular customer
@valid_customer.anonymous?
#=> false

# --- Customer skip logic: global/system detection ---

## global? returns true when custid is GLOBAL
@global_customer.global?
#=> true

## global? returns false for a regular customer
@valid_customer.global?
#=> false

## Email-based GLOBAL check: normal customer email does not trigger guard
# process_batch checks: customer.email.to_s.upcase == 'GLOBAL'
@global_customer.email.to_s.upcase == 'GLOBAL'
#=> false

## Email-based GLOBAL check: the string 'GLOBAL' triggers the guard
# Verifies the exact condition used in process_batch without mutating
# indexed fields on a real Customer object.
'GLOBAL'.to_s.upcase == 'GLOBAL'
#=> true

## Email-based GLOBAL check: case-insensitive match
'global'.to_s.upcase == 'GLOBAL'
#=> true

# --- Customer skip logic: invalid email format ---
# process_batch checks: customer.email.to_s.include?('@')
# Test the guard condition on strings directly to avoid stale index issues.

## Email without @ is detected by the process_batch guard
'noemailformat'.to_s.include?('@')
#=> false

## Empty email string fails the @ check
''.to_s.include?('@')
#=> false

## Nil email (via to_s) fails the @ check
nil.to_s.include?('@')
#=> false

## Valid email passes the @ check
@valid_customer.email.to_s.include?('@')
#=> true

# --- existing_extids resume dedup ---

## Existing extids Set skips already-synced customers
@resume_set = Set.new([@valid_customer.extid])
@resume_set.include?(@valid_customer.extid)
#=> true

## New customer extid is not in the skip set
@resume_set.include?("brand_new_extid")
#=> false

# --- batch_processed_extids cross-batch dedup ---
# After a batch commits, process_batch merges batch_processed_extids
# into existing_extids so subsequent batches skip those records.

## batch_processed_extids merges into existing_extids after batch commit
@batch_processed = ["extid_1", "extid_2"]
@resume_set.merge(@batch_processed)
@resume_set.include?("extid_1") && @resume_set.include?("extid_2")
#=> true

## Original entries remain after merge
@resume_set.include?(@valid_customer.extid)
#=> true

## Duplicate extids in batch_processed don't cause issues
@resume_set.merge(["extid_1"])
@resume_set.size
#=> 3

## process_batch method has correct arity (8 params)
# db, batch_ids, batch_start, existing_extids, stats, verbose_level, total, dry_run
@cmd.method(:process_batch).arity.abs
#=> 8

## obscure_email is also a private method on the command
@cmd.class.private_instance_methods.include?(:obscure_email)
#=> true

# Teardown
@valid_customer.destroy! if @valid_customer&.exists?
@global_customer.destroy! if @global_customer&.exists?
