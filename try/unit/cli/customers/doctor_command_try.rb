# try/unit/cli/customers/doctor_command_try.rb
#
# frozen_string_literal: true

# Tests for CLI command: bin/ots customers doctor
#
# Focus: the field-serialization check and repair flow added for #3016.
# Exercises the actual production methods:
#   - Onetime::CLI::CustomersDoctorCommand#properly_serialized?
#   - Onetime::CLI::CustomersDoctorCommand#check_field_serialization
#
# Closes the coverage gap between try/unit/models/customer_field_serialization_try.rb
# (which tests the serializer primitives) and the doctor command code paths.
#
# Run: bundle exec try try/unit/cli/customers/doctor_command_try.rb

require_relative '../../../support/test_helpers'
require 'onetime/cli'

OT.boot! :cli

# Clean up any existing test data from previous runs
Familia.dbclient.flushdb
OT.info "Cleaned Redis for fresh test run"

# Shared fixtures available to every testcase via instance variables
@test_id   = "#{Familia.now.to_i}_#{rand(10000)}"
@dbclient  = Familia.dbclient

# -------------------------------------------------------------------
# properly_serialized? predicate: boundary cases
# -------------------------------------------------------------------

## properly_serialized? returns true for JSON-quoted email string
cmd = Onetime::CLI::CustomersDoctorCommand.new
cmd.send(:properly_serialized?, '"a@b.com"')
#=> true

## properly_serialized? returns false for bare (unquoted) string
cmd = Onetime::CLI::CustomersDoctorCommand.new
cmd.send(:properly_serialized?, 'a@b.com')
#=> false

## properly_serialized? returns true for nil (empty field)
cmd = Onetime::CLI::CustomersDoctorCommand.new
cmd.send(:properly_serialized?, nil)
#=> true

## properly_serialized? returns true for empty string (cleared field)
cmd = Onetime::CLI::CustomersDoctorCommand.new
cmd.send(:properly_serialized?, '')
#=> true

# -------------------------------------------------------------------
# check_field_serialization: issue detection
# -------------------------------------------------------------------

## check_field_serialization flags a bare-string field as a high-severity issue
email = "check_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: email)
@dbclient.hset(cust.dbkey(:object), 'email', email)
cmd = Onetime::CLI::CustomersDoctorCommand.new
issues = []
report = { checked: 0, healthy: 0, issues: [], repaired: [] }
cmd.send(:check_field_serialization, cust, issues, report, repair: false)
cust.delete!
issues.first.slice(:check, :severity, :repairable)
#=> { check: :field_serialization, severity: :high, repairable: true }

## check_field_serialization diagnostic includes {field:, value:} for bad field
@diag_email = "diag_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: @diag_email)
@dbclient.hset(cust.dbkey(:object), 'email', @diag_email)
cmd = Onetime::CLI::CustomersDoctorCommand.new
issues = []
cmd.send(:check_field_serialization, cust, issues, { repaired: [] }, repair: false)
cust.delete!
bad = issues.first[:fields].find { |f| f[:field] == 'email' }
[bad[:field], bad[:value]]
#=> ['email', @diag_email]

## check_field_serialization truncates long raw values to 61 chars in diagnostic
email = "trunc_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: email)
long_bogus = 'x' * 200
@dbclient.hset(cust.dbkey(:object), 'email', long_bogus)
cmd = Onetime::CLI::CustomersDoctorCommand.new
issues = []
cmd.send(:check_field_serialization, cust, issues, { repaired: [] }, repair: false)
cust.delete!
issues.first[:fields].find { |f| f[:field] == 'email' }[:value].length
#=> 61

## check_field_serialization emits no issue when all fields are JSON-wrapped
email = "clean_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: email)
cmd = Onetime::CLI::CustomersDoctorCommand.new
issues = []
cmd.send(:check_field_serialization, cust, issues, { repaired: [] }, repair: false)
cust.delete!
issues
#=> []

# -------------------------------------------------------------------
# check_field_serialization: repair path
# -------------------------------------------------------------------

## repair: true rewrites the bare field back to JSON in Redis (end-to-end)
@repair_email = "repair_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: @repair_email)
@dbclient.hset(cust.dbkey(:object), 'email', @repair_email)
cmd = Onetime::CLI::CustomersDoctorCommand.new
report = { checked: 0, healthy: 0, issues: [], repaired: [] }
cmd.send(:check_field_serialization, cust, [], report, repair: true)
raw_after = @dbclient.hget(cust.dbkey(:object), 'email')
cust.delete!
raw_after
#=> "\"#{@repair_email}\""

## repair: true records :fields_reserialized in report[:repaired]
@report_email = "report_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: @report_email)
@dbclient.hset(cust.dbkey(:object), 'email', @report_email)
cmd = Onetime::CLI::CustomersDoctorCommand.new
report = { checked: 0, healthy: 0, issues: [], repaired: [] }
cmd.send(:check_field_serialization, cust, [], report, repair: true)
entry = report[:repaired].first
@extid_captured = cust.extid
cust.delete!
[entry[:action], entry[:customer], entry[:fields]]
#=> [:fields_reserialized, @extid_captured, ['email']]

## repair is idempotent: running twice leaves value JSON-wrapped with no double-encoding
@idem_email = "idem_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: @idem_email)
@dbclient.hset(cust.dbkey(:object), 'email', @idem_email)
cmd = Onetime::CLI::CustomersDoctorCommand.new
cmd.send(:check_field_serialization, cust, [], { repaired: [] }, repair: true)
issues = []
cmd.send(:check_field_serialization, cust, issues, { repaired: [] }, repair: true)
raw = @dbclient.hget(cust.dbkey(:object), 'email')
cust.delete!
[issues.empty?, Familia::JsonSerializer.parse(raw)]
#=> [true, @idem_email]

## repair handles multiple bad fields in a single hset round-trip (batch)
@multi_email = "multi_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: @multi_email)
@dbclient.hset(cust.dbkey(:object), 'email', @multi_email)
@dbclient.hset(cust.dbkey(:object), 'planid', 'basic')
cmd = Onetime::CLI::CustomersDoctorCommand.new
report = { checked: 0, healthy: 0, issues: [], repaired: [] }
cmd.send(:check_field_serialization, cust, [], report, repair: true)
raw_email  = @dbclient.hget(cust.dbkey(:object), 'email')
raw_planid = @dbclient.hget(cust.dbkey(:object), 'planid')
fields     = report[:repaired].first[:fields].sort
cust.delete!
[fields, raw_email, raw_planid]
#=> [%w[email planid], "\"#{@multi_email}\"", '"basic"']

# -------------------------------------------------------------------
# Teardown
# -------------------------------------------------------------------

# Most testcases above delete their own customer inline. This is a best-effort
# safety net in case any testcase bailed before reaching its cleanup line.
# Uses Familia.members to enumerate live customer objids.
begin
  Onetime::Customer.instances.to_a.each do |cust|
    next unless cust.respond_to?(:email) && cust.email.to_s.include?("_#{@test_id}@")
    cust.destroy! if cust.respond_to?(:destroy!) && cust.exists?
  rescue StandardError
    nil
  end
rescue StandardError
  nil
end

OT.info "Teardown complete"
