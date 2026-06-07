# try/unit/cli/billing/update_stripe_metadata_try.rb
#
# frozen_string_literal: true

# Tests for CLI command: bin/ots billing update-stripe-metadata
#
# Command options:
#   --key KEY      Metadata key (required). Alone = read mode.
#   --value VAL    New value (triggers write mode)
#   --unset        Remove the key (triggers write mode, mutually exclusive with --value)
#   --apply        Apply changes (default dry-run)
#   --org EXTID    Update a single org only
#   --sleep MS     Throttle Stripe API calls (default 50ms)
#
# Tested here: command shape, option validation, truncation helper,
# orphan reporting, and registry wiring. Live Stripe behavior (merge
# semantics, 429 handling) is verified manually per the issue's
# acceptance criteria.
#
# Run: bundle exec try try/unit/cli/billing/update_stripe_metadata_try.rb

require_relative '../../../support/test_helpers'
require 'onetime/cli'

OT.boot! :cli

# Clean Redis for fresh test run
Familia.dbclient.flushdb
OT.info 'Cleaned Redis for fresh test run'

@test_suffix = "#{Familia.now.to_i}_#{rand(10_000)}"

# -------------------------------------------------------------------
# Command class basics
# -------------------------------------------------------------------

## Command class exists
defined?(Onetime::CLI::BillingUpdateStripeMetadataCommand)
#=> 'constant'

## Inherits from base Command
Onetime::CLI::BillingUpdateStripeMetadataCommand.ancestors.include?(Onetime::CLI::Command)
#=> true

## Includes BillingHelpers (for with_stripe_retry, stripe_configured?)
Onetime::CLI::BillingUpdateStripeMetadataCommand.ancestors.include?(Onetime::CLI::BillingHelpers)
#=> true

## Can be instantiated
@cmd = Onetime::CLI::BillingUpdateStripeMetadataCommand.new
@cmd.is_a?(Dry::CLI::Command)
#=> true

## Registered under 'billing update-stripe-metadata'
registry          = Onetime::CLI.get(['billing', 'update-stripe-metadata'])
registered_class  = registry.respond_to?(:command) ? registry.command : registry
registered_class == Onetime::CLI::BillingUpdateStripeMetadataCommand
#=> true

# -------------------------------------------------------------------
# Option validation
# -------------------------------------------------------------------

## Missing --key returns false
@capture = StringIO.new
@orig    = $stdout
$stdout  = @capture
@result  = @cmd.send(:validate_options!, key: nil, value: 'x', unset: false)
$stdout  = @orig
@result
#=> false

## Missing --key prints helpful error
@capture.string.include?('--key is required')
#=> true

## Empty --key returns false
@capture = StringIO.new
$stdout  = @capture
@result  = @cmd.send(:validate_options!, key: '   ', value: 'x', unset: false)
$stdout  = @orig
@result
#=> false

## --unset combined with --value returns false
@capture = StringIO.new
$stdout  = @capture
@result  = @cmd.send(:validate_options!, key: 'region', value: 'us', unset: true)
$stdout  = @orig
@result
#=> false

## Mutex error message is clear
@capture.string.include?('mutually exclusive')
#=> true

## --key alone (read mode) passes validation
@result = @cmd.send(:validate_options!, key: 'region', value: nil, unset: false)
@result
#=> true

## read_only_mode? returns true when no value and no unset
@cmd.send(:read_only_mode?, value: nil, unset: false)
#=> true

## read_only_mode? returns false when value is set
@cmd.send(:read_only_mode?, value: 'us-east', unset: false)
#=> false

## read_only_mode? returns false when unset is true
@cmd.send(:read_only_mode?, value: nil, unset: true)
#=> false

## --key + --value passes validation
@capture = StringIO.new
$stdout  = @capture
@result  = @cmd.send(:validate_options!, key: 'region', value: 'us-east', unset: false)
$stdout  = @orig
@result
#=> true

## --key + --unset (no --value) passes validation
@result = @cmd.send(:validate_options!, key: 'region', value: nil, unset: true)
@result
#=> true

## Negative --sleep returns false
@capture = StringIO.new
$stdout  = @capture
@result  = @cmd.send(:validate_options!, key: 'region', value: 'us', unset: false, sleep: -10)
$stdout  = @orig
@result
#=> false

## Negative --sleep prints helpful error
@capture.string.include?('non-negative')
#=> true

# -------------------------------------------------------------------
# truncate helper
# -------------------------------------------------------------------

## truncate returns '-' for nil
@cmd.send(:truncate, nil)
#=> '-'

## truncate returns '-' for empty string
@cmd.send(:truncate, '')
#=> '-'

## truncate passes through short strings unchanged
@cmd.send(:truncate, 'us-east')
#=> 'us-east'

## truncate shortens long strings with ellipsis
@cmd.send(:truncate, 'this-is-a-very-long-value-here', length: 20)
#=> 'this-is-a-very-lo...'

## truncate respects custom length
@cmd.send(:truncate, 'abcdefghij', length: 5)
#=> 'ab...'

# -------------------------------------------------------------------
# Single-org branch: missing org reports cleanly
# -------------------------------------------------------------------

## process_single_organization with nonexistent extid prints not-found and returns
@capture = StringIO.new
$stdout  = @capture
@cmd.instance_variable_set(:@sleep_interval, 0.0)
@cmd.instance_variable_set(:@read_only, false)
@cmd.send(
  :process_single_organization,
  "missing_#{@test_suffix}",
  key: 'region',
  value: 'us-east',
  unset: false,
  apply: false,
)
$stdout = @orig
@capture.string.include?('No organization found')
#=> true

# -------------------------------------------------------------------
# Single-org branch: org without a Stripe customer is reported
# -------------------------------------------------------------------

## Create an org with no Stripe customer link
@bare_owner = Onetime::Customer.create!(email: "bare_#{@test_suffix}@test.com")
@bare_org   = Onetime::Organization.create!('Bare Org', @bare_owner, "bare_#{@test_suffix}@acme.com")
@bare_org.stripe_customer_id.to_s.empty?
#=> true

## process_single_organization on an org without Stripe customer reports cleanly
@capture = StringIO.new
$stdout  = @capture
@cmd.instance_variable_set(:@read_only, false)
@cmd.send(
  :process_single_organization,
  @bare_org.extid,
  key: 'region',
  value: 'us-east',
  unset: false,
  apply: false,
)
$stdout = @orig
@capture.string.include?('no Stripe customer linked')
#=> true

# -------------------------------------------------------------------
# All-orgs branch: orphaned index entry surfaces in summary
# -------------------------------------------------------------------

## Inject a dangling (stripe_customer_id -> bogus org_objid) into the index
@bogus_objid       = "ghost_org_#{@test_suffix}"
@bogus_customer_id = "cus_ghost_#{@test_suffix}"
Onetime::Organization.stripe_customer_id_index[@bogus_customer_id] = @bogus_objid
Onetime::Organization.stripe_customer_id_index[@bogus_customer_id]
#=> @bogus_objid

## process_all_organizations classifies the orphan row without contacting Stripe
@capture = StringIO.new
$stdout  = @capture
@cmd.instance_variable_set(:@read_only, false)
@cmd.send(
  :process_all_organizations,
  key: 'region',
  value: 'us-east',
  unset: false,
  apply: false,
)
$stdout = @orig
@out_str = @capture.string
@out_str.include?('orphaned:') && @out_str.include?('ERROR: org not found')
#=> true

## Summary reports at least one orphaned row
@out_str.match(/Orphaned:\s+(\d+)/)[1].to_i >= 1
#=> true

## Dry-run footer not shown when no updates pending (only orphans)
@out_str.include?('Run with --apply')
#=> false

## Header shows the SET action
@out_str.include?('SET region=us-east')
#=> true

## Re-run with --unset shows UNSET action in header
@capture = StringIO.new
$stdout  = @capture
@cmd.instance_variable_set(:@read_only, false)
@cmd.send(
  :process_all_organizations,
  key: 'region',
  value: nil,
  unset: true,
  apply: false,
)
$stdout = @orig
@capture.string.include?('UNSET region')
#=> true

# -------------------------------------------------------------------
# Teardown
# -------------------------------------------------------------------

# Remove the dangling index entry we injected
Onetime::Organization.stripe_customer_id_index.remove(@bogus_customer_id)

[@bare_org].compact.each do |org|
  org.destroy! if org.respond_to?(:destroy!) && org.exists?
rescue StandardError
  nil
end

[@bare_owner].compact.each do |cust|
  cust.destroy! if cust.respond_to?(:destroy!) && cust.exists?
rescue StandardError
  nil
end

OT.info 'Teardown complete'
