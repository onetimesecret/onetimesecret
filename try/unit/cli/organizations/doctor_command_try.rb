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
#   6. stripe_customer_id unique-index entry (CRITICAL/HIGH/MEDIUM, #4205)
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
def create_membership_record(org_objid, customer_objid, role)
  objid = "organization:#{org_objid}:customer:#{customer_objid}:org_membership"
  key = membership_key(org_objid, customer_objid)

  Familia.dbclient.hset(key, 'objid', Familia::JsonSerializer.dump(objid))
  Familia.dbclient.hset(key, 'organization_objid', Familia::JsonSerializer.dump(org_objid))
  Familia.dbclient.hset(key, 'customer_objid', Familia::JsonSerializer.dump(customer_objid))
  Familia.dbclient.hset(key, 'role', Familia::JsonSerializer.dump(role))
  Familia.dbclient.hset(key, 'status', Familia::JsonSerializer.dump('active'))
end

# Helper: Create an org that carries a Stripe customer id, claiming the
# class-level unique index the way a normal full save does.
def create_billed_org(label, owner, customer_id, suffix)
  org = create_org(label, owner, "#{label.downcase.gsub(/\W+/, '')}_#{suffix}@acme.com")
  org.stripe_customer_id = customer_id
  org.save
  org
end

# Helper: the class-level unique index behind `unique_index :stripe_customer_id`
def stripe_index
  Onetime::Organization.stripe_customer_id_index
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
# Scenario 16: CHECK 6 — healthy stripe_customer_id index entry (#4205)
# -------------------------------------------------------------------

## A normal full save claims the class-level index for the saving org
@stripe_owner       = create_customer("stripe_owner_#{@test_suffix}@test.com")
@healthy_cus        = "cus_healthy_#{@test_suffix}"
@stripe_healthy_org = create_billed_org('StripeHealthy', @stripe_owner, @healthy_cus, @test_suffix)
stripe_index[@healthy_cus]
#=> @stripe_healthy_org.objid

## Check 6 reports nothing when the org holds its own entry
@issues16 = []
@report16 = { checked: 0, healthy: 0, issues: [], repaired: [] }
@cmd.send(:check_stripe_customer_id_index, @stripe_healthy_org, @issues16, @report16, repair: false)
@issues16
#=> []

## An org with no stripe_customer_id is skipped entirely
@issues16b = []
@cmd.send(:check_stripe_customer_id_index, @healthy_org, @issues16b, @report16, repair: false)
@issues16b
#=> []

# -------------------------------------------------------------------
# Scenario 17: CHECK 6 — MISSING index entry (field set, never claimed)
# -------------------------------------------------------------------

## Drop the index entry: the shape a fast write or a write inside MULTI leaves
@missing_cus        = "cus_missing_#{@test_suffix}"
@stripe_missing_org = create_billed_org('StripeMissing', @stripe_owner, @missing_cus, @test_suffix)
stripe_index.remove(@missing_cus)
stripe_index[@missing_cus].to_s
#=> ""

## Check 6 flags it as a missing entry (MEDIUM — no lockout yet, but claimable
## by another org)
@issues17 = []
@report17 = { checked: 0, healthy: 0, issues: [], repaired: [] }
@cmd17    = Onetime::CLI::OrgDoctorCommand.new
@cmd17.send(:check_stripe_customer_id_index, @stripe_missing_org, @issues17, @report17, repair: false)
[@issues17.size, @issues17.first[:check], @issues17.first[:state], @issues17.first[:severity]]
#=> [1, :stripe_customer_id_index, :missing_entry, :medium]

## The missing entry is auto-repairable
@issues17.first[:repairable]
#=> true

## Audit mode leaves the index alone
stripe_index[@missing_cus].to_s
#=> ""

## --repair claims the entry for the org
@issues17r = []
@report17r = { checked: 0, healthy: 0, issues: [], repaired: [] }
@cmd17r    = Onetime::CLI::OrgDoctorCommand.new
@cmd17r.send(:check_stripe_customer_id_index, @stripe_missing_org, @issues17r, @report17r, repair: true)
stripe_index[@missing_cus]
#=> @stripe_missing_org.objid

## The repair is recorded as a claim
[@report17r[:repaired].size, @report17r[:repaired].first[:action], @report17r[:repaired].first[:stripe_customer_id]]
#=> [1, :stripe_index_claimed, @missing_cus]

# -------------------------------------------------------------------
# Scenario 18: CHECK 6 — STALE index entry (holder org deleted)
# -------------------------------------------------------------------

## Point the entry at an objid that no longer resolves
@stale_cus        = "cus_stale_#{@test_suffix}"
@stripe_stale_org = create_billed_org('StripeStale', @stripe_owner, @stale_cus, @test_suffix)
@gone_objid       = "gone_org_#{@test_suffix}"
stripe_index[@stale_cus] = @gone_objid
Onetime::Organization.load(@gone_objid).nil?
#=> true

## Check 6 flags a stale entry (HIGH — every full save on this org fails)
@issues18 = []
@report18 = { checked: 0, healthy: 0, issues: [], repaired: [] }
@cmd18    = Onetime::CLI::OrgDoctorCommand.new
@cmd18.send(:check_stripe_customer_id_index, @stripe_stale_org, @issues18, @report18, repair: false)
[@issues18.size, @issues18.first[:state], @issues18.first[:severity], @issues18.first[:repairable]]
#=> [1, :stale_entry, :high, true]

## The issue names the objid the entry points at
@issues18.first[:index_objid]
#=> @gone_objid

## --repair repoints the entry at the surviving org
@issues18r = []
@report18r = { checked: 0, healthy: 0, issues: [], repaired: [] }
@cmd18r    = Onetime::CLI::OrgDoctorCommand.new
@cmd18r.send(:check_stripe_customer_id_index, @stripe_stale_org, @issues18r, @report18r, repair: true)
stripe_index[@stale_cus]
#=> @stripe_stale_org.objid

## The repair records what it displaced
@repair18 = @report18r[:repaired].first
[@repair18[:action], @repair18[:previous_objid]]
#=> [:stripe_index_repointed, @gone_objid]

# -------------------------------------------------------------------
# Scenario 19: CHECK 6 — STALE index entry (holder moved to another customer)
# -------------------------------------------------------------------

## Two live orgs; the entry for one points at the other, which carries its own id
@moved_cus_a    = "cus_moved_a_#{@test_suffix}"
@moved_cus_b    = "cus_moved_b_#{@test_suffix}"
@moved_org_a    = create_billed_org('StripeMovedA', @stripe_owner, @moved_cus_a, @test_suffix)
@moved_org_b    = create_billed_org('StripeMovedB', @stripe_owner, @moved_cus_b, @test_suffix)
stripe_index[@moved_cus_a] = @moved_org_b.objid
@issues19 = []
@report19 = { checked: 0, healthy: 0, issues: [], repaired: [] }
@cmd19    = Onetime::CLI::OrgDoctorCommand.new
@cmd19.send(:check_stripe_customer_id_index, @moved_org_a, @issues19, @report19, repair: false)
[@issues19.size, @issues19.first[:state], @issues19.first[:repairable]]
#=> [1, :stale_entry, true]

## A holder that no longer carries the id is a dead pointer, not a rival —
## the message names it so an operator can see where the entry went
@issues19.first[:message].include?(@moved_org_b.extid)
#=> true

# -------------------------------------------------------------------
# Scenario 20: CHECK 6 — LIVE DUPLICATE (two orgs, one Stripe customer)
# -------------------------------------------------------------------

## Both orgs persist the same stripe_customer_id; the index points at the second
## (exactly the drift a write path that skipped the claim leaves behind)
@dup_cus   = "cus_dup_#{@test_suffix}"
@dup_org_a = create_billed_org('StripeDupA', @stripe_owner, @dup_cus, @test_suffix)
stripe_index.remove(@dup_cus)
@dup_org_b = create_billed_org('StripeDupB', @stripe_owner, @dup_cus, @test_suffix)
[stripe_index[@dup_cus] == @dup_org_b.objid, @dup_org_a.stripe_customer_id, @dup_org_b.stripe_customer_id]
#=> [true, @dup_cus, @dup_cus]

## Check 6 flags the locked-out org as a CRITICAL duplicate
@issues20 = []
@report20 = { checked: 0, healthy: 0, issues: [], repaired: [] }
@cmd20    = Onetime::CLI::OrgDoctorCommand.new
@cmd20.send(:check_stripe_customer_id_index, @dup_org_a, @issues20, @report20, repair: false)
[@issues20.size, @issues20.first[:state], @issues20.first[:severity]]
#=> [1, :duplicate, :critical]

## A live duplicate is NEVER auto-repairable
@issues20.first[:repairable]
#=> false

## The report carries both sides, with the index holder marked
@dup_issue = @issues20.first
[@dup_issue[:contender][:extid], @dup_issue[:contender][:holds_index],
 @dup_issue[:rivals].map { |r| r[:extid] }, @dup_issue[:rivals].first[:holds_index]]
#=> [@dup_org_a.extid, false, [@dup_org_b.extid], true]

## Adjudication context an operator needs is included per side
@dup_issue[:rivals].first.keys.sort
#=> [:display_name, :extid, :holds_index, :objid, :owner, :planid, :stripe_subscription_id, :subscription_status]

## --repair does not touch the index for a duplicate
@issues20r = []
@report20r = { checked: 0, healthy: 0, issues: [], repaired: [] }
@cmd20r    = Onetime::CLI::OrgDoctorCommand.new
@cmd20r.send(:check_stripe_customer_id_index, @dup_org_a, @issues20r, @report20r, repair: true)
[stripe_index[@dup_cus] == @dup_org_b.objid, @report20r[:repaired]]
#=> [true, []]

# -------------------------------------------------------------------
# Scenario 21: CHECK 6 — duplicate whose index entry points at NEITHER org
# -------------------------------------------------------------------

## Two live orgs on one id, index entry aimed at a dead third objid. Without the
## claims pre-pass this is indistinguishable from a plain stale entry, and
## --repair would award the customer to whichever org the scan reached first.
@dup2_cus   = "cus_dup2_#{@test_suffix}"
@dup2_org_a = create_billed_org('StripeDup2A', @stripe_owner, @dup2_cus, @test_suffix)
stripe_index.remove(@dup2_cus)
@dup2_org_b = create_billed_org('StripeDup2B', @stripe_owner, @dup2_cus, @test_suffix)
stripe_index[@dup2_cus] = "gone_third_#{@test_suffix}"
@cmd21 = Onetime::CLI::OrgDoctorCommand.new
@cmd21.send(:index_stripe_customer_claims, [@dup2_org_a, @dup2_org_b])
@issues21 = []
@report21 = { checked: 0, healthy: 0, issues: [], repaired: [] }
@cmd21.send(:check_stripe_customer_id_index, @dup2_org_a, @issues21, @report21, repair: true)
[@issues21.first[:state], @issues21.first[:repairable], @report21[:repaired]]
#=> [:duplicate, false, []]

## Neither org holds the entry, so the consequence is stated as a race
[@issues21.first[:contender][:holds_index], @issues21.first[:rivals].first[:holds_index]]
#=> [false, false]

## Without the pre-pass the same state reads as a repairable stale entry —
## which is exactly why #call builds the claim map before checking anything
@issues21b = []
@cmd21b    = Onetime::CLI::OrgDoctorCommand.new
@cmd21b.send(:check_stripe_customer_id_index, @dup2_org_a, @issues21b, @report21, repair: false)
@issues21b.first[:state]
#=> :stale_entry

# -------------------------------------------------------------------
# Scenario 22: index sweep — orphaned entries no live org carries
# -------------------------------------------------------------------

## An entry whose org is gone and whose customer id nobody carries. It blocks
## any FUTURE org from claiming that id, so check 6 can never see it.
@orphan_cus = "cus_orphan_#{@test_suffix}"
stripe_index[@orphan_cus] = "gone_orphan_#{@test_suffix}"
@cmd22 = Onetime::CLI::OrgDoctorCommand.new
@cmd22.send(:index_stripe_customer_claims, @cmd22.send(:scan_all_orgs))
@orphans22 = @cmd22.send(:collect_orphan_index_entries, stripe_index)
@orphans22.map { |e| e[:stripe_customer_id] }.include?(@orphan_cus)
#=> true

## A healthy org's entry is never an orphan
@orphans22.map { |e| e[:stripe_customer_id] }.include?(@healthy_cus)
#=> false

## An id two LIVE orgs contest is check 6's finding, not the sweep's — the
## sweep must not report it, and above all must not delete it
@orphans22.map { |e| e[:stripe_customer_id] }.include?(@dup2_cus)
#=> false

## The sweep reports orphans as a class-level issue group
@report22 = { checked: 0, healthy: 0, issues: [], repaired: [] }
@cmd22.send(:sweep_stripe_customer_id_index, @report22, repair: false)
@sweep_group = @report22[:issues].find { |g| g[:type] == :stripe_customer_id_index }
[@sweep_group[:label], @sweep_group[:issues].first[:check], @sweep_group[:issues].first[:severity]]
#=> ['organization:stripe_customer_id_index', :stripe_customer_id_index_orphans, :medium]

## Audit mode leaves the orphan in place
stripe_index[@orphan_cus].to_s.empty?
#=> false

## --repair removes the orphan and frees the Stripe customer id
@report22r = { checked: 0, healthy: 0, issues: [], repaired: [] }
@cmd22r    = Onetime::CLI::OrgDoctorCommand.new
@cmd22r.send(:index_stripe_customer_claims, @cmd22r.send(:scan_all_orgs))
@cmd22r.send(:sweep_stripe_customer_id_index, @report22r, repair: true)
stripe_index[@orphan_cus].to_s
#=> ""

## The contested entry survives the sweep untouched
stripe_index[@dup2_cus].to_s.empty?
#=> false

## The sweep repair is recorded
@sweep_repair = @report22r[:repaired].find { |r| r[:action] == :stripe_index_orphans_removed }
@sweep_repair[:count].positive?
#=> true

# -------------------------------------------------------------------
# Scenario 23: check 6 findings reach check_org and the JSON output
# -------------------------------------------------------------------

## check_org runs check 6 alongside the owner/member checks
@json_cus     = "cus_json_#{@test_suffix}"
@json_org     = create_billed_org('StripeJson', @stripe_owner, @json_cus, @test_suffix)
stripe_index[@json_cus] = "gone_json_#{@test_suffix}"
@report23 = { checked: 0, healthy: 0, issues: [], repaired: [] }
@cmd23    = Onetime::CLI::OrgDoctorCommand.new
@cmd23.send(:check_org, @json_org, @report23, repair: false)
@report23[:issues].first[:issues].map { |i| i[:check] }.include?(:stripe_customer_id_index)
#=> true

## --json renders the new check, its state and its Stripe customer id
@json_out = StringIO.new
@prev_stdout = $stdout
$stdout = @json_out
@cmd23.send(:output_json, @report23)
$stdout = @prev_stdout
@json23 = JSON.parse(@json_out.string)
@json23_issue = @json23['issues'].first['issues'].find { |i| i['check'] == 'stripe_customer_id_index' }
[@json23_issue['state'], @json23_issue['severity'], @json23_issue['stripe_customer_id']]
#=> ['stale_entry', 'high', @json_cus]

## Text output renders the class-level sweep group without an org label
@text_out = StringIO.new
@prev_stdout = $stdout
$stdout = @text_out
@cmd22.send(:output_text, @report22, repair: false)
$stdout = @prev_stdout
@text_out.string.include?('organization:stripe_customer_id_index')
#=> true

## Text output renders the duplicate adjudication block
@dup_text_out = StringIO.new
@dup_report   = { checked: 1, healthy: 0, repaired: [],
                  issues: [{ org_extid: @dup_org_a.extid, display_name: 'Dup A', issues: @issues20 }] }
@prev_stdout = $stdout
$stdout = @dup_text_out
@cmd20.send(:output_text, @dup_report, repair: false)
$stdout = @prev_stdout
[@dup_text_out.string.include?('[holds index entry]'), @dup_text_out.string.include?('manual fix required')]
#=> [true, true]

# -------------------------------------------------------------------
# Scenario 24: legacy JSON-encoded index values are stripped before compare
# -------------------------------------------------------------------

## Familia 2.9 wrote index values JSON-encoded. A value read literally would
## look like a different objid — and --repair would hand a live org's entry
## to somebody else.
@cmd24 = Onetime::CLI::OrgDoctorCommand.new
@cmd24.send(:index_value, "\"on1abcdef\"")
#=> 'on1abcdef'

## Raw values pass through untouched
@cmd24.send(:index_value, 'on1abcdef')
#=> 'on1abcdef'

## nil reads back as the empty string (the "no entry" signal)
@cmd24.send(:index_value, nil)
#=> ''

# -------------------------------------------------------------------
# Teardown
# -------------------------------------------------------------------

# Clean up all test data
[@healthy_org, @orphan_org, @missing_member_org, @stale_org, @mismatch_org,
 @empty_org, @promote_org, @cleanup_org, @repair_org, @scan_org1, @scan_org2,
 @multi_org, @ensure_org, @stripe_healthy_org, @stripe_missing_org,
 @stripe_stale_org, @moved_org_a, @moved_org_b, @dup_org_a, @dup_org_b,
 @dup2_org_a, @dup2_org_b, @json_org].compact.each do |org|
  org.destroy! if org.respond_to?(:destroy!) && org.exists?
rescue StandardError
  nil
end

[@healthy_owner, @missing_member_owner, @stale_owner, @mismatch_owner, @mismatch_member,
 @empty_owner, @promote_candidate, @cleanup_owner, @repair_owner, @scan_owner1,
 @scan_owner2, @multi_owner, @ensure_owner, @ensure_member,
 @stripe_owner].compact.each do |cust|
  cust.destroy! if cust.respond_to?(:destroy!) && cust.exists?
rescue StandardError
  nil
end

# Index entries outlive the orgs when a fixture pointed one at a dead objid.
[@healthy_cus, @missing_cus, @stale_cus, @moved_cus_a, @moved_cus_b, @dup_cus,
 @dup2_cus, @orphan_cus, @json_cus].compact.each do |customer_id|
  Onetime::Organization.stripe_customer_id_index.remove(customer_id)
rescue StandardError
  nil
end

OT.info "Teardown complete"
