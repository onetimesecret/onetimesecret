# try/unit/api/v3/secrets/validate_domain_permissions_try.rb
#
# frozen_string_literal: true

# Tests for V3::Logic::Secrets::ConcealSecret domain permission behavior.
#
# V3::Logic::Secrets::ConcealSecret < V2::Logic::Secrets::ConcealSecret, so the
# domain-permission rules are inherited verbatim. These tests verify that
# inheritance is wired correctly and document V3's two extra surfaces:
#
# 1. Guest route gating (require_guest_route_enabled!(:conceal)) runs in
#    raise_concerns BEFORE the inherited validate_domain_permissions. It only
#    activates for anonymous + auth_method='noauth' callers.
# 2. /api/v3/secret/conceal uses sessionauth at the route level, so anonymous
#    callers never reach this logic via that route. Anonymous traffic only
#    flows through /api/v3/guest/secret/conceal.
#
# Permission denials raise Onetime::Forbidden (HTTP 403). Guest gate denials
# raise Onetime::GuestRoutesDisabled (also HTTP 403) but with a distinct
# error code.

require_relative '../../../../support/test_helpers'

OT.boot! :test, false

require 'v3/logic'

@timestamp = Familia.now.to_i

@owner_email = generate_unique_test_email("v3_domain_owner")
@other_email = generate_unique_test_email("v3_domain_other")

@owner = Onetime::Customer.create!(email: @owner_email)
@other = Onetime::Customer.create!(email: @other_email)

@org = Onetime::Organization.create!("V3DomainPerm Org #{@timestamp}", @owner, "v3orgperm_#{@timestamp}@test.com")

@domain = Onetime::CustomDomain.create!("v3-validate-perms-#{@timestamp}.example.com", @org.objid)

# Helper to set public homepage setting.
# Writes through HomepageConfig (the authoritative store post-#3026); the
# legacy brand[allow_public_homepage] path no longer affects the predicate.
def set_public_homepage(domain, enabled)
  Onetime::CustomDomain::HomepageConfig.upsert(domain_id: domain.identifier, enabled: enabled)
end

# Helper to create a V3 ConcealSecret logic instance.
#
# Pass customer=nil to simulate an anonymous caller; auth_method defaults to
# 'noauth' for anonymous (matching production NoAuthStrategy) and 'basic' for
# authenticated callers, but can be overridden to test the guest gate.
def create_test_logic(customer, share_domain_value: nil, domain_strategy: nil, display_domain: nil, auth_method: nil)
  sess = MockSession.new
  metadata = {}
  metadata[:domain_strategy] = domain_strategy if domain_strategy
  metadata[:display_domain]  = display_domain  if display_domain
  resolved_auth_method = auth_method || (customer.nil? ? 'noauth' : 'basic')
  strategy_result = MockStrategyResult.new(session: sess, user: customer, auth_method: resolved_auth_method, metadata: metadata)
  params = {
    'secret' => {
      'secret' => 'test secret',
      'ttl' => '3600',
      'share_domain' => share_domain_value
    }
  }
  V3::Logic::Secrets::ConcealSecret.new(strategy_result, params, 'en')
end

# Helper to temporarily override guest_routes config (mirrors the integration
# helper at try/integration/api/v3/guest_routes_disabled_try.rb).
def with_guest_routes_config(config_overrides)
  original_conf = OT.conf
  test_conf = Onetime::Config.deep_clone(original_conf)
  test_conf['site'] ||= {}
  test_conf['site']['interface'] ||= {}
  test_conf['site']['interface']['api'] ||= {}
  test_conf['site']['interface']['api']['guest_routes'] = config_overrides
  OT.instance_variable_set(:@conf, test_conf)
  yield
ensure
  OT.instance_variable_set(:@conf, original_conf)
end

# INHERITED validate_domain_permissions BEHAVIOR (mirrors V2 coverage)

## V3: Owner can access their own domain from canonical domain
logic = create_test_logic(@owner, share_domain_value: @domain.display_domain)
begin
  logic.send(:validate_domain_access, @domain.display_domain)
  :success
rescue Onetime::Forbidden => e
  e.message
end
#=> :success

## V3: Authenticated non-owner on canonical domain raises Forbidden
logic = create_test_logic(@other, share_domain_value: @domain.display_domain)
begin
  logic.send(:validate_domain_access, @domain.display_domain)
  :success
rescue Onetime::Forbidden => e
  e.message
end
#=~> /You do not have permission to use domain:/

## V3: Authenticated non-owner on custom domain with public sharing enabled is rejected
# Inherits the corrected V2 behavior: the toggle gates anonymous traffic only.
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

## V3: Authenticated non-owner on custom domain with public sharing disabled is rejected with permission error
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

## V3: Anonymous on custom domain with public sharing enabled is allowed
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

## V3: Anonymous on custom domain with public sharing disabled is rejected with public-sharing-disabled
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

## V3 issue #3073: Owner on custom domain with public sharing disabled is allowed
# Regression: the Homepage Secrets toggle must not block authenticated owners.
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

## V3 issue #3073: Owner on custom domain with public sharing enabled is also allowed
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

# V3-SPECIFIC GUEST ROUTE GATING

## V3: Guest gate raises GuestRoutesDisabled when conceal is disabled site-wide
# Anonymous caller with auth_method='noauth' is the only context the gate
# applies to. This runs in raise_concerns BEFORE validate_domain_permissions.
with_guest_routes_config({ 'enabled' => true, 'conceal' => false }) do
  logic = create_test_logic(nil, auth_method: 'noauth')
  begin
    logic.send(:require_guest_route_enabled!, :conceal)
    :success
  rescue Onetime::GuestRoutesDisabled => e
    e.code
  end
end
#=> "GUEST_CONCEAL_DISABLED"

## V3: Guest gate raises GuestRoutesDisabled when guest routes globally disabled
with_guest_routes_config({ 'enabled' => false }) do
  logic = create_test_logic(nil, auth_method: 'noauth')
  begin
    logic.send(:require_guest_route_enabled!, :conceal)
    :success
  rescue Onetime::GuestRoutesDisabled => e
    e.code
  end
end
#=> "GUEST_ROUTES_DISABLED"

## V3: Guest gate passes through when conceal is enabled
with_guest_routes_config({ 'enabled' => true, 'conceal' => true }) do
  logic = create_test_logic(nil, auth_method: 'noauth')
  logic.send(:require_guest_route_enabled!, :conceal)
end
#=> true

## V3: Guest gate is skipped for authenticated callers regardless of config
# Even if guest_routes.conceal is false, an authenticated caller bypasses the
# gate (guest_context? requires anonymous_user? && auth_method=='noauth').
with_guest_routes_config({ 'enabled' => true, 'conceal' => false }) do
  logic = create_test_logic(@owner, auth_method: 'basic')
  logic.send(:require_guest_route_enabled!, :conceal)
end
#=> true

## V3: Guest gate is skipped for anonymous caller with non-noauth auth_method
# Defensive: only the canonical noauth path triggers gating.
with_guest_routes_config({ 'enabled' => true, 'conceal' => false }) do
  logic = create_test_logic(nil, auth_method: 'session')
  logic.send(:require_guest_route_enabled!, :conceal)
end
#=> true

# Teardown
@domain.destroy!
@org.destroy!
@owner.destroy!
@other.destroy!
