# try/unit/auth/organization_header_try.rb
#
# frozen_string_literal: true

#
# Integration tests for O-Organization-ID header support in OrganizationLoader
#
# Tests the header-based organization context sync between frontend SPA and backend:
# - Header present + valid org + customer is member -> uses header org
# - Header present + valid org + customer NOT member -> falls back to session
# - Header present + invalid org ID -> falls back to session
# - Header absent -> uses existing session logic
# - Rapid org switches (header changes) -> each request uses correct context
#
# The O-Organization-ID header allows the frontend to specify which organization
# context should be used for each request, enabling instant org switching without
# a round-trip session update.
#

require_relative '../../support/test_helpers'

OT.boot! :test

# Create test strategy class that includes OrganizationLoader
require 'onetime/application/organization_loader'

class TestAuthStrategy
  include Onetime::Application::OrganizationLoader
end

@strategy = TestAuthStrategy.new

# Setup test data with unique identifiers
@test_suffix = "#{Familia.now.to_i}_#{rand(10000)}"
@owner = Onetime::Customer.create!(email: generate_unique_test_email("header_owner"))

# Create two organizations the owner is a member of
@org1 = Onetime::Organization.create!('Header Test Org 1', @owner, generate_unique_test_email("header_contact1"))
@org1.is_default = true
@org1.save

@org2 = Onetime::Organization.create!('Header Test Org 2', @owner, generate_unique_test_email("header_contact2"))

# Create a third organization the owner is NOT a member of
@outsider = Onetime::Customer.create!(email: generate_unique_test_email("header_outsider"))
@org3 = Onetime::Organization.create!('Header Test Org 3', @outsider, generate_unique_test_email("header_contact3"))


# =============================================================================
# O-Organization-ID Header: Valid Org + Customer is Member
# =============================================================================

## Header with valid org ID where customer is member: Uses header org
@session = {}
@env = { 'HTTP_O_ORGANIZATION_ID' => @org2.objid }
context = @strategy.load_organization_context(@owner, @session, @env)
context[:organization]&.objid
#=> @org2.objid

## Header takes priority over session selection
@session = { 'organization_id' => @org1.objid }
@env = { 'HTTP_O_ORGANIZATION_ID' => @org2.objid }
context = @strategy.load_organization_context(@owner, @session, @env)
context[:organization]&.objid
#=> @org2.objid

## Header takes priority over default organization (org1 is default but org2 header wins)
@session = {}
@env = { 'HTTP_O_ORGANIZATION_ID' => @org2.objid }
context = @strategy.load_organization_context(@owner, @session, @env)
[@org1.is_default, context[:organization]&.objid == @org2.objid]
#=> [true, true]


# =============================================================================
# O-Organization-ID Header: Valid Org + Customer NOT Member (Security)
# =============================================================================

## Header with valid org ID but customer not a member: Falls back to default
@session = {}
@env = { 'HTTP_O_ORGANIZATION_ID' => @org3.objid }
context = @strategy.load_organization_context(@owner, @session, @env)
context[:organization]&.objid
#=> @org1.objid

## Verifies customer is NOT a member of org3 (security precondition)
@org3.member?(@owner)
#=> false

## Header with unauthorized org does not expose org3 data
@session = {}
@env = { 'HTTP_O_ORGANIZATION_ID' => @org3.objid }
context = @strategy.load_organization_context(@owner, @session, @env)
context[:organization]&.objid != @org3.objid
#=> true


# =============================================================================
# O-Organization-ID Header: Invalid Org ID
# =============================================================================

## Header with non-existent org ID: Falls back to default
@session = {}
@env = { 'HTTP_O_ORGANIZATION_ID' => 'nonexistent-org-id-12345' }
context = @strategy.load_organization_context(@owner, @session, @env)
context[:organization]&.objid
#=> @org1.objid

## Header with empty string: Falls back to default
@session = {}
@env = { 'HTTP_O_ORGANIZATION_ID' => '' }
context = @strategy.load_organization_context(@owner, @session, @env)
context[:organization]&.objid
#=> @org1.objid

## Header with nil value: Falls back to default
@session = {}
@env = { 'HTTP_O_ORGANIZATION_ID' => nil }
context = @strategy.load_organization_context(@owner, @session, @env)
context[:organization]&.objid
#=> @org1.objid


# =============================================================================
# O-Organization-ID Header: Absent (Existing Behavior)
# =============================================================================

## No header with session selection: Uses session org
@session = { 'organization_id' => @org2.objid }
@env = {}
context = @strategy.load_organization_context(@owner, @session, @env)
context[:organization]&.objid
#=> @org2.objid

## No header and no session: Uses default organization
@session = {}
@env = {}
context = @strategy.load_organization_context(@owner, @session, @env)
context[:organization]&.objid
#=> @org1.objid


# =============================================================================
# Rapid Organization Switches (Simulating SPA Navigation)
# =============================================================================
# These tests verify that header-based org switching works correctly on one
# session: each request resolves its own header and leaves nothing behind
# in the session for the next one.

## Rapid switch: First request with org1 header
@rapid_session = {}
@env1 = { 'HTTP_O_ORGANIZATION_ID' => @org1.objid }
@context1 = @strategy.load_organization_context(@owner, @rapid_session, @env1)
@context1[:organization]&.objid
#=> @org1.objid

## Rapid switch: The header-based load wrote nothing to the session
@rapid_session
#=> {}

## Rapid switch: Second request with DIFFERENT header uses new header
@env2 = { 'HTTP_O_ORGANIZATION_ID' => @org2.objid }
@context2 = @strategy.load_organization_context(@owner, @rapid_session, @env2)
@context2[:organization]&.objid
#=> @org2.objid

## Rapid switch: Third request back to org1 uses org1 from header
@env3 = { 'HTTP_O_ORGANIZATION_ID' => @org1.objid }
@context3 = @strategy.load_organization_context(@owner, @rapid_session, @env3)
@context3[:organization]&.objid
#=> @org1.objid

## Rapid switch: All three requests resolved to correct org per header
[@context1[:organization_id], @context2[:organization_id], @context3[:organization_id]]
#=> [@org1.objid, @org2.objid, @org1.objid]


# =============================================================================
# Header vs. Explicit Session Selection
# =============================================================================
# The header decides the request it is on. It does not change the session
# selection, which is what a later request without a header (a page load)
# resolves to.

## Header vs selection: session selects org1, no header resolves org1
@bypass_session = { 'organization_id' => @org1.objid }
@env_no_header = {}
@context_selected = @strategy.load_organization_context(@owner, @bypass_session, @env_no_header)
@context_selected[:organization]&.objid
#=> @org1.objid

## Header vs selection: Header for org2 overrides the selection for that request
@env_header_org2 = { 'HTTP_O_ORGANIZATION_ID' => @org2.objid }
@context_header_override = @strategy.load_organization_context(@owner, @bypass_session, @env_header_org2)
@context_header_override[:organization]&.objid
#=> @org2.objid

## Header vs selection: The header left the session selection as it was
@bypass_session
#=> { 'organization_id' => @org1.objid }

## Header vs selection: The next request without a header is back on the selection
@context_after_header = @strategy.load_organization_context(@owner, @bypass_session, @env_no_header)
@context_after_header[:organization]&.objid
#=> @org1.objid


# =============================================================================
# Edge Cases
# =============================================================================

## Anonymous customer: Returns empty context (header ignored)
@anon = Onetime::Customer.new(role: 'anonymous')
@env = { 'HTTP_O_ORGANIZATION_ID' => @org1.objid }
context = @strategy.load_organization_context(@anon, {}, @env)
context
#=> {}

## Nil customer: Returns empty context (header ignored)
context = @strategy.load_organization_context(nil, {}, { 'HTTP_O_ORGANIZATION_ID' => @org1.objid })
context
#=> {}

## Header with path traversal attempt: Falls back gracefully without crash
@session = {}
@env = { 'HTTP_O_ORGANIZATION_ID' => '../../../etc/passwd' }
context = @strategy.load_organization_context(@owner, @session, @env)
context[:organization]&.objid
#=> @org1.objid


# =============================================================================
# Header Input Sanitization Edge Cases
# =============================================================================
# These tests verify that malformed or malicious header values are handled safely.

## Header with leading/trailing whitespace: Falls back to default (invalid for Redis lookup)
@session = {}
@env = { 'HTTP_O_ORGANIZATION_ID' => "  #{@org2.objid}  " }
context = @strategy.load_organization_context(@owner, @session, @env)
context[:organization]&.objid
#=> @org1.objid

## Header with CRLF injection attempt: Falls back to default (invalid ID)
@session = {}
@env = { 'HTTP_O_ORGANIZATION_ID' => "#{@org2.objid}\r\nX-Injected: true" }
context = @strategy.load_organization_context(@owner, @session, @env)
context[:organization]&.objid
#=> @org1.objid

## Header with null byte injection: Falls back to default (invalid ID)
@session = {}
@env = { 'HTTP_O_ORGANIZATION_ID' => "#{@org2.objid}\x00malicious" }
context = @strategy.load_organization_context(@owner, @session, @env)
context[:organization]&.objid
#=> @org1.objid


# =============================================================================
# Membership Is Checked on Every Header Request
# =============================================================================

## A header-based load is not remembered: nothing is written to the session
@session = {}
@env = { 'HTTP_O_ORGANIZATION_ID' => @org2.objid }
@context_first = @strategy.load_organization_context(@owner, @session, @env)
[@context_first[:organization]&.objid, @session]
#=> [@org2.objid, {}]

## A membership removed between two requests is refused on the second
@member = Onetime::Customer.create!(email: generate_unique_test_email("header_member"))
@org2.add_members_instance(@member, through_attrs: { role: 'member' })
@member_session = {}
@member_before = @strategy.load_organization_context(@member, @member_session, @env)
@org2.remove_members_instance(@member)
@member_after = @strategy.load_organization_context(@member, @member_session, @env)
[@member_before[:organization]&.objid, @member_after[:organization]&.objid]
#=> [@org2.objid, nil]

## Clean up the removed member
@member.destroy!
true
#=> true


# =============================================================================
# Cleanup
# =============================================================================

## Cleanup test data
[@org1, @org2, @org3, @owner, @outsider].each do |obj|
  obj.destroy! if obj&.respond_to?(:destroy!) && obj.exists?
end
true
#=> true
