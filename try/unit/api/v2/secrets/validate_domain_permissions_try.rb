# try/unit/api/v2/secrets/validate_domain_permissions_try.rb
#
# frozen_string_literal: true

# Tests for V2::Logic::Secrets::BaseSecretAction#validate_domain_permissions
#
# The validate_domain_permissions method enforces:
# - On custom domains: allows access if public sharing is enabled
# - On canonical domain: requires domain ownership
#
# Fix verified: Task #32 added raise_form_error for non-owners on canonical domain

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

# Helper to set public homepage setting
def set_public_homepage(domain, enabled)
  domain.brand['allow_public_homepage'] = enabled
  # Clear memoized brand_settings
  domain.instance_variable_set(:@brand_settings, nil)
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
  strategy_result = MockStrategyResult.new(session: sess, user: customer, metadata: metadata)
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

## Non-owner on canonical domain raises FormError matching domain permission message
# No domain_strategy in metadata -> canonical domain (domain_strategy is nil)
logic = create_test_logic(@other, share_domain_value: @domain.display_domain)
begin
  logic.send(:validate_domain_access, @domain.display_domain)
  :success
rescue Onetime::FormError => e
  e.message
end
#=~> /You do not have permission to use domain:/

## Error message includes the actual domain name
# No domain_strategy in metadata -> canonical domain (domain_strategy is nil)
logic = create_test_logic(@other, share_domain_value: @domain.display_domain)
begin
  logic.send(:validate_domain_access, @domain.display_domain)
  :success
rescue Onetime::FormError => e
  e.message.include?("validate-perms")
end
#=> true

## Non-owner on custom domain with public sharing enabled is allowed
set_public_homepage(@domain, true)
logic = create_test_logic(@other,
  share_domain_value: @domain.display_domain,
  domain_strategy: :custom,
  display_domain: @domain.display_domain)
begin
  logic.send(:validate_domain_access, @domain.display_domain)
  :success
rescue Onetime::FormError => e
  e.message
end
#=> :success

## Non-owner on custom domain with public sharing disabled is rejected
set_public_homepage(@domain, false)
logic = create_test_logic(@other,
  share_domain_value: @domain.display_domain,
  domain_strategy: :custom,
  display_domain: @domain.display_domain)
begin
  logic.send(:validate_domain_access, @domain.display_domain)
  :success
rescue Onetime::FormError => e
  e.message
end
#=~> /Public sharing disabled for domain:/

## Owner can always access their domain regardless of public sharing setting
# No domain_strategy in metadata -> canonical domain (domain_strategy is nil)
set_public_homepage(@domain, false)
logic = create_test_logic(@owner, share_domain_value: @domain.display_domain)
begin
  logic.send(:validate_domain_access, @domain.display_domain)
  :success
rescue Onetime::FormError => e
  e.message
end
#=> :success

# Teardown
@domain.destroy!
@org.destroy!
@owner.destroy!
@other.destroy!
