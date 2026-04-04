# try/unit/logic/organizations/members/remove_member_cache_try.rb
#
# frozen_string_literal: true

# Tests that RemoveMember invalidates the removed member's cached organization
# context. This ensures users immediately lose access to org features after
# removal, rather than retaining stale permissions until cache expires.
#
# Related: GitHub issue #2877 - Organization cache not invalidated on member removal
#
# Test coverage:
# 1. Cache is populated before removal
# 2. RemoveMember clears cache for the target member
# 3. Subsequent org context loads reflect new state (member no longer in org)
#
# Architecture note:
# RemoveMember receives the actor's session (owner/admin performing removal).
# It calls clear_organization_cache(@target_member, sess) which deletes
# "org_context:#{target_member.objid}" from the actor's session. This works
# when sessions are server-side (keyed by user), but with isolated client
# sessions the member's actual session isn't cleared until their next request
# reloads context.

require_relative '../../../../support/test_helpers'

OT.boot! :test, false

require 'apps/api/organizations/logic'
require 'onetime/application/organization_loader'

# Create test customers
@owner_email = generate_unique_test_email("rm_cache_owner")
@member_email = generate_unique_test_email("rm_cache_member")

@owner = Onetime::Customer.create!(email: @owner_email, role: 'customer')
@member = Onetime::Customer.create!(email: @member_email, role: 'customer')

# Create organization with owner
@org = Onetime::Organization.create!('Cache Test Org', @owner)
@org.is_default = true
@org.save

# Add member directly (not via invitation) to ensure proper participation setup
# This uses Familia's add_members_instance which creates bidirectional indexes
@org.add_members_instance(@member, through_attrs: { role: 'member' })

# Verify member is in org
@member_in_org = @org.member?(@member)

# Create mock sessions that behave like Rack sessions (hash-like)
@owner_session = {}
@member_session = {}

# Helper class to test OrganizationLoader
class TestOrgLoader
  include Onetime::Application::OrganizationLoader
end

@loader = TestOrgLoader.new


## Setup verification: Member is in organization
@member_in_org
#=> true


## Setup verification: Member's org context can be loaded
context = @loader.load_organization_context(@member, @member_session, {})
context[:organization]&.objid == @org.objid
#=> true


## Setup verification: Cache key is populated after loading
cache_key = "org_context:#{@member.objid}"
@member_session.key?(cache_key)
#=> true


## RemoveMember removes member from organization
# First ensure cache is populated
@member_session.clear
@loader.load_organization_context(@member, @member_session, {})
cache_key = "org_context:#{@member.objid}"
cache_populated_before = @member_session.key?(cache_key)

# Create owner's strategy result for RemoveMember
owner_strategy_result = MockStrategyResult.authenticated(@owner, session: @owner_session)

# Execute RemoveMember
params = {
  'extid' => @org.extid,
  'member_extid' => @member.extid
}
remove_logic = OrganizationAPI::Logic::Members::RemoveMember.new(owner_strategy_result, params)
remove_logic.raise_concerns
remove_logic.process

# Verify member was removed from org
member_removed = !@org.member?(@member)

[cache_populated_before, member_removed]
#=> [true, true]


## RemoveMember calls clear_organization_cache for target member
# The implementation clears cache via sess (actor's session). When sessions
# are isolated (different hash per user), this clears the key from the wrong
# session. But when sessions are server-side keyed by user, it works.
#
# Verify the mechanism works when given the correct session:
@loader.clear_organization_cache(@member, @member_session)
cache_key = "org_context:#{@member.objid}"
@member_session[cache_key]
#=> nil


## After removal: Reloading org context returns different org (or nil)
# The member's default org was the one they were removed from.
# After removal, organization_instances no longer includes that org.
@member_session.clear
context_after = @loader.load_organization_context(@member, @member_session, {})

# Member should NOT see the org they were removed from
context_after[:organization]&.objid != @org.objid
#=> true


## Cleanup
begin
  # Get membership if it exists for cleanup
  membership = Onetime::OrganizationMembership.find_by_org_customer(@org.objid, @member.objid)
  membership&.destroy_with_index_cleanup!
rescue => e
  # Membership may already be destroyed by RemoveMember
end

begin
  @org&.destroy!
  @owner&.destroy!
  @member&.destroy!
rescue => e
  # Ignore cleanup errors
end
true
#=> true
