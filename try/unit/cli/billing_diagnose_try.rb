# try/unit/cli/billing_diagnose_try.rb
#
# frozen_string_literal: true

# Tests for BillingDiagnoseCommand CLI integration.
# Exercises the command via Open3.capture3 against `bin/ots billing diagnose`
# to cover: help output, missing-argument handling, customer-not-found path,
# billing-disabled standalone entitlements, and the --entitlement flag.
#
# Run: bundle exec try try/unit/cli/billing_diagnose_try.rb

require 'open3'

# Shared environment for all CLI invocations. Uses the test Redis port (2121)
# and suppresses Familia debug output.
@env = {
  'FAMILIA_DEBUG' => '0',
  'RACK_ENV' => 'test',
  'VALKEY_URL' => 'valkey://127.0.0.1:2121/0',
  'REDIS_URL' => 'redis://127.0.0.1:2121/0',
  'ONETIME_HOME' => ENV['ONETIME_HOME'] || File.expand_path(File.join(__dir__, '..', '..', '..'))
}

# Helper to invoke `bin/ots` and return [stdout, stderr, exit_status]
def run_ots(*args)
  cmd = [File.join(@env['ONETIME_HOME'], 'bin/ots'), *args]
  Open3.capture3(@env, *cmd)
end

# Cache outputs that multiple test cases reference
@help_out, @help_err, @help_status = run_ots('billing', 'diagnose', '--help')
@noarg_out, @noarg_err, @noarg_status = run_ots('billing', 'diagnose')
@notfound_out, @notfound_err, @notfound_status = run_ots('billing', 'diagnose', 'nonexistent_tryout_xyz_99@example.com')
@entitlement_out, @entitlement_err, @entitlement_status = run_ots(
  'billing', 'diagnose', 'nonexistent_tryout_xyz_99@example.com',
  '--entitlement', 'custom_mail_sender'
)
@billing_help_out, _, _ = run_ots('billing', '--help')

# -------------------------------------------------------------------
# Help output
# -------------------------------------------------------------------

## --help exits successfully
@help_status.exitstatus
#=> 0

## --help shows command name
@help_out.include?('ots billing diagnose')
#=> true

## --help shows EMAIL argument as required
@help_out.include?('REQUIRED Customer email address')
#=> true

## --help shows --entitlement option
@help_out.include?('--entitlement=VALUE')
#=> true

## --help describes the entitlement option
@help_out.include?('Check a specific entitlement')
#=> true

## --help shows --verbose option
@help_out.include?('--[no-]verbose')
#=> true

## --help shows description
@help_out.include?('Diagnose entitlement resolution for a user')
#=> true

# -------------------------------------------------------------------
# Missing required argument
# -------------------------------------------------------------------

## Calling without EMAIL exits with non-zero status
@noarg_status.exitstatus
#=> 1

## Missing EMAIL produces an error on stderr
@noarg_err.include?('was called with no arguments')
#=> true

## Missing EMAIL error includes the usage hint
@noarg_err.include?('ots billing diagnose EMAIL')
#=> true

## Missing EMAIL produces no stdout
@noarg_out.strip.empty?
#=> true

# -------------------------------------------------------------------
# Customer not found path
# -------------------------------------------------------------------

## Command exits successfully even when customer is not found
@notfound_status.exitstatus
#=> 0

## Output contains the diagnosed email
@notfound_out.include?('Diagnosing: nonexistent_tryout_xyz_99@example.com')
#=> true

## Output reports billing status (disabled in test env)
@notfound_out.include?('Billing: disabled (standalone mode)')
#=> true

## Output shows STANDALONE_ENTITLEMENTS note when billing is disabled
@notfound_out.include?('STANDALONE_ENTITLEMENTS apply (full access)')
#=> true

## Output shows CUSTOMER section header
@notfound_out.include?('CUSTOMER')
#=> true

## Output shows NOT FOUND message for the email
@notfound_out.include?("NOT FOUND: No customer record for 'nonexistent_tryout_xyz_99@example.com'")
#=> true

## Output includes the fix suggestion
@notfound_out.include?('Fix: Create with')
#=> true

## Output does NOT show ORGANIZATION section (early return after customer miss)
@notfound_out.include?('ORGANIZATION')
#=> false

## Output does NOT show ENTITLEMENTS section header (early return)
@notfound_out.include?("\nENTITLEMENTS\n")
#=> false

# -------------------------------------------------------------------
# Entitlement flag with nonexistent customer
# -------------------------------------------------------------------

## --entitlement flag still exits successfully
@entitlement_status.exitstatus
#=> 0

## --entitlement flag does not change customer-not-found behavior
@entitlement_out.include?('NOT FOUND')
#=> true

## Entitlement result is NOT shown (customer lookup stops the chain)
@entitlement_out.include?("org.can?('custom_mail_sender')")
#=> false

# -------------------------------------------------------------------
# diagnose appears in billing --help as a subcommand
# -------------------------------------------------------------------

## 'billing --help' lists diagnose subcommand
@billing_help_out.include?('diagnose')
#=> true

## 'billing --help' shows diagnose description
@billing_help_out.include?('Diagnose entitlement resolution for a user')
#=> true
