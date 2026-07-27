# try/unit/cli/billing/sync_org_command_try.rb
#
# frozen_string_literal: true

# Tests for CLI command: bin/ots billing sync-org
#
# Command options:
#   EXTID       Organization external ID to sync (optional if --all)
#   --all       Sync all organizations with stripe_subscription_id
#   --dry-run   Preview changes without applying
#
# Tested here: command shape, option handling, truncate_extid helper,
# single org sync logic, batch processing, error handling, and dry-run mode.
# The mutation itself is delegated to the shared audited op
# Onetime::Operations::Org::Reconcile (#3903) — adapter behavior is covered
# by spec/cli/billing/sync_org_command_spec.rb and the op by
# spec/unit/onetime/operations/org/reconcile_spec.rb.
#
# Run: bundle exec try try/unit/cli/billing/sync_org_command_try.rb

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
defined?(Onetime::CLI::BillingSyncOrgCommand)
#=> 'constant'

## Inherits from base Command
Onetime::CLI::BillingSyncOrgCommand.ancestors.include?(Onetime::CLI::Command)
#=> true

## Includes BillingHelpers (for stripe_configured?)
Onetime::CLI::BillingSyncOrgCommand.ancestors.include?(Onetime::CLI::BillingHelpers)
#=> true

## Can be instantiated
@cmd = Onetime::CLI::BillingSyncOrgCommand.new
@cmd.is_a?(Dry::CLI::Command)
#=> true

## Registered under 'billing sync-org'
registry         = Onetime::CLI.get(['billing', 'sync-org'])
registered_class = registry.respond_to?(:command) ? registry.command : registry
registered_class == Onetime::CLI::BillingSyncOrgCommand
#=> true

# -------------------------------------------------------------------
# truncate_extid helper
# -------------------------------------------------------------------

## truncate_extid truncates long extids with ellipsis
@long_extid = 'on8q30gih2uxu2cw77jzh7caq07'
@cmd.send(:truncate_extid, @long_extid)
#=> 'on8q30gih2u...'

## truncate_extid preserves first 11 characters
@result = @cmd.send(:truncate_extid, @long_extid)
@result[0..10]
#=> 'on8q30gih2u'

## truncate_extid handles nil gracefully
@cmd.send(:truncate_extid, nil).include?('...')
#=> true

## truncate_extid handles empty string
@cmd.send(:truncate_extid, '').include?('...')
#=> true

# -------------------------------------------------------------------
# sync_single_organization: org not found
# -------------------------------------------------------------------

## sync_single_organization with nonexistent extid prints error
@capture = StringIO.new
@orig    = $stdout
$stdout  = @capture
@cmd.send(:sync_single_organization, "nonexistent_extid_#{@test_suffix}", dry_run: false)
$stdout = @orig
@capture.string.include?('Error: Organization not found')
#=> true

# -------------------------------------------------------------------
# sync_single_organization: org without subscription (dry run)
# -------------------------------------------------------------------

## Create org without stripe_subscription_id
@owner_no_sub = Onetime::Customer.create!(email: "owner_no_sub_#{@test_suffix}@test.com")
@org_no_sub   = Onetime::Organization.create!('Org No Sub', @owner_no_sub, "org_no_sub_#{@test_suffix}@acme.com")
@org_no_sub.save
@org_no_sub.exists?
#=> true

## Org has no stripe_subscription_id
@org_no_sub.stripe_subscription_id.to_s.empty?
#=> true

# -------------------------------------------------------------------
# sync_all_organizations: skips orgs without subscription
# -------------------------------------------------------------------

## sync_all_organizations reports skipped count for orgs without subscription
@capture = StringIO.new
$stdout  = @capture
@cmd.send(:sync_all_organizations, dry_run: true)
$stdout = @orig
@output = @capture.string
@output.include?('Skipped') && @output.include?('no stripe_subscription_id')
#=> true

# -------------------------------------------------------------------
# sync_organization: dry run shows changes without saving
# -------------------------------------------------------------------

## Create org with mock subscription ID
@owner_with_sub = Onetime::Customer.create!(email: "owner_with_sub_#{@test_suffix}@test.com")
@org_with_sub   = Onetime::Organization.create!('Org With Sub', @owner_with_sub, "org_with_sub_#{@test_suffix}@acme.com")
@org_with_sub.stripe_subscription_id = "sub_test_#{@test_suffix}"
@org_with_sub.planid = 'old_plan_v1'
@org_with_sub.save
@org_with_sub.exists?
#=> true

## Org has stripe_subscription_id set
@org_with_sub.stripe_subscription_id.to_s.start_with?('sub_test_')
#=> true

# -------------------------------------------------------------------
# Delegation: the audited Reconcile op owns the mutation (#3903)
# -------------------------------------------------------------------

## The shared Reconcile op is loaded by the command file
defined?(Onetime::Operations::Org::Reconcile)
#=> 'constant'

## sync_organization is defined in this command file (not inherited)
Onetime::CLI::BillingSyncOrgCommand.instance_method(:sync_organization).source_location.first.include?('sync_org_command.rb')
#=> true

## Command delegates the mutation to Onetime::Operations::Org::Reconcile
@command_source = File.read(Onetime::CLI::BillingSyncOrgCommand.instance_method(:sync_organization).source_location.first)
@command_source.include?('Onetime::Operations::Org::Reconcile')
#=> true

## Command no longer calls ApplySubscriptionToOrg directly (op owns it)
@command_source.include?('ApplySubscriptionToOrg')
#=> false

## Audit actor is the shared CLI sentinel, never a fabricated Customer
@command_source.include?('Customers::Shared::CLI_ACTOR')
#=> true

## Status mapping keys off the op's OK_STATUSES contract
@command_source.include?('OK_STATUSES')
#=> true

# -------------------------------------------------------------------
# Error handling: Billing::OpsProblem family
# -------------------------------------------------------------------

## OpsProblem family is rescued per-org so a --all sweep keeps going
# CatalogMissError AND PlanCacheMissError are Billing::OpsProblem subclasses
# (not Stripe::StripeError), so they escape Reconcile#call; the adapter
# rescues the parent class, not a single subclass.
@command_source.include?('rescue Billing::OpsProblem')
#=> true

## OpsProblem handler reports the exception class + message generically
@command_source.include?('ex.class') && @command_source.include?('ex.message')
#=> true

## Unexpected StandardErrors are contained in the --all sweep loop
# Containment scope decision (PR #3924 review): sweep robust, single-org
# loud — the same exception on `sync-org <extid>` still raises with a
# backtrace.
@command_source.include?('rescue StandardError')
#=> true

## Sweep summary label is pluralized to match synced/skipped ("3 errors")
@command_source.include?("\#{stats[:errors]} errors")
#=> true

## Dry-run outcome line has no hardcoded dangling reason separator
# The "— reason" segment is conditional on result.reason being present.
@command_source.include?('result.status} — ')
#=> false

# -------------------------------------------------------------------
# call: validates arguments (extid or --all required)
# -------------------------------------------------------------------

## call method validates that extid or --all is required (code path exists)
# The actual error message is printed after stripe_configured? check,
# so we verify the code path exists structurally
@call_source = File.read(Onetime::CLI::BillingSyncOrgCommand.instance_method(:call).source_location.first)
@call_source.include?('Error: Provide an extid or use --all')
#=> true

## call method routes to sync_all_organizations when --all is true
@call_source.include?('sync_all_organizations(dry_run: dry_run)')
#=> true

## call method routes to sync_single_organization when extid provided
@call_source.include?('sync_single_organization(extid, dry_run: dry_run)')
#=> true

# -------------------------------------------------------------------
# Command options are defined correctly
# -------------------------------------------------------------------

## Command accepts extid argument
@args = Onetime::CLI::BillingSyncOrgCommand.arguments
@args.first.name == :extid
#=> true

## extid argument is optional (for --all mode)
@args.first.options[:required] == false
#=> true

## Command has --all option
@opts = Onetime::CLI::BillingSyncOrgCommand.options
@opts.any? { |opt| opt.name == :all && opt.options[:type] == :boolean }
#=> true

## Command has --dry-run option
@opts.any? { |opt| opt.name == :dry_run && opt.options[:type] == :boolean }
#=> true

## --dry-run defaults to false
@dry_run_opt = @opts.find { |opt| opt.name == :dry_run }
@dry_run_opt.options[:default] == false
#=> true

## --all defaults to false
@all_opt = @opts.find { |opt| opt.name == :all }
@all_opt.options[:default] == false
#=> true

# -------------------------------------------------------------------
# Teardown
# -------------------------------------------------------------------

[@org_no_sub, @org_with_sub].compact.each do |org|
  org.destroy! if org.respond_to?(:destroy!) && org.exists?
rescue StandardError
  nil
end

[@owner_no_sub, @owner_with_sub].compact.each do |cust|
  cust.destroy! if cust.respond_to?(:destroy!) && cust.exists?
rescue StandardError
  nil
end

OT.info 'Teardown complete'
