# try/unit/cli/customers/doctor_command_try.rb
#
# frozen_string_literal: true

# Tests for the field-serialization check + repair behind `bin/ots customers doctor`.
#
# Focus: the field-serialization check and repair flow added for #3016.
#
# The check + repair logic was extracted (epic #20) out of the CLI command and
# into the shared op that the command now delegates to, so these testcases
# exercise the production methods where they now live:
#   - Auth::Operations::Customers::Doctor#properly_serialized?
#   - Auth::Operations::Customers::Doctor#check_field_serialization
# The CLI command (Onetime::CLI::CustomersDoctorCommand) is a thin adapter over
# this op, so driving the op here still covers the doctor command's field path.
#
# Op signature note: the op takes `customer:`/`repair:` at construction and its
# private `check_field_serialization(issues, repaired)` appends repair-action
# hashes to the `repaired` ARRAY (the CLI's old `report[:repaired]` hash slot).
#
# Closes the coverage gap between try/unit/models/customer_field_serialization_try.rb
# (which tests the serializer primitives) and the doctor check/repair code paths.
# The sibling try/unit/auth/operations/customers_ops_try.rb covers Doctor's other
# checks (role_invalid, verified_by repair) but NOT this serialization boundary.
#
# Run: bundle exec try try/unit/cli/customers/doctor_command_try.rb

require_relative '../../../support/test_helpers'
require 'onetime/cli'

OT.boot! :cli

# The op is the single implementation the CLI delegates to; requiring the CLI
# loads it transitively (doctor_command.rb -> auth/operations/customers/doctor),
# but require it explicitly so this tryout's dependency is self-evident.
require 'auth/operations/customers/doctor'

# Clean up any existing test data from previous runs
Familia.dbclient.flushdb
OT.info "Cleaned Redis for fresh test run"

# Shared fixtures available to every testcase via instance variables
@test_id   = "#{Familia.now.to_i}_#{rand(10000)}"
@dbclient  = Familia.dbclient

# Build a Doctor op for a customer (or nil, for the pure predicate cases).
def doctor_op(customer, repair: false)
  Auth::Operations::Customers::Doctor.new(customer: customer, repair: repair)
end

# -------------------------------------------------------------------
# properly_serialized? predicate: boundary cases
# (pure — does not touch @customer, so a nil-customer op is fine)
# -------------------------------------------------------------------

## properly_serialized? returns true for JSON-quoted email string
doctor_op(nil).send(:properly_serialized?, '"a@b.com"')
#=> true

## properly_serialized? returns false for bare (unquoted) string
doctor_op(nil).send(:properly_serialized?, 'a@b.com')
#=> false

## properly_serialized? returns true for nil (empty field)
doctor_op(nil).send(:properly_serialized?, nil)
#=> true

## properly_serialized? returns true for empty string (cleared field)
doctor_op(nil).send(:properly_serialized?, '')
#=> true

# -------------------------------------------------------------------
# check_field_serialization: issue detection
# -------------------------------------------------------------------

## check_field_serialization flags a bare-string field as a high-severity issue
email = "check_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: email)
@dbclient.hset(cust.dbkey(:object), 'email', email)
issues = []
doctor_op(cust, repair: false).send(:check_field_serialization, issues, [])
cust.delete!
issues.first.slice(:check, :severity, :repairable)
#=> { check: :field_serialization, severity: :high, repairable: true }

## check_field_serialization diagnostic includes {field:, value:} for bad field
@diag_email = "diag_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: @diag_email)
@dbclient.hset(cust.dbkey(:object), 'email', @diag_email)
issues = []
doctor_op(cust, repair: false).send(:check_field_serialization, issues, [])
cust.delete!
bad = issues.first[:fields].find { |f| f[:field] == 'email' }
[bad[:field], bad[:value]]
#=> ['email', @diag_email]

## check_field_serialization truncates long raw values to 61 chars in diagnostic
email = "trunc_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: email)
long_bogus = 'x' * 200
@dbclient.hset(cust.dbkey(:object), 'email', long_bogus)
issues = []
doctor_op(cust, repair: false).send(:check_field_serialization, issues, [])
cust.delete!
issues.first[:fields].find { |f| f[:field] == 'email' }[:value].length
#=> 61

## check_field_serialization emits no issue when all fields are JSON-wrapped
email = "clean_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: email)
issues = []
doctor_op(cust, repair: false).send(:check_field_serialization, issues, [])
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
doctor_op(cust, repair: true).send(:check_field_serialization, [], [])
raw_after = @dbclient.hget(cust.dbkey(:object), 'email')
cust.delete!
raw_after
#=> "\"#{@repair_email}\""

## repair: true records :fields_reserialized in the repaired list
@report_email = "report_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: @report_email)
@dbclient.hset(cust.dbkey(:object), 'email', @report_email)
repaired = []
doctor_op(cust, repair: true).send(:check_field_serialization, [], repaired)
entry = repaired.first
@extid_captured = cust.extid
cust.delete!
[entry[:action], entry[:customer], entry[:fields]]
#=> [:fields_reserialized, @extid_captured, ['email']]

## repair is idempotent: running twice leaves value JSON-wrapped with no double-encoding
@idem_email = "idem_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: @idem_email)
@dbclient.hset(cust.dbkey(:object), 'email', @idem_email)
op = doctor_op(cust, repair: true)
op.send(:check_field_serialization, [], [])
issues = []
op.send(:check_field_serialization, issues, [])
raw = @dbclient.hget(cust.dbkey(:object), 'email')
cust.delete!
[issues.empty?, Familia::JsonSerializer.parse(raw)]
#=> [true, @idem_email]

## repair handles multiple bad fields in a single hset round-trip (batch)
@multi_email = "multi_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: @multi_email)
@dbclient.hset(cust.dbkey(:object), 'email', @multi_email)
@dbclient.hset(cust.dbkey(:object), 'planid', 'basic')
repaired = []
doctor_op(cust, repair: true).send(:check_field_serialization, [], repaired)
raw_email  = @dbclient.hget(cust.dbkey(:object), 'email')
raw_planid = @dbclient.hget(cust.dbkey(:object), 'planid')
fields     = repaired.first[:fields].sort
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
