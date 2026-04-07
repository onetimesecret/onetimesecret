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
@session.delete("org_context:#{@owner.objid}")
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
@session.delete("org_context:#{@owner.objid}")
@env = { 'HTTP_O_ORGANIZATION_ID' => @org3.objid }
context = @strategy.load_organization_context(@owner, @session, @env)
context[:organization]&.objid
#=> @org1.objid

## Verifies customer is NOT a member of org3 (security precondition)
@org3.member?(@owner)
#=> false

## Header with unauthorized org does not expose org3 data
@session = {}
@session.delete("org_context:#{@owner.objid}")
@env = { 'HTTP_O_ORGANIZATION_ID' => @org3.objid }
context = @strategy.load_organization_context(@owner, @session, @env)
context[:organization]&.objid != @org3.objid
#=> true


# =============================================================================
# O-Organization-ID Header: Invalid Org ID
# =============================================================================

## Header with non-existent org ID: Falls back to default
@session = {}
@session.delete("org_context:#{@owner.objid}")
@env = { 'HTTP_O_ORGANIZATION_ID' => 'nonexistent-org-id-12345' }
context = @strategy.load_organization_context(@owner, @session, @env)
context[:organization]&.objid
#=> @org1.objid

## Header with empty string: Falls back to default
@session = {}
@session.delete("org_context:#{@owner.objid}")
@env = { 'HTTP_O_ORGANIZATION_ID' => '' }
context = @strategy.load_organization_context(@owner, @session, @env)
context[:organization]&.objid
#=> @org1.objid

## Header with nil value: Falls back to default
@session = {}
@session.delete("org_context:#{@owner.objid}")
@env = { 'HTTP_O_ORGANIZATION_ID' => nil }
context = @strategy.load_organization_context(@owner, @session, @env)
context[:organization]&.objid
#=> @org1.objid


# =============================================================================
# O-Organization-ID Header: Absent (Existing Behavior)
# =============================================================================

## No header with session selection: Uses session org
@session = { 'organization_id' => @org2.objid }
@session.delete("org_context:#{@owner.objid}")
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
# These tests verify that header-based org switching works correctly even when
# the cache is warm. The cache should NOT prevent header from taking effect.

## Rapid switch: First request warms cache with org1
@rapid_session = {}
@env1 = { 'HTTP_O_ORGANIZATION_ID' => @org1.objid }
@context1 = @strategy.load_organization_context(@owner, @rapid_session, @env1)
@context1[:organization]&.objid
#=> @org1.objid

## Rapid switch: Verify cache was warmed (precondition for next test)
@cache_key = "org_context:#{@owner.objid}"
@rapid_session[@cache_key].nil?
#=> false

## Rapid switch: Second request with DIFFERENT header (cache still warm) uses new header
# This is the critical test - header must override warm cache
@env2 = { 'HTTP_O_ORGANIZATION_ID' => @org2.objid }
@context2 = @strategy.load_organization_context(@owner, @rapid_session, @env2)
@context2[:organization]&.objid
#=> @org2.objid

## Rapid switch: Third request back to org1 (cache has org2) uses org1 from header
@env3 = { 'HTTP_O_ORGANIZATION_ID' => @org1.objid }
@context3 = @strategy.load_organization_context(@owner, @rapid_session, @env3)
@context3[:organization]&.objid
#=> @org1.objid

## Rapid switch: All three requests resolved to correct org per header
[@context1[:organization_id], @context2[:organization_id], @context3[:organization_id]]
#=> [@org1.objid, @org2.objid, @org1.objid]


# =============================================================================
# Header Bypasses Warm Cache (Explicit Verification)
# =============================================================================
# This section explicitly tests that headers take precedence over cached context.

## Cache bypass: Warm cache with org1 (no header, session-based)
@bypass_session = { 'organization_id' => @org1.objid }
@env_no_header = {}
@context_cached = @strategy.load_organization_context(@owner, @bypass_session, @env_no_header)
@context_cached[:organization]&.objid
#=> @org1.objid

## Cache bypass: Verify cache is now warm with org1
@bypass_cache_key = "org_context:#{@owner.objid}"
@bypass_session[@bypass_cache_key]&.dig(:organization_id) == @org1.objid
#=> true

## Cache bypass: Header for org2 must override warm cache containing org1
@env_header_org2 = { 'HTTP_O_ORGANIZATION_ID' => @org2.objid }
@context_header_override = @strategy.load_organization_context(@owner, @bypass_session, @env_header_org2)
@context_header_override[:organization]&.objid
#=> @org2.objid

## Cache bypass: Confirm header value differs from what was cached
[@bypass_session[@bypass_cache_key]&.dig(:organization_id), @context_header_override[:organization_id]]
#=> [@org2.objid, @org2.objid]


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
@session.delete("org_context:#{@owner.objid}")
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
@session.delete("org_context:#{@owner.objid}")
@env = { 'HTTP_O_ORGANIZATION_ID' => "  #{@org2.objid}  " }
context = @strategy.load_organization_context(@owner, @session, @env)
context[:organization]&.objid
#=> @org1.objid

## Header with CRLF injection attempt: Falls back to default (invalid ID)
@session = {}
@session.delete("org_context:#{@owner.objid}")
@env = { 'HTTP_O_ORGANIZATION_ID' => "#{@org2.objid}\r\nX-Injected: true" }
context = @strategy.load_organization_context(@owner, @session, @env)
context[:organization]&.objid
#=> @org1.objid

## Header with null byte injection: Falls back to default (invalid ID)
@session = {}
@session.delete("org_context:#{@owner.objid}")
@env = { 'HTTP_O_ORGANIZATION_ID' => "#{@org2.objid}\x00malicious" }
context = @strategy.load_organization_context(@owner, @session, @env)
context[:organization]&.objid
#=> @org1.objid


# =============================================================================
# Caching Behavior with Headers
# =============================================================================

## Cache is created after header-based load
@session = {}
@env = { 'HTTP_O_ORGANIZATION_ID' => @org1.objid }
@context_cached = @strategy.load_organization_context(@owner, @session, @env)
@cache_key = "org_context:#{@owner.objid}"
@session[@cache_key].nil?
#=> false

## Header override works after clearing cache
@session.delete(@cache_key)
@env = { 'HTTP_O_ORGANIZATION_ID' => @org2.objid }
@context_after_clear = @strategy.load_organization_context(@owner, @session, @env)
@context_after_clear[:organization]&.objid
#=> @org2.objid


# =============================================================================
# Cleanup
# =============================================================================

## Cleanup test data
[@org1, @org2, @org3, @owner, @outsider].each do |obj|
  obj.destroy! if obj&.respond_to?(:destroy!) && obj.exists?
end
true
#=> true
