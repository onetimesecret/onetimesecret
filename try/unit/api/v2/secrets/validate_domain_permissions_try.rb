# try/unit/api/v2/secrets/validate_domain_permissions_try.rb
#
# frozen_string_literal: true

# Tests for V2::Logic::Secrets::BaseSecretAction#validate_domain_permissions
#
# Rules (issue #3073):
# - Domain owner / org member: always permitted, regardless of toggle.
# - Authenticated non-owner: never permitted, regardless of toggle.
#   The Homepage Secrets toggle gates anonymous public intake; it does
#   not authorize unrelated authenticated users to share via someone
#   else's domain.
# - Anonymous on a custom domain: gated by the Homepage Secrets toggle.
# - Anonymous on canonical with share_domain set to a custom domain:
#   not permitted.
#
# Permission denials raise Onetime::Forbidden (HTTP 403), not FormError (422),
# because they reflect access-control decisions rather than form validation.

require_relative '../../../../support/test_helpers'

OT.boot! :test, false

require 'v2/logic'

@timestamp = Familia.now.to_i

@owner_email = generate_unique_test_email("domain_owner")
@other_email = generate_unique_test_email("domain_other")

@owner = Onetime::Customer.create!(email: @owner_email)
@other = Onetime::Customer.create!(email: @other_email)

@org = Onetime::Organization.create!("DomainPerm Org #{@timestamp}", @owner, "orgperm_#{@timestamp}@test.com")

@domain = Onetime::CustomDomain.create!("validate-perms-#{@timestamp}.example.com", @org.objid)

# Helper to set public homepage setting.
# Writes through HomepageConfig (the authoritative store post-#3026); the
# legacy brand[allow_public_homepage] path no longer affects the predicate.
def set_public_homepage(domain, enabled)
  Onetime::CustomDomain::HomepageConfig.upsert(domain_id: domain.identifier, enabled: enabled)
end

# Helper to create a mock ConcealSecret logic instance for testing
#
# Passes domain_strategy and display_domain through metadata so that
# Logic::Base#initialize -> extract_domain_context exercises the real
# init chain (instead of setting attributes after construction).
def create_test_logic(customer, share_domain_value: nil, domain_strategy: nil, display_domain: nil)
  sess = MockSession.new
  metadata = {}
  metadata[:domain_strategy] = domain_strategy if domain_strategy
  metadata[:display_domain]  = display_domain  if display_domain
  auth_method = customer.nil? ? 'anonymous' : 'basic'
  strategy_result = MockStrategyResult.new(session: sess, user: customer, auth_method: auth_method, metadata: metadata)
  params = {
    'secret' => {
      'secret' => 'test secret',
      'ttl' => '3600',
      'share_domain' => share_domain_value
    }
  }
  V2::Logic::Secrets::ConcealSecret.new(strategy_result, params, 'en')
end

## Domain owner can access their own domain from canonical domain
# No domain_strategy in metadata -> canonical domain (domain_strategy is nil)
logic = create_test_logic(@owner, share_domain_value: @domain.display_domain)
begin
  # Call validate_domain_access which internally calls validate_domain_permissions
  logic.send(:validate_domain_access, @domain.display_domain)
  :success
rescue Onetime::FormError => e
  e.message
end
#=> :success

## Non-owner on canonical domain raises Forbidden matching domain permission message
# No domain_strategy in metadata -> canonical domain (domain_strategy is nil)
logic = create_test_logic(@other, share_domain_value: @domain.display_domain)
begin
  logic.send(:validate_domain_access, @domain.display_domain)
  :success
rescue Onetime::Forbidden => e
  e.message
end
#=~> /You do not have permission to use domain:/

## Error message includes the actual domain name
# No domain_strategy in metadata -> canonical domain (domain_strategy is nil)
logic = create_test_logic(@other, share_domain_value: @domain.display_domain)
begin
  logic.send(:validate_domain_access, @domain.display_domain)
  :success
rescue Onetime::Forbidden => e
  e.message.include?("validate-perms")
end
#=> true

## Authenticated non-owner on custom domain with public sharing enabled is rejected
# The Homepage Secrets toggle gates anonymous traffic; an authenticated
# unrelated user does not get to share via someone else's domain just
# because the public-intake toggle is on.
set_public_homepage(@domain, true)
logic = create_test_logic(@other,
  share_domain_value: @domain.display_domain,
  domain_strategy: :custom,
  display_domain: @domain.display_domain)
begin
  logic.send(:validate_domain_access, @domain.display_domain)
  :success
rescue Onetime::Forbidden => e
  e.message
end
#=~> /You do not have permission to use domain:/

## Authenticated non-owner on custom domain with public sharing disabled is rejected with permission error
# Was previously reported as "Public sharing disabled" — corrected to
# the permission error since the caller is authenticated.
set_public_homepage(@domain, false)
logic = create_test_logic(@other,
  share_domain_value: @domain.display_domain,
  domain_strategy: :custom,
  display_domain: @domain.display_domain)
begin
  logic.send(:validate_domain_access, @domain.display_domain)
  :success
rescue Onetime::Forbidden => e
  e.message
end
#=~> /You do not have permission to use domain:/

## Anonymous on custom domain with public sharing enabled is allowed
set_public_homepage(@domain, true)
logic = create_test_logic(nil,
  share_domain_value: @domain.display_domain,
  domain_strategy: :custom,
  display_domain: @domain.display_domain)
begin
  logic.send(:validate_domain_access, @domain.display_domain)
  :success
rescue Onetime::Forbidden => e
  e.message
end
#=> :success

## Anonymous on custom domain with public sharing disabled is rejected with public-sharing-disabled
set_public_homepage(@domain, false)
logic = create_test_logic(nil,
  share_domain_value: @domain.display_domain,
  domain_strategy: :custom,
  display_domain: @domain.display_domain)
begin
  logic.send(:validate_domain_access, @domain.display_domain)
  :success
rescue Onetime::Forbidden => e
  e.message
end
#=~> /Public sharing disabled for domain:/

## Owner on canonical domain is allowed regardless of public sharing setting
# No domain_strategy in metadata -> canonical domain (domain_strategy is nil)
set_public_homepage(@domain, false)
logic = create_test_logic(@owner, share_domain_value: @domain.display_domain)
begin
  logic.send(:validate_domain_access, @domain.display_domain)
  :success
rescue Onetime::Forbidden => e
  e.message
end
#=> :success

## Issue #3073: Owner on custom domain with public sharing disabled is allowed
# Regression for the bug where the Homepage Secrets toggle blocked authenticated
# domain owner requests on the custom domain itself.
set_public_homepage(@domain, false)
logic = create_test_logic(@owner,
  share_domain_value: @domain.display_domain,
  domain_strategy: :custom,
  display_domain: @domain.display_domain)
begin
  logic.send(:validate_domain_access, @domain.display_domain)
  :success
rescue Onetime::Forbidden => e
  e.message
end
#=> :success

## Issue #3073: Owner on custom domain with public sharing enabled is also allowed
set_public_homepage(@domain, true)
logic = create_test_logic(@owner,
  share_domain_value: @domain.display_domain,
  domain_strategy: :custom,
  display_domain: @domain.display_domain)
begin
  logic.send(:validate_domain_access, @domain.display_domain)
  :success
rescue Onetime::Forbidden => e
  e.message
end
#=> :success

# Teardown
@domain.destroy!
@org.destroy!
@owner.destroy!
@other.destroy!
