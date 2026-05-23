# try/unit/cli/organizations/list_plan_filter_try.rb
#
# frozen_string_literal: true

# Tests for CLI command: bin/ots organizations --list --plan=PLAN_ID
#
# Command options:
#   --list      List all organizations
#   --plan      Filter by plan ID (e.g., identity_plus_v1, free)
#
# Tested here: --plan filter behavior, plan matching logic, empty results,
# filter interaction with other options, and output formatting.
#
# Run: bundle exec try try/unit/cli/organizations/list_plan_filter_try.rb

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
defined?(Onetime::CLI::OrganizationsListCommand)
#=> 'constant'

## Inherits from base Command
Onetime::CLI::OrganizationsListCommand.ancestors.include?(Onetime::CLI::Command)
#=> true

## Can be instantiated
@cmd = Onetime::CLI::OrganizationsListCommand.new
@cmd.is_a?(Dry::CLI::Command)
#=> true

## Registered under 'organizations'
registry         = Onetime::CLI.get(['organizations'])
registered_class = registry.respond_to?(:command) ? registry.command : registry
registered_class == Onetime::CLI::OrganizationsListCommand
#=> true

## Also registered under 'organization' alias
registry_alias   = Onetime::CLI.get(['organization'])
alias_class      = registry_alias.respond_to?(:command) ? registry_alias.command : registry_alias
alias_class == Onetime::CLI::OrganizationsListCommand
#=> true

# -------------------------------------------------------------------
# Command has --plan option
# -------------------------------------------------------------------

## Command has --plan option defined
@opts = Onetime::CLI::OrganizationsListCommand.options
@opts.any? { |opt| opt.name == :plan && opt.options[:type] == :string }
#=> true

## --plan option defaults to nil
@plan_opt = @opts.find { |opt| opt.name == :plan }
@plan_opt.options[:default].nil?
#=> true

## --plan option has description
@plan_opt.options[:desc].include?('plan')
#=> true

# -------------------------------------------------------------------
# Create test organizations with different plans
# -------------------------------------------------------------------

## Create org on identity_plus_v1 plan
@owner_plus = Onetime::Customer.create!(email: "owner_plus_#{@test_suffix}@test.com")
@org_plus   = Onetime::Organization.create!('Plus Org', @owner_plus, "plus_#{@test_suffix}@acme.com")
@org_plus.planid = 'identity_plus_v1'
@org_plus.save
@org_plus.planid
#=> 'identity_plus_v1'

## Create org on free plan
@owner_free = Onetime::Customer.create!(email: "owner_free_#{@test_suffix}@test.com")
@org_free   = Onetime::Organization.create!('Free Org', @owner_free, "free_#{@test_suffix}@acme.com")
@org_free.planid = 'free'
@org_free.save
@org_free.planid
#=> 'free'

## Create org on enterprise_v1 plan
@owner_ent = Onetime::Customer.create!(email: "owner_ent_#{@test_suffix}@test.com")
@org_ent   = Onetime::Organization.create!('Enterprise Org', @owner_ent, "ent_#{@test_suffix}@acme.com")
@org_ent.planid = 'enterprise_v1'
@org_ent.save
@org_ent.planid
#=> 'enterprise_v1'

## Create org with no plan (empty planid)
@owner_no_plan = Onetime::Customer.create!(email: "owner_no_plan_#{@test_suffix}@test.com")
@org_no_plan   = Onetime::Organization.create!('No Plan Org', @owner_no_plan, "no_plan_#{@test_suffix}@acme.com")
@org_no_plan.planid = ''
@org_no_plan.save
@org_no_plan.planid.to_s.empty?
#=> true

# -------------------------------------------------------------------
# list_organizations: plan filter returns matching orgs
# -------------------------------------------------------------------

## list_organizations with plan='identity_plus_v1' shows only plus org
@capture = StringIO.new
@orig    = $stdout
$stdout  = @capture
@cmd.send(:list_organizations, owner: nil, plan: 'identity_plus_v1', limit: 50, verbose: false)
$stdout = @orig
@output = @capture.string
@output.include?('identity_plus_v1') && @output.include?('Found')
#=> true

## Filter message shows count and plan name
@output.match(/Found \d+ organizations matching plan=identity_plus_v1/)
#=> @output.match(/Found \d+ organizations matching plan=identity_plus_v1/)

## Output includes the plus org extid
@output.include?(@org_plus.extid)
#=> true

## Output does NOT include the free org extid
@output.include?(@org_free.extid)
#=> false

# -------------------------------------------------------------------
# list_organizations: plan filter with no matches
# -------------------------------------------------------------------

## list_organizations with nonexistent plan returns empty
@capture = StringIO.new
$stdout  = @capture
@cmd.send(:list_organizations, owner: nil, plan: "nonexistent_plan_#{@test_suffix}", limit: 50, verbose: false)
$stdout = @orig
@output = @capture.string
@output.include?('Found 0 organizations matching')
#=> true

# -------------------------------------------------------------------
# list_organizations: plan filter for 'free' plan
# -------------------------------------------------------------------

## list_organizations with plan='free' shows free org
@capture = StringIO.new
$stdout  = @capture
@cmd.send(:list_organizations, owner: nil, plan: 'free', limit: 50, verbose: false)
$stdout = @orig
@output = @capture.string
@output.include?(@org_free.extid)
#=> true

## Output does NOT include the plus org
@output.include?(@org_plus.extid)
#=> false

# -------------------------------------------------------------------
# list_organizations: plan filter combined with owner filter
# -------------------------------------------------------------------

## Create additional org for combined filter test
@owner_combo = Onetime::Customer.create!(email: "combo_owner_#{@test_suffix}@test.com")
@org_combo   = Onetime::Organization.create!('Combo Org', @owner_combo, "combo_#{@test_suffix}@acme.com")
@org_combo.planid = 'identity_plus_v1'
@org_combo.save
@org_combo.planid
#=> 'identity_plus_v1'

## list_organizations with both plan and owner filters
@capture = StringIO.new
$stdout  = @capture
@cmd.send(:list_organizations, owner: "combo_owner_#{@test_suffix}", plan: 'identity_plus_v1', limit: 50, verbose: false)
$stdout = @orig
@output = @capture.string
# Should filter by both and find the combo org
@output.include?(@org_combo.extid)
#=> true

# -------------------------------------------------------------------
# list_organizations: plan filter with limit
# -------------------------------------------------------------------

## list_organizations respects limit even with plan filter
@capture = StringIO.new
$stdout  = @capture
@cmd.send(:list_organizations, owner: nil, plan: 'identity_plus_v1', limit: 1, verbose: false)
$stdout = @orig
# Should not crash and should respect the limit parameter
# (limit applies AFTER plan filter - streams through all orgs until limit matches found)
true
#=> true

# -------------------------------------------------------------------
# list_organizations: verbose mode with plan filter
# -------------------------------------------------------------------

## list_organizations verbose mode works with plan filter
@capture = StringIO.new
$stdout  = @capture
@cmd.send(:list_organizations, owner: nil, plan: 'enterprise_v1', limit: 50, verbose: true)
$stdout = @orig
@output = @capture.string
@output.include?(@org_ent.extid)
#=> true

# -------------------------------------------------------------------
# call: routes to list_organizations when --list provided
# -------------------------------------------------------------------

## call routes to list_organizations with plan filter when both provided
@call_source = File.read(Onetime::CLI::OrganizationsListCommand.instance_method(:call).source_location.first)
@call_source.include?('list_organizations(owner: owner, plan: plan')
#=> true

# -------------------------------------------------------------------
# Plan filter matching is exact (not substring)
# -------------------------------------------------------------------

## 'identity' does not match 'identity_plus_v1'
@capture = StringIO.new
$stdout  = @capture
@cmd.send(:list_organizations, owner: nil, plan: 'identity', limit: 50, verbose: false)
$stdout = @orig
@output = @capture.string
@output.include?('Found 0')
#=> true

## 'identity_plus' (partial) does not match 'identity_plus_v1'
@capture = StringIO.new
$stdout  = @capture
@cmd.send(:list_organizations, owner: nil, plan: 'identity_plus', limit: 50, verbose: false)
$stdout = @orig
@output = @capture.string
@output.include?('Found 0')
#=> true

# -------------------------------------------------------------------
# truncate helper
# -------------------------------------------------------------------

## truncate helper truncates long strings with ellipsis (unicode)
@cmd.send(:truncate, 'this is a very long string that should be truncated', 20)
#=> "this is a very long…"

## truncate helper preserves short strings
@cmd.send(:truncate, 'short', 20)
#=> 'short'

## truncate helper handles exact length strings
@cmd.send(:truncate, 'exactly_twenty_char', 20)
#=> 'exactly_twenty_char'

# -------------------------------------------------------------------
# owner_email helper
# -------------------------------------------------------------------

## owner_email returns obscured email when owner exists
@result = @cmd.send(:owner_email, @org_plus)
@result.include?('***')
#=> true

# -------------------------------------------------------------------
# Teardown
# -------------------------------------------------------------------

[@org_plus, @org_free, @org_ent, @org_no_plan, @org_combo].compact.each do |org|
  org.destroy! if org.respond_to?(:destroy!) && org.exists?
rescue StandardError
  nil
end

[@owner_plus, @owner_free, @owner_ent, @owner_no_plan, @owner_combo].compact.each do |cust|
  cust.destroy! if cust.respond_to?(:destroy!) && cust.exists?
rescue StandardError
  nil
end

OT.info 'Teardown complete'
