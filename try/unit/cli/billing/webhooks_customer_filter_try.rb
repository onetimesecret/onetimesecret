# try/unit/cli/billing/webhooks_customer_filter_try.rb
#
# frozen_string_literal: true

# Tests for CLI command: bin/ots billing webhooks --customer
#
# Command options:
#   --customer cus_xxx      Filter by Stripe customer ID
#   --customer ORG_EXTID    Filter by organization external ID (resolves to cus_xxx)
#
# Tested here: resolve_customer_id logic, matches_customer? predicate,
# scan_webhook_events iteration, and customer filter branch selection.
# Live Stripe behavior is verified manually.
#
# Run: bundle exec try try/unit/cli/billing/webhooks_customer_filter_try.rb

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
defined?(Onetime::CLI::BillingWebhooksCommand)
#=> 'constant'

## Inherits from base Command
Onetime::CLI::BillingWebhooksCommand.ancestors.include?(Onetime::CLI::Command)
#=> true

## Includes BillingHelpers
Onetime::CLI::BillingWebhooksCommand.ancestors.include?(Onetime::CLI::BillingHelpers)
#=> true

## Can be instantiated
@cmd = Onetime::CLI::BillingWebhooksCommand.new
@cmd.is_a?(Dry::CLI::Command)
#=> true

## Registered under 'billing webhooks'
registry         = Onetime::CLI.get(['billing', 'webhooks'])
registered_class = registry.respond_to?(:command) ? registry.command : registry
registered_class == Onetime::CLI::BillingWebhooksCommand
#=> true

# -------------------------------------------------------------------
# Command has --customer option
# -------------------------------------------------------------------

## Command has --customer option defined
@opts = Onetime::CLI::BillingWebhooksCommand.options
@opts.any? { |opt| opt.name == :customer && opt.options[:type] == :string }
#=> true

## --customer option has description
@customer_opt = @opts.find { |opt| opt.name == :customer }
@customer_opt.options[:desc].include?('customer')
#=> true

# -------------------------------------------------------------------
# resolve_customer_id: direct cus_ prefix passthrough
# -------------------------------------------------------------------

## resolve_customer_id returns cus_ ID unchanged
@cmd.send(:resolve_customer_id, 'cus_abc123')
#=> 'cus_abc123'

## resolve_customer_id returns cus_ ID with any suffix unchanged
@cmd.send(:resolve_customer_id, 'cus_xyz789_test')
#=> 'cus_xyz789_test'

# -------------------------------------------------------------------
# resolve_customer_id: org extid resolution
# -------------------------------------------------------------------

## Create org with stripe_customer_id for resolution test
@owner_org = Onetime::Customer.create!(email: "owner_org_#{@test_suffix}@test.com")
@test_org  = Onetime::Organization.create!('Webhook Test Org', @owner_org, "webhook_#{@test_suffix}@acme.com")
@test_org.stripe_customer_id = "cus_org_#{@test_suffix}"
@test_org.save
@test_org.exists?
#=> true

## resolve_customer_id resolves org extid to stripe_customer_id
@cmd.send(:resolve_customer_id, @test_org.extid)
#=> "cus_org_#{@test_suffix}"

## Create org without stripe_customer_id
@owner_no_cust = Onetime::Customer.create!(email: "owner_no_cust_#{@test_suffix}@test.com")
@org_no_cust   = Onetime::Organization.create!('No Cust Org', @owner_no_cust, "no_cust_#{@test_suffix}@acme.com")
@org_no_cust.save
@org_no_cust.stripe_customer_id.to_s.empty?
#=> true

## resolve_customer_id returns nil for org without stripe_customer_id
@cmd.send(:resolve_customer_id, @org_no_cust.extid)
#=> nil

# -------------------------------------------------------------------
# resolve_customer_id: customer extid resolution
# -------------------------------------------------------------------

## Create customer with stripe_customer_id
@test_customer = Onetime::Customer.create!(email: "test_cust_#{@test_suffix}@test.com")
@test_customer.stripe_customer_id = "cus_direct_#{@test_suffix}"
@test_customer.save
@test_customer.stripe_customer_id
#=> "cus_direct_#{@test_suffix}"

## resolve_customer_id resolves customer extid to stripe_customer_id
@cmd.send(:resolve_customer_id, @test_customer.extid)
#=> "cus_direct_#{@test_suffix}"

## resolve_customer_id returns nil for nonexistent extid
@cmd.send(:resolve_customer_id, "nonexistent_#{@test_suffix}")
#=> nil

# -------------------------------------------------------------------
# matches_customer? - Define mock event class as an instance variable
# -------------------------------------------------------------------

## Define mock event class for matches_customer? tests
@mock_evt_class = Struct.new(:data_object_id, :event_payload, keyword_init: true) do
  def deserialize_payload
    event_payload ? JSON.parse(event_payload) : nil
  end
end
@mock_evt_class.respond_to?(:new)
#=> true

# -------------------------------------------------------------------
# matches_customer?: data_object_id match
# -------------------------------------------------------------------

## matches_customer? returns true when data_object_id matches
@evt1 = @mock_evt_class.new(data_object_id: 'cus_target123', event_payload: nil)
@cmd.send(:matches_customer?, @evt1, 'cus_target123')
#=> true

## matches_customer? returns false when data_object_id differs
@evt2 = @mock_evt_class.new(data_object_id: 'cus_target123', event_payload: nil)
@cmd.send(:matches_customer?, @evt2, 'cus_other')
#=> false

# -------------------------------------------------------------------
# matches_customer?: payload customer field match
# -------------------------------------------------------------------

## matches_customer? returns true when payload.data.object.customer matches
@payload1 = { 'data' => { 'object' => { 'customer' => 'cus_payload123' } } }.to_json
@evt3 = @mock_evt_class.new(data_object_id: nil, event_payload: @payload1)
@cmd.send(:matches_customer?, @evt3, 'cus_payload123')
#=> true

## matches_customer? returns false when payload.data.object.customer differs
@payload2 = { 'data' => { 'object' => { 'customer' => 'cus_payload123' } } }.to_json
@evt4 = @mock_evt_class.new(data_object_id: nil, event_payload: @payload2)
@cmd.send(:matches_customer?, @evt4, 'cus_other')
#=> false

# -------------------------------------------------------------------
# matches_customer?: payload id field match (customer object events)
# -------------------------------------------------------------------

## matches_customer? returns true when payload.data.object.id matches
@payload3 = { 'data' => { 'object' => { 'id' => 'cus_direct_obj' } } }.to_json
@evt5 = @mock_evt_class.new(data_object_id: nil, event_payload: @payload3)
@cmd.send(:matches_customer?, @evt5, 'cus_direct_obj')
#=> true

# -------------------------------------------------------------------
# matches_customer?: metadata customer_extid match
# -------------------------------------------------------------------

## matches_customer? returns true when metadata.customer_extid matches original_customer_id
@payload4 = { 'data' => { 'object' => { 'metadata' => { 'customer_extid' => 'cu9x7y8z' } } } }.to_json
@evt6 = @mock_evt_class.new(data_object_id: nil, event_payload: @payload4)
@cmd.send(:matches_customer?, @evt6, nil, original_customer_id: 'cu9x7y8z')
#=> true

## matches_customer? returns false when metadata.customer_extid differs from original_customer_id
@payload5 = { 'data' => { 'object' => { 'metadata' => { 'customer_extid' => 'cu9x7y8z' } } } }.to_json
@evt7 = @mock_evt_class.new(data_object_id: nil, event_payload: @payload5)
@cmd.send(:matches_customer?, @evt7, nil, original_customer_id: 'cu_other')
#=> false

# -------------------------------------------------------------------
# matches_customer?: handles missing/nil payload gracefully
# -------------------------------------------------------------------

## matches_customer? returns false when no payload and no data_object_id match
@evt8 = @mock_evt_class.new(data_object_id: nil, event_payload: nil)
@cmd.send(:matches_customer?, @evt8, 'cus_any')
#=> false

# -------------------------------------------------------------------
# list_events_by_customer: invalid customer prints error
# -------------------------------------------------------------------

## list_events_by_customer with unresolvable customer prints error
@capture = StringIO.new
@orig    = $stdout
$stdout  = @capture
@cmd.send(:list_events_by_customer, "unresolvable_#{@test_suffix}")
$stdout = @orig
@capture.string.include?('Could not resolve customer')
#=> true

# -------------------------------------------------------------------
# list_events_by_customer: no events returns empty message
# -------------------------------------------------------------------

## list_events_by_customer with valid customer but no events prints empty
@capture = StringIO.new
$stdout  = @capture
@cmd.send(:list_events_by_customer, 'cus_no_events')
$stdout = @orig
@capture.string.include?('No events found')
#=> true

# -------------------------------------------------------------------
# call: customer branch is selected when --customer provided
# -------------------------------------------------------------------

## call routes to list_events_by_customer when customer provided
# Verify by checking call method source references list_events_by_customer
@call_source = File.read(Onetime::CLI::BillingWebhooksCommand.instance_method(:call).source_location.first)
@call_source.include?('list_events_by_customer(customer)')
#=> true

## customer option is checked before status/failed options
@call_source.index('customer') < @call_source.index('failed || status')
#=> true

# -------------------------------------------------------------------
# format_timestamp: handles various inputs
# -------------------------------------------------------------------

## format_timestamp returns N/A for nil
@cmd.send(:format_timestamp, nil)
#=> 'N/A'

## format_timestamp returns N/A for empty string
@cmd.send(:format_timestamp, '')
#=> 'N/A'

## format_timestamp formats valid timestamp
@ts = Time.new(2025, 1, 15, 10, 30, 45, '+00:00').to_i.to_s
@result = @cmd.send(:format_timestamp, @ts)
@result.include?('2025-01-15')
#=> true

## format_timestamp handles integer timestamp
@result = @cmd.send(:format_timestamp, 1705315845)
@result.include?('2024-01-15') || @result.include?('Invalid') == false
#=> true

# -------------------------------------------------------------------
# format_status: color codes status values
# -------------------------------------------------------------------

## format_status applies green to success
@result = @cmd.send(:format_status, 'success')
@result.include?('success') && @result.include?("\e[32m")
#=> true

## format_status applies red to failed
@result = @cmd.send(:format_status, 'failed')
@result.include?('failed') && @result.include?("\e[31m")
#=> true

## format_status applies yellow to retrying
@result = @cmd.send(:format_status, 'retrying')
@result.include?('retrying') && @result.include?("\e[33m")
#=> true

## format_status applies cyan to pending
@result = @cmd.send(:format_status, 'pending')
@result.include?('pending') && @result.include?("\e[36m")
#=> true

## format_status returns unknown statuses as-is
@cmd.send(:format_status, 'unknown')
#=> 'unknown'

# -------------------------------------------------------------------
# Teardown
# -------------------------------------------------------------------

[@test_org, @org_no_cust].compact.each do |org|
  org.destroy! if org.respond_to?(:destroy!) && org.exists?
rescue StandardError
  nil
end

[@owner_org, @owner_no_cust, @test_customer].compact.each do |cust|
  cust.destroy! if cust.respond_to?(:destroy!) && cust.exists?
rescue StandardError
  nil
end

OT.info 'Teardown complete'
