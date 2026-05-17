# try/unit/cli/billing/sync_billing_email_try.rb
#
# frozen_string_literal: true

# Tests for CLI command: bin/ots billing sync-billing-email
#
# Command options:
#   --apply              Apply changes (default dry-run)
#   --customer cus_xxx   Sync only the org linked to this Stripe customer
#   --update-contact-email  Also update contact_email (default: only billing_email)
#   --sleep MS           Throttle Stripe API calls (default 50ms)
#
# Tested here: command shape, option handling, truncate_email helper,
# orphan reporting, apply_billing_email_update conflict detection,
# and registry wiring. Live Stripe behavior is verified manually.
#
# Run: bundle exec try try/unit/cli/billing/sync_billing_email_try.rb

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
defined?(Onetime::CLI::BillingSyncBillingEmailCommand)
#=> 'constant'

## Inherits from base Command
Onetime::CLI::BillingSyncBillingEmailCommand.ancestors.include?(Onetime::CLI::Command)
#=> true

## Includes BillingHelpers (for with_stripe_retry, stripe_configured?)
Onetime::CLI::BillingSyncBillingEmailCommand.ancestors.include?(Onetime::CLI::BillingHelpers)
#=> true

## Can be instantiated
@cmd = Onetime::CLI::BillingSyncBillingEmailCommand.new
@cmd.is_a?(Dry::CLI::Command)
#=> true

## Registered under 'billing sync-billing-email'
registry          = Onetime::CLI.get(['billing', 'sync-billing-email'])
registered_class  = registry.respond_to?(:command) ? registry.command : registry
registered_class == Onetime::CLI::BillingSyncBillingEmailCommand
#=> true

# -------------------------------------------------------------------
# truncate_email helper
# -------------------------------------------------------------------

## truncate_email returns '-' for nil
@cmd.send(:truncate_email, nil)
#=> '-'

## truncate_email returns '-' for empty string
@cmd.send(:truncate_email, '')
#=> '-'

## truncate_email passes through short emails unchanged
@cmd.send(:truncate_email, 'user@example.com')
#=> 'user@example.com'

## truncate_email shortens long emails with ellipsis (>28 chars)
@long_email = 'verylongusername@verylongdomain.example.com'
@result = @cmd.send(:truncate_email, @long_email)
@result.length == 29 && @result.end_with?('...')
#=> true

## truncate_email truncates at position 25 plus ellipsis
@cmd.send(:truncate_email, 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')
#=> 'aaaaaaaaaaaaaaaaaaaaaaaaaa...'

# -------------------------------------------------------------------
# Single-customer branch: missing customer reports cleanly
# -------------------------------------------------------------------

## sync_single_organization with nonexistent customer prints not-found and returns
@capture = StringIO.new
@orig    = $stdout
$stdout  = @capture
@cmd.instance_variable_set(:@sleep_interval, 0.0)
@cmd.send(
  :sync_single_organization,
  "cus_missing_#{@test_suffix}",
  apply: false,
  update_contact_email: false,
)
$stdout = @orig
@capture.string.include?('No organization found')
#=> true

# -------------------------------------------------------------------
# All-orgs branch: orphaned index entry surfaces in output
# -------------------------------------------------------------------

## Inject a dangling (stripe_customer_id -> bogus org_objid) into the index
@bogus_objid       = "ghost_org_#{@test_suffix}"
@bogus_customer_id = "cus_ghost_#{@test_suffix}"
Onetime::Organization.stripe_customer_id_index[@bogus_customer_id] = @bogus_objid
Onetime::Organization.stripe_customer_id_index[@bogus_customer_id]
#=> @bogus_objid

## sync_all_organizations classifies the orphan row without contacting Stripe
@capture = StringIO.new
$stdout  = @capture
@cmd.instance_variable_set(:@sleep_interval, 0.0)
@cmd.send(
  :sync_all_organizations,
  apply: false,
  update_contact_email: false,
)
$stdout = @orig
@out_str = @capture.string
@out_str.include?('orphaned:') && @out_str.include?('ERROR: org not found')
#=> true

## Summary reports at least one error (the orphan)
@out_str.match(/Errors:\s+(\d+)/)[1].to_i >= 1
#=> true

## Dry-run footer is present
@out_str.include?('Run with --apply')
#=> true

## Header shows mode correctly
@out_str.include?('Mode: DRY RUN')
#=> true

## Header shows update_contact_email setting
@out_str.include?('Update contact_email: NO')
#=> true

# -------------------------------------------------------------------
# apply_billing_email_update: conflict detection
# -------------------------------------------------------------------

## Create two orgs for conflict testing
@owner1 = Onetime::Customer.create!(email: "owner1_#{@test_suffix}@test.com")
@org1   = Onetime::Organization.create!('Org One', @owner1, "org1_#{@test_suffix}@acme.com")
@org1.billing_email = "billing1_#{@test_suffix}@acme.com"
@org1.save

@owner2 = Onetime::Customer.create!(email: "owner2_#{@test_suffix}@test.com")
@org2   = Onetime::Organization.create!('Org Two', @owner2, "org2_#{@test_suffix}@acme.com")
@org2.billing_email = "billing2_#{@test_suffix}@acme.com"
@org2.save
[@org1, @org2].all?(&:exists?)
#=> true

## apply_billing_email_update returns CONFLICT when billing_email in use by another org
@conflict_email = @org1.billing_email
@result = @cmd.send(
  :apply_billing_email_update,
  @org2,
  @conflict_email,
  update_contact_email: false,
)
@result.include?('CONFLICT')
#=> true

## apply_billing_email_update succeeds with unique email
@unique_email = "unique_#{@test_suffix}@acme.com"
@result = @cmd.send(
  :apply_billing_email_update,
  @org2,
  @unique_email,
  update_contact_email: false,
)
@result
#=> 'UPDATED'

## Organization billing_email was actually updated
@org2_reloaded = Onetime::Organization.load(@org2.objid)
@org2_reloaded.billing_email
#=> @unique_email

## contact_email was NOT updated when update_contact_email: false
@org2_reloaded.contact_email != @unique_email
#=> true

## apply_billing_email_update with update_contact_email: true updates both
@both_email = "both_#{@test_suffix}@acme.com"
@result = @cmd.send(
  :apply_billing_email_update,
  @org1,
  @both_email,
  update_contact_email: true,
)
@result
#=> 'UPDATED (both)'

## Both fields were updated
@org1_reloaded = Onetime::Organization.load(@org1.objid)
@org1_reloaded.billing_email == @both_email && @org1_reloaded.contact_email == @both_email
#=> true

# -------------------------------------------------------------------
# Teardown
# -------------------------------------------------------------------

# Remove the dangling index entry we injected
Onetime::Organization.stripe_customer_id_index.remove(@bogus_customer_id)

[@org1, @org2].compact.each do |org|
  org.destroy! if org.respond_to?(:destroy!) && org.exists?
rescue StandardError
  nil
end

[@owner1, @owner2].compact.each do |cust|
  cust.destroy! if cust.respond_to?(:destroy!) && cust.exists?
rescue StandardError
  nil
end

OT.info 'Teardown complete'
