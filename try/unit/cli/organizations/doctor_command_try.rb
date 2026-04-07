# try/unit/cli/organizations/doctor_command_try.rb
#
# frozen_string_literal: true

# Tests for CLI command: bin/ots org doctor
#
# Command options:
#   EXTID       Organization extid to check (optional if --all)
#   --all       Scan all organizations
#   --repair    Auto-repair issues
#   --json      JSON output
#
# Checks performed:
#   1. owner_id points to existing customer (CRITICAL)
#   2. owner_id customer is in members set (HIGH)
#   3. All members have backing customer objects (MEDIUM)
#   4. Membership role:'owner' matches owner_id (WARNING)
#   5. Organization has at least one member (WARNING)
#
# Run: bundle exec try try/unit/cli/organizations/doctor_command_try.rb

require_relative '../../../support/test_helpers'
require 'onetime/cli'

OT.boot! :cli

# Clean up any existing test data from previous runs
Familia.dbclient.flushdb
OT.info "Cleaned Redis for fresh test run"

# Setup with unique identifiers
@test_suffix = "#{Familia.now.to_i}_#{rand(10000)}"

# -------------------------------------------------------------------
# Test Fixtures Setup
# -------------------------------------------------------------------

# Helper: Create a customer and return it
def create_customer(email)
  Onetime::Customer.create!(email: email)
end

# Helper: Create an organization with owner
def create_org(name, owner, billing_email)
  Onetime::Organization.create!(name, owner, billing_email)
end

# Helper: Get the membership key pattern for an org/customer
def membership_key(org_objid, customer_objid)
  "org_membership:organization:#{org_objid}:customer:#{customer_objid}:org_membership:object"
end

# Helper: Directly add a member ID to the org's members sorted set
# (bypasses normal validation to create test scenarios)
def raw_add_member(org, member_id)
  org.members.add(member_id)
end

# Helper: Directly remove a member from the org's members sorted set
def raw_remove_member(org, member)
  org.members.remove(member)
end

# Helper: Set a membership role directly in Redis
def set_membership_role(org_objid, customer_objid, role)
  key = membership_key(org_objid, customer_objid)
  Familia.dbclient.hset(key, 'role', Familia::JsonSerializer.dump(role))
end

# Helper: Create membership record directly in Redis
# Must also populate the org_customer_lookup index for find_by_org_customer to work
def create_membership_record(org_objid, customer_objid, role)
  # The objid for a composite-keyed through model
  objid = "organization:#{org_objid}:customer:#{customer_objid}:org_membership"
  key = membership_key(org_objid, customer_objid)

  # Store field values as JSON (matches Familia's serialization)
  Familia.dbclient.hset(key, 'objid', Familia::JsonSerializer.dump(objid))
  Familia.dbclient.hset(key, 'organization_objid', Familia::JsonSerializer.dump(org_objid))
  Familia.dbclient.hset(key, 'customer_objid', Familia::JsonSerializer.dump(customer_objid))
  Familia.dbclient.hset(key, 'role', Familia::JsonSerializer.dump(role))
  Familia.dbclient.hset(key, 'status', Familia::JsonSerializer.dump('active'))

  # Populate the org_customer_lookup index
  lookup_key = "#{org_objid}:#{customer_objid}"
  Onetime::OrganizationMembership.org_customer_lookup[lookup_key] = objid
end

# Helper: Delete a customer from Redis (simulate deleted customer)
def delete_customer_raw(customer)
  # Delete the customer object
  Familia.dbclient.del("customer:#{customer.objid}:object")
  # Note: we don't clean up indexes intentionally to test stale data scenarios
end

# -------------------------------------------------------------------
# Command class basics
# -------------------------------------------------------------------

## OrgDoctorCommand exists and inherits from Command
Onetime::CLI::OrgDoctorCommand.ancestors.include?(Onetime::CLI::Command)
#=> true

## OrgDoctorCommand can be instantiated
@cmd = Onetime::CLI::OrgDoctorCommand.new
@cmd.is_a?(Dry::CLI::Command)
#=> true

## SEVERITY_ORDER constant has expected keys
Onetime::CLI::OrgDoctorCommand::SEVERITY_ORDER.keys.sort
#=> [:critical, :high, :low, :medium, :warning]

## SEVERITY_ORDER has correct priority (lower = more severe)
Onetime::CLI::OrgDoctorCommand::SEVERITY_ORDER[:critical] < Onetime::CLI::OrgDoctorCommand::SEVERITY_ORDER[:warning]
#=> true

# -------------------------------------------------------------------
# Scenario 1: Healthy organization passes all checks
# -------------------------------------------------------------------

## Create healthy org with owner properly configured
@healthy_owner = create_customer("healthy_owner_#{@test_suffix}@test.com")
@healthy_org = create_org("Healthy Org", @healthy_owner, "healthy_#{@test_suffix}@acme.com")
@healthy_org.class
#=> Onetime::Organization

## Healthy org has owner_id set
@healthy_org.owner_id == @healthy_owner.custid
#=> true

## Healthy org owner is in members set
@healthy_org.member?(@healthy_owner)
#=> true

## Healthy org has member count of 1
@healthy_org.member_count
#=> 1

## Run check_org on healthy org - no issues found
@report = { checked: 0, healthy: 0, issues: [], repaired: [] }
@cmd.send(:check_org, @healthy_org, @report, repair: false)
@report[:issues]
#=> []

## Healthy org counts as healthy
@report[:healthy]
#=> 1

# -------------------------------------------------------------------
# Scenario 2: Org with deleted owner customer (CRITICAL)
# -------------------------------------------------------------------

## Create org then add a second member with role:'owner', then delete original owner
# This matches the real bug scenario: SSO user added with role:'owner' but original owner deleted
@deleted_owner = create_customer("deleted_owner_#{@test_suffix}@test.com")
@orphan_org = create_org("Orphan Owner Org", @deleted_owner, "orphan_#{@test_suffix}@acme.com")
@saved_owner_id = @orphan_org.owner_id
# Add a second member who has role:'owner' (the repair candidate)
@repair_candidate = create_customer("repair_candidate_#{@test_suffix}@test.com")
raw_add_member(@orphan_org, @repair_candidate.objid)
create_membership_record(@orphan_org.objid, @repair_candidate.objid, 'owner')
# Now delete the original owner
delete_customer_raw(@deleted_owner)
@orphan_org.class
#=> Onetime::Organization

## Owner customer no longer exists
Onetime::Customer.load(@saved_owner_id).nil?
#=> true

## Run check_org detects CRITICAL owner issue
@report2 = { checked: 0, healthy: 0, issues: [], repaired: [] }
@cmd.send(:check_org, @orphan_org, @report2, repair: false)
@report2[:issues].size
#=> 1

## Issue has CRITICAL severity
@report2[:issues].first[:issues].first[:severity]
#=> :critical

## Issue has correct check name
@report2[:issues].first[:issues].first[:check]
#=> :owner_exists

## Issue is marked as repairable (because repair candidate exists)
@report2[:issues].first[:issues].first[:repairable]
#=> true

## Issue includes repair action hint
@report2[:issues].first[:issues].first[:repair_action].include?('Will promote')
#=> true

# -------------------------------------------------------------------
# Scenario 3: Org with owner not in members set (HIGH)
# -------------------------------------------------------------------

## Create org and remove owner from members set
@missing_member_owner = create_customer("missing_member_owner_#{@test_suffix}@test.com")
@missing_member_org = create_org("Missing Member Org", @missing_member_owner, "missing_#{@test_suffix}@acme.com")
raw_remove_member(@missing_member_org, @missing_member_owner)
@missing_member_org.class
#=> Onetime::Organization

## Owner exists but is not in members set
[@missing_member_org.owner.nil?, @missing_member_org.member?(@missing_member_owner)]
#=> [false, false]

## Run check_org detects HIGH severity issue
@report3 = { checked: 0, healthy: 0, issues: [], repaired: [] }
@cmd.send(:check_org, @missing_member_org, @report3, repair: false)
@report3[:issues].first[:issues].first[:severity]
#=> :high

## Issue has correct check name
@report3[:issues].first[:issues].first[:check]
#=> :owner_in_members

# -------------------------------------------------------------------
# Scenario 4: Org with stale members (deleted customers) (MEDIUM)
# -------------------------------------------------------------------

## Create org with member, then delete the member
@stale_owner = create_customer("stale_owner_#{@test_suffix}@test.com")
@stale_member = create_customer("stale_member_#{@test_suffix}@test.com")
@stale_org = create_org("Stale Member Org", @stale_owner, "stale_#{@test_suffix}@acme.com")
@stale_org.add_members_instance(@stale_member, through_attrs: { role: 'member' })
@stale_member_id = @stale_member.custid
delete_customer_raw(@stale_member)
@stale_org.class
#=> Onetime::Organization

## Stale member ID is still in members set
@stale_org.members.to_a.include?(@stale_member_id)
#=> true

## Run find_stale_members detects the orphan
@stale_found = @cmd.send(:find_stale_members, @stale_org)
@stale_found.include?(@stale_member_id)
#=> true

## Run check_org detects MEDIUM severity issue
@report4 = { checked: 0, healthy: 0, issues: [], repaired: [] }
@cmd.send(:check_org, @stale_org, @report4, repair: false)
@stale_issue = @report4[:issues].first[:issues].find { |i| i[:check] == :members_exist }
@stale_issue[:severity]
#=> :medium

## Issue includes stale IDs
@stale_issue[:stale_ids].include?(@stale_member_id)
#=> true

# -------------------------------------------------------------------
# Scenario 5: Org with membership role mismatch (WARNING)
# -------------------------------------------------------------------

## Create org with second member that has role:'owner' in membership
@mismatch_owner = create_customer("mismatch_owner_#{@test_suffix}@test.com")
@mismatch_member = create_customer("mismatch_member_#{@test_suffix}@test.com")
@mismatch_org = create_org("Mismatch Org", @mismatch_owner, "mismatch_#{@test_suffix}@acme.com")
@mismatch_org.add_members_instance(@mismatch_member, through_attrs: { role: 'member' })
# Now manually set the membership role to 'owner' (creating a mismatch)
set_membership_role(@mismatch_org.objid, @mismatch_member.objid, 'owner')
@mismatch_org.class
#=> Onetime::Organization

## Run find_role_mismatches detects the issue
@mismatches = @cmd.send(:find_role_mismatches, @mismatch_org)
@mismatches.size
#=> 1

## Mismatch includes the non-owner member's ID
@mismatches.first[:member_id]
#=> @mismatch_member.custid

## Run check_org detects WARNING severity issue
@report5 = { checked: 0, healthy: 0, issues: [], repaired: [] }
@cmd.send(:check_org, @mismatch_org, @report5, repair: false)
@mismatch_issue = @report5[:issues].first[:issues].find { |i| i[:check] == :membership_role_sync }
@mismatch_issue[:severity]
#=> :warning

## Role mismatch issue is NOT auto-repairable
@mismatch_issue[:repairable]
#=> false

# -------------------------------------------------------------------
# Scenario 6: Empty org with no members (WARNING)
# -------------------------------------------------------------------

## Create org then remove all members
@empty_owner = create_customer("empty_owner_#{@test_suffix}@test.com")
@empty_org = create_org("Empty Org", @empty_owner, "empty_#{@test_suffix}@acme.com")
raw_remove_member(@empty_org, @empty_owner)
@empty_org.class
#=> Onetime::Organization

## Org has no members
@empty_org.member_count
#=> 0

## Run check_org detects WARNING for empty org
@report6 = { checked: 0, healthy: 0, issues: [], repaired: [] }
@cmd.send(:check_org, @empty_org, @report6, repair: false)
@empty_issue = @report6[:issues].first[:issues].find { |i| i[:check] == :has_members }
@empty_issue[:severity]
#=> :warning

## Empty org issue is not auto-repairable
@empty_issue[:repairable]
#=> false

# -------------------------------------------------------------------
# Scenario 7: Repair mode - promote_owner_from_membership
# -------------------------------------------------------------------

## Create org with deleted owner but a member with role:'owner'
@promote_owner = create_customer("promote_owner_#{@test_suffix}@test.com")
@promote_candidate = create_customer("promote_candidate_#{@test_suffix}@test.com")
@promote_org = create_org("Promote Org", @promote_owner, "promote_#{@test_suffix}@acme.com")
@promote_org.add_members_instance(@promote_candidate, through_attrs: { role: 'member' })
# Set candidate's membership role to 'owner' (making them eligible for promotion)
set_membership_role(@promote_org.objid, @promote_candidate.objid, 'owner')
# Delete the original owner
delete_customer_raw(@promote_owner)
@promote_org.class
#=> Onetime::Organization

## Run promote_owner_from_membership finds candidate
@promoted = @cmd.send(:promote_owner_from_membership, @promote_org)
@promoted[:custid]
#=> @promote_candidate.custid

## Org owner_id is now updated to promoted candidate
@promote_org.refresh!
@promote_org.owner_id
#=> @promote_candidate.custid

# -------------------------------------------------------------------
# Scenario 8: Repair mode - remove_stale_members
# -------------------------------------------------------------------

## Create org with stale member for removal test
@cleanup_owner = create_customer("cleanup_owner_#{@test_suffix}@test.com")
@cleanup_member = create_customer("cleanup_member_#{@test_suffix}@test.com")
@cleanup_org = create_org("Cleanup Org", @cleanup_owner, "cleanup_#{@test_suffix}@acme.com")
@cleanup_org.add_members_instance(@cleanup_member, through_attrs: { role: 'member' })
@cleanup_member_id = @cleanup_member.custid
delete_customer_raw(@cleanup_member)
@cleanup_org.class
#=> Onetime::Organization

## Stale member is in set before cleanup
@cleanup_org.members.to_a.include?(@cleanup_member_id)
#=> true

## Run remove_stale_members
@stale_to_remove = [@cleanup_member_id]
@cmd.send(:remove_stale_members, @cleanup_org, @stale_to_remove)
@cleanup_org.members.to_a.include?(@cleanup_member_id)
#=> false

## Only owner remains after cleanup
@cleanup_org.member_count
#=> 1

# -------------------------------------------------------------------
# Scenario 9: Repair mode - full check_org with repair flag
# -------------------------------------------------------------------

## Create org with owner missing from members (HIGH issue)
@repair_owner = create_customer("repair_owner_#{@test_suffix}@test.com")
@repair_org = create_org("Repair Org", @repair_owner, "repair_#{@test_suffix}@acme.com")
raw_remove_member(@repair_org, @repair_owner)
@repair_org.class
#=> Onetime::Organization

## Confirm owner not in members
@repair_org.member?(@repair_owner)
#=> false

## Run check_org with repair:true
@report_repair = { checked: 0, healthy: 0, issues: [], repaired: [] }
@cmd.send(:check_org, @repair_org, @report_repair, repair: true)
@report_repair[:repaired].size > 0
#=> true

## Repair action was owner_added_to_members
@report_repair[:repaired].first[:action]
#=> :owner_added_to_members

## Owner is now in members set after repair
@repair_org.member?(@repair_owner)
#=> true

# -------------------------------------------------------------------
# Scenario 10: JSON output format validation
# -------------------------------------------------------------------

## output_json produces valid JSON
@json_report = { checked: 2, healthy: 1, issues: [{ org_extid: 'test', issues: [] }], repaired: [] }
output = StringIO.new
original_stdout = $stdout
$stdout = output
@cmd.send(:output_json, @json_report)
$stdout = original_stdout
@json_output = output.string
JSON.parse(@json_output).is_a?(Hash)
#=> true

## JSON output contains expected keys
@parsed = JSON.parse(@json_output)
@parsed.keys.sort
#=> ["checked", "healthy", "issues", "repaired"]

# -------------------------------------------------------------------
# Scenario 11: scan_all_orgs finds multiple organizations
# -------------------------------------------------------------------

## Create multiple orgs for scan test
@scan_owner1 = create_customer("scan_owner1_#{@test_suffix}@test.com")
@scan_owner2 = create_customer("scan_owner2_#{@test_suffix}@test.com")
@scan_org1 = create_org("Scan Org 1", @scan_owner1, "scan1_#{@test_suffix}@acme.com")
@scan_org2 = create_org("Scan Org 2", @scan_owner2, "scan2_#{@test_suffix}@acme.com")
[@scan_org1, @scan_org2].all? { |o| o.is_a?(Onetime::Organization) }
#=> true

## scan_all_orgs finds organizations
@all_orgs = @cmd.send(:scan_all_orgs)
@all_orgs.size >= 2
#=> true

## All returned items are Organization instances
@all_orgs.all? { |o| o.is_a?(Onetime::Organization) }
#=> true

# -------------------------------------------------------------------
# Scenario 12: load_org handles missing organization
# -------------------------------------------------------------------

## load_org with invalid extid exits with error
# We can't easily test exit behavior in tryouts, so test the lookup
# Organization uses find_by_extid via Familia's object_identifier feature
Onetime::Organization.find_by_extid("invalid_extid_#{@test_suffix}")
#=> nil

# -------------------------------------------------------------------
# Scenario 13: severity_tag formatting
# -------------------------------------------------------------------

## severity_tag returns correct format for each level
@cmd.send(:severity_tag, :critical)
#=> '[CRITICAL]'

## severity_tag for high
@cmd.send(:severity_tag, :high)
#=> '[HIGH]    '

## severity_tag for medium
@cmd.send(:severity_tag, :medium)
#=> '[MEDIUM]  '

## severity_tag for warning
@cmd.send(:severity_tag, :warning)
#=> '[WARNING] '

## severity_tag for low
@cmd.send(:severity_tag, :low)
#=> '[LOW]     '

## severity_tag for unknown returns UNKNOWN
@cmd.send(:severity_tag, :unknown)
#=> '[UNKNOWN] '

# -------------------------------------------------------------------
# Scenario 14: Multiple issues on same org are sorted by severity
# -------------------------------------------------------------------

## Create org with multiple issues
@multi_owner = create_customer("multi_owner_#{@test_suffix}@test.com")
@multi_member = create_customer("multi_member_#{@test_suffix}@test.com")
@multi_org = create_org("Multi Issue Org", @multi_owner, "multi_#{@test_suffix}@acme.com")
@multi_org.add_members_instance(@multi_member, through_attrs: { role: 'member' })
# Create multiple issues:
# 1. Remove owner from members (HIGH)
raw_remove_member(@multi_org, @multi_owner)
# 2. Delete the additional member (MEDIUM - stale member)
@multi_member_id = @multi_member.custid
delete_customer_raw(@multi_member)
@multi_org.class
#=> Onetime::Organization

## Run check_org to find multiple issues
@report_multi = { checked: 0, healthy: 0, issues: [], repaired: [] }
@cmd.send(:check_org, @multi_org, @report_multi, repair: false)
@multi_issues = @report_multi[:issues].first[:issues]
@multi_issues.size >= 2
#=> true

## Issues are sorted by severity (most severe first)
@severities = @multi_issues.map { |i| i[:severity] }
@severity_order = Onetime::CLI::OrgDoctorCommand::SEVERITY_ORDER
@sorted_severities = @severities.sort_by { |s| @severity_order[s] }
@severities == @sorted_severities
#=> true

# -------------------------------------------------------------------
# Scenario 15: ensure_membership_record creates proper record
# -------------------------------------------------------------------

## Create org for membership record test
@ensure_owner = create_customer("ensure_owner_#{@test_suffix}@test.com")
@ensure_member = create_customer("ensure_member_#{@test_suffix}@test.com")
@ensure_org = create_org("Ensure Org", @ensure_owner, "ensure_#{@test_suffix}@acme.com")
# Add member without membership record
raw_add_member(@ensure_org, @ensure_member.custid)
@ensure_org.class
#=> Onetime::Organization

## Run ensure_membership_record creates record
@membership = @cmd.send(:ensure_membership_record, @ensure_org, @ensure_member, role: 'admin')
@membership.role
#=> 'admin'

## Membership is linked to correct org
@membership.organization_objid
#=> @ensure_org.objid

# -------------------------------------------------------------------
# Teardown
# -------------------------------------------------------------------

# Clean up all test data
[@healthy_org, @orphan_org, @missing_member_org, @stale_org, @mismatch_org,
 @empty_org, @promote_org, @cleanup_org, @repair_org, @scan_org1, @scan_org2,
 @multi_org, @ensure_org].compact.each do |org|
  org.destroy! if org.respond_to?(:destroy!) && org.exists?
rescue StandardError
  nil
end

[@healthy_owner, @missing_member_owner, @stale_owner, @mismatch_owner, @mismatch_member,
 @empty_owner, @promote_candidate, @cleanup_owner, @repair_owner, @scan_owner1,
 @scan_owner2, @multi_owner, @ensure_owner, @ensure_member].compact.each do |cust|
  cust.destroy! if cust.respond_to?(:destroy!) && cust.exists?
rescue StandardError
  nil
end

OT.info "Teardown complete"
