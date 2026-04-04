# try/unit/api/organizations/logic/determine_user_role_try.rb
#
# frozen_string_literal: true

#
# Unit tests for OrganizationAPI::Logic::Base#determine_user_role
#
# Tests that the method correctly returns roles based on membership lookup:
# - Owner returns 'owner' (via Organization#owner?)
# - Admin returns 'admin' (via membership lookup)
# - Member returns 'member' (via membership lookup)
# - Non-member returns 'member' (defensive fallback when no membership found)
#
# Bug fix for issue #2888: Previously returned 'member' for all non-owners,
# ignoring the actual membership role. Now correctly looks up OrganizationMembership.

require_relative '../../../../support/test_helpers'

OT.boot! :test

require 'apps/api/organizations/logic'

# Setup with unique identifiers
@test_suffix = "#{Familia.now.to_i}_#{rand(10000)}"
@owner = Onetime::Customer.create!(email: generate_unique_test_email("role_owner"))
@admin = Onetime::Customer.create!(email: generate_unique_test_email("role_admin"))
@member = Onetime::Customer.create!(email: generate_unique_test_email("role_member"))
@outsider = Onetime::Customer.create!(email: generate_unique_test_email("role_outsider"))
@org = Onetime::Organization.create!("Role Test Org", @owner, generate_unique_test_email("role_contact"))

# Create admin membership
@admin_invite = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @admin.email,
  role: 'admin',
  inviter: @owner
)
@admin_invite.accept!(@admin)

# Create member membership
@member_invite = Onetime::OrganizationMembership.create_invitation!(
  organization: @org,
  email: @member.email,
  role: 'member',
  inviter: @owner
)
@member_invite.accept!(@member)

# Create a test logic class instance to access determine_user_role
# We need to include the module to access the protected method
class TestLogic < OrganizationAPI::Logic::Base
  def initialize(org, user)
    @org = org
    @user = user
  end

  def test_determine_role
    determine_user_role(@org, @user)
  end
end

# =============================================================================
# Role Detection Tests
# =============================================================================

## Owner returns 'owner'
logic = TestLogic.new(@org, @owner)
logic.test_determine_role
#=> 'owner'

## Admin returns 'admin' (not 'member' - this was the bug)
logic = TestLogic.new(@org, @admin)
logic.test_determine_role
#=> 'admin'

## Member returns 'member'
logic = TestLogic.new(@org, @member)
logic.test_determine_role
#=> 'member'

## Non-member returns 'member' (defensive fallback)
logic = TestLogic.new(@org, @outsider)
logic.test_determine_role
#=> 'member'


# =============================================================================
# Teardown
# =============================================================================

[@owner, @admin, @member, @outsider].each(&:destroy!)
@org.destroy!
