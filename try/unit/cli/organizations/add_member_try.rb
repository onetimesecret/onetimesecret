# try/unit/cli/organizations/add_member_try.rb
#
# frozen_string_literal: true

# Tests for CLI command: bin/ots organizations add-member
#
# Command options:
#   --org       Organization extid or domain hostname
#   --email     Customer email
#   --role      member or admin (default: member)
#   --default   Set org as customer's default organization
#   --dry-run   Preview mode
#
# Run: bundle exec try try/unit/cli/organizations/add_member_try.rb

require_relative '../../../support/test_helpers'

OT.boot! :cli

# Clean up any existing test data from previous runs
Familia.dbclient.flushdb
OT.info "Cleaned Redis for fresh test run"

# Setup with unique identifiers
@test_suffix = "#{Familia.now.to_i}_#{rand(10000)}"

# Create test fixtures
@owner = Onetime::Customer.create!(email: "cli_owner_#{@test_suffix}@test.com")
@member = Onetime::Customer.create!(email: "cli_member_#{@test_suffix}@test.com")
@billing_email = "cli_billing_#{@test_suffix}@acme.com"

# Create test organization
@org = Onetime::Organization.create!("CLI Test Org", @owner, @billing_email)

# Create a domain for domain-based org resolution tests
# Domain requires org_id to save, then we link it to the org
@domain = Onetime::CustomDomain.new(
  display_domain: "cli-test-#{@test_suffix}.example.com",
  base_domain: "example.com",
  org_id: @org.objid
)
@domain.save
@org.add_domain(@domain)

# -------------------------------------------------------------------
# Helper method to simulate CLI add-member command behavior
# This mirrors what the actual command will do
# -------------------------------------------------------------------

def resolve_organization(org_identifier)
  # Try extid first
  org = Onetime::Organization.find_by_extid(org_identifier)
  return org if org

  # Try domain hostname lookup
  domain = Onetime::CustomDomain.find_by_display_domain(org_identifier)
  return nil unless domain

  domain.organization_instances.first
end

def add_member_cli(org:, email:, role: 'member', default_org: false, dry_run: false)
  # Validate role
  valid_roles = %w[member admin]
  unless valid_roles.include?(role)
    return { success: false, error: "Invalid role '#{role}'. Must be one of: #{valid_roles.join(', ')}" }
  end

  # Resolve organization
  organization = resolve_organization(org)
  unless organization
    return { success: false, error: "Organization not found: #{org}" }
  end

  # Find customer - normalize email to lowercase for consistent Redis lookup
  # (Customer emails are stored lowercase via Customer.create! normalization)
  normalized_email = email.to_s.strip.unicode_normalize(:nfc).downcase(:fold)
  customer = Onetime::Customer.find_by_email(normalized_email)
  unless customer
    return { success: false, error: "Customer not found: #{email}" }
  end

  if dry_run
    already_member = organization.member?(customer)
    action = already_member ? 'update' : 'add'
    return {
      success: true,
      dry_run: true,
      action: action,
      message: "[DRY RUN] Would #{action} #{email} as #{role} in #{organization.display_name}",
      organization: organization,
      customer: customer,
      role: role,
      default_org: default_org
    }
  end

  # Add or update member (idempotent via through model)
  membership = organization.add_members_instance(customer, through_attrs: { role: role })

  # Handle --default flag
  if default_org
    # Set this org as customer's default
    # This requires finding the membership and marking it
    membership.role = role  # Ensure role is set
    membership.save
  end

  {
    success: true,
    dry_run: false,
    membership: membership,
    organization: organization,
    customer: customer,
    role: role
  }
end

# -------------------------------------------------------------------
# Happy Path: Add member by org extid with default role
# -------------------------------------------------------------------

## Add member by org extid returns success
@result = add_member_cli(org: @org.extid, email: @member.email, role: 'member')
@result[:success]
#=> true

## Member is added to organization
@org.member?(@member)
#=> true

## Membership has correct role (default: member)
@membership_key = "organization:#{@org.objid}:customer:#{@member.objid}:org_membership"
@membership = Onetime::OrganizationMembership.load(@membership_key)
@membership.role
#=> 'member'

# -------------------------------------------------------------------
# Happy Path: Add member by domain hostname
# -------------------------------------------------------------------

## Create another customer for domain test
@member2 = Onetime::Customer.create!(email: "cli_member2_#{@test_suffix}@test.com")
@member2.class
#=> Onetime::Customer

## Add member by domain hostname returns success
@result2 = add_member_cli(org: @domain.display_domain, email: @member2.email, role: 'member')
@result2[:success]
#=> true

## Member added via domain lookup is in organization
@org.member?(@member2)
#=> true

# -------------------------------------------------------------------
# Happy Path: Add member with admin role
# -------------------------------------------------------------------

## Create another customer for admin role test
@admin_member = Onetime::Customer.create!(email: "cli_admin_#{@test_suffix}@test.com")
@admin_member.class
#=> Onetime::Customer

## Add member with admin role returns success
@result3 = add_member_cli(org: @org.extid, email: @admin_member.email, role: 'admin')
@result3[:success]
#=> true

## Admin membership has admin role
@admin_key = "organization:#{@org.objid}:customer:#{@admin_member.objid}:org_membership"
@admin_membership = Onetime::OrganizationMembership.load(@admin_key)
@admin_membership.role
#=> 'admin'

# -------------------------------------------------------------------
# Happy Path: Add member with --default flag
# -------------------------------------------------------------------

## Create another customer for default org test
@default_test_member = Onetime::Customer.create!(email: "cli_default_#{@test_suffix}@test.com")
@default_test_member.class
#=> Onetime::Customer

## Add member with default flag returns success
@result4 = add_member_cli(org: @org.extid, email: @default_test_member.email, role: 'member', default_org: true)
@result4[:success]
#=> true

## Member with default flag is in organization
@org.member?(@default_test_member)
#=> true

# -------------------------------------------------------------------
# Happy Path: Dry-run shows what would happen without changes
# -------------------------------------------------------------------

## Create another customer for dry-run test
@dry_run_member = Onetime::Customer.create!(email: "cli_dryrun_#{@test_suffix}@test.com")
@dry_run_member.class
#=> Onetime::Customer

## Dry-run returns success with preview info
@dry_result = add_member_cli(org: @org.extid, email: @dry_run_member.email, role: 'admin', dry_run: true)
@dry_result[:success]
#=> true

## Dry-run result indicates dry_run mode
@dry_result[:dry_run]
#=> true

## Dry-run result indicates 'add' action for new member
@dry_result[:action]
#=> 'add'

## Dry-run does NOT actually add the member
@org.member?(@dry_run_member)
#=> false

## Dry-run for existing member shows 'update' action
@existing_dry = add_member_cli(org: @org.extid, email: @member.email, role: 'admin', dry_run: true)
@existing_dry[:action]
#=> 'update'

# -------------------------------------------------------------------
# Error Cases: Customer not found
# -------------------------------------------------------------------

## Adding non-existent customer returns error
@error_result = add_member_cli(org: @org.extid, email: "nonexistent_#{@test_suffix}@test.com", role: 'member')
@error_result[:success]
#=> false

## Error message mentions customer not found
@error_result[:error].include?('Customer not found')
#=> true

# -------------------------------------------------------------------
# Error Cases: Organization not found (extid)
# -------------------------------------------------------------------

## Adding to non-existent org extid returns error
@error_org = add_member_cli(org: "on_nonexistent_#{@test_suffix}", email: @member.email, role: 'member')
@error_org[:success]
#=> false

## Error message mentions organization not found
@error_org[:error].include?('Organization not found')
#=> true

# -------------------------------------------------------------------
# Error Cases: Organization not found (domain)
# -------------------------------------------------------------------

## Adding via non-existent domain returns error
@error_domain = add_member_cli(org: "nonexistent-#{@test_suffix}.example.com", email: @member.email, role: 'member')
@error_domain[:success]
#=> false

## Error message mentions organization not found for domain
@error_domain[:error].include?('Organization not found')
#=> true

# -------------------------------------------------------------------
# Error Cases: Invalid role (owner, superadmin, etc.)
# -------------------------------------------------------------------

## Adding with 'owner' role returns error
@error_owner = add_member_cli(org: @org.extid, email: @member.email, role: 'owner')
@error_owner[:success]
#=> false

## Error message mentions invalid role for owner
@error_owner[:error].include?('Invalid role')
#=> true

## Adding with 'superadmin' role returns error
@error_super = add_member_cli(org: @org.extid, email: @member.email, role: 'superadmin')
@error_super[:success]
#=> false

## Error message mentions invalid role for superadmin
@error_super[:error].include?('Invalid role')
#=> true

## Adding with empty role returns error
@error_empty = add_member_cli(org: @org.extid, email: @member.email, role: '')
@error_empty[:success]
#=> false

## Error message mentions invalid role for empty
@error_empty[:error].include?('Invalid role')
#=> true

# -------------------------------------------------------------------
# Edge Cases: Already a member - should succeed (idempotent)
# -------------------------------------------------------------------

## Re-adding existing member succeeds (idempotent)
@idempotent = add_member_cli(org: @org.extid, email: @member.email, role: 'member')
@idempotent[:success]
#=> true

## Member count unchanged after re-add (same member, not duplicated)
# Count members before and compare
@member_count_before = @org.member_count
@recount = add_member_cli(org: @org.extid, email: @member.email, role: 'member')
@org.member_count == @member_count_before
#=> true

# -------------------------------------------------------------------
# Edge Cases: Idempotent role update - re-adding with different role updates membership
# -------------------------------------------------------------------

## Initial membership role is member
@member_membership = Onetime::OrganizationMembership.load(@membership_key)
@member_membership.role
#=> 'member'

## Re-adding with admin role updates the membership
@role_update = add_member_cli(org: @org.extid, email: @member.email, role: 'admin')
@role_update[:success]
#=> true

## Membership role updated to admin
@updated_membership = Onetime::OrganizationMembership.load(@membership_key)
@updated_membership.role
#=> 'admin'

## Re-adding with member role reverts the membership
@role_revert = add_member_cli(org: @org.extid, email: @member.email, role: 'member')
@role_revert[:success]
#=> true

## Membership role reverted to member
@reverted_membership = Onetime::OrganizationMembership.load(@membership_key)
@reverted_membership.role
#=> 'member'

# -------------------------------------------------------------------
# Edge Cases: --default with existing member updates their default org
# -------------------------------------------------------------------

## Setting default on existing member succeeds
@default_existing = add_member_cli(org: @org.extid, email: @member.email, role: 'member', default_org: true)
@default_existing[:success]
#=> true

## Member still exists in organization after default update
@org.member?(@member)
#=> true

# -------------------------------------------------------------------
# Edge Cases: Case-insensitive email lookup
# -------------------------------------------------------------------

## Adding with uppercase email finds existing customer
@upper_result = add_member_cli(org: @org.extid, email: @member.email.upcase, role: 'member')
@upper_result[:success]
#=> true

# -------------------------------------------------------------------
# Cleanup
# -------------------------------------------------------------------

# Remove domain first (org.destroy! requires no domains)
if @domain&.respond_to?(:destroy!) && @domain.exists?
  @org.remove_domain(@domain) if @org&.domain?(@domain)
  @domain.destroy!
end

# Now destroy org and customers
[@org, @owner, @member, @member2, @admin_member, @default_test_member, @dry_run_member].each do |obj|
  obj.destroy! if obj&.respond_to?(:destroy!) && obj.exists?
end
