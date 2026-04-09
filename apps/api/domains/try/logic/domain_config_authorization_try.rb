# apps/api/domains/try/logic/domain_config_authorization_try.rb
#
# frozen_string_literal: true

# Tests for shared domain config authorization logic
#
# Both ApiConfig::Base and HomepageConfig::Base implement the same
# authorization model:
#   1. load_custom_domain - find domain by extid
#   2. load_organization_for_domain - find org from domain's org_id
#   3. verify_organization_owner - check user is org owner (or colonel)
#   4. verify entitlement - check org has the required feature
#   5. authorize wrapper - full chain (load domain, org, verify, entitle)
#   6. parse_boolean - coerce various inputs to boolean
#
# The only differences are the entitlement names (api_access vs
# homepage_secrets) and the authorize method names.

require_relative '../../../../../try/support/test_helpers'

OT.boot! :test

require 'onetime/models/custom_domain/api_config'
require 'onetime/models/custom_domain/homepage_config'
require 'apps/api/domains/logic/base'
require 'apps/api/domains/logic/api_config/base'
require 'apps/api/domains/logic/homepage_config/base'

Familia.dbclient.flushdb
OT.info "Cleaned Redis for domain config authorization tests"

# Create test data: owner, non-owner, org, domain
@test_id = SecureRandom.hex(4)
@owner = Onetime::Customer.create!(email: "owner_#{@test_id}@example.com")
@non_owner = Onetime::Customer.create!(email: "nonowner_#{@test_id}@example.com")
@org = Onetime::Organization.create!(
  "Auth Test Org #{@test_id}",
  @owner,
  "billing+authtest+#{@test_id}@onetimesecret.com"
)
@domain = Onetime::CustomDomain.create!("authtest-#{@test_id}.example.com", @org.objid)

# Helper to create a logic instance for a given Base class and customer.
# Logic::Base requires (strategy_result, params, locale).
def make_logic(klass, customer)
  strategy_result = MockStrategyResult.authenticated(customer)
  klass.new(strategy_result, {}, 'en')
end

# Build logic instances for both config types, as both owner and non-owner
@api_logic_owner = make_logic(DomainsAPI::Logic::ApiConfig::Base, @owner)
@api_logic_non_owner = make_logic(DomainsAPI::Logic::ApiConfig::Base, @non_owner)
@homepage_logic_owner = make_logic(DomainsAPI::Logic::HomepageConfig::Base, @owner)
@homepage_logic_non_owner = make_logic(DomainsAPI::Logic::HomepageConfig::Base, @non_owner)

# ============================================================
# parse_boolean
# ============================================================

## parse_boolean returns true for boolean true
@api_logic_owner.send(:parse_boolean, true)
#=> true

## parse_boolean returns true for string 'true'
@api_logic_owner.send(:parse_boolean, 'true')
#=> true

## parse_boolean returns true for string '1'
@api_logic_owner.send(:parse_boolean, '1')
#=> true

## parse_boolean returns true for integer 1
@api_logic_owner.send(:parse_boolean, 1)
#=> true

## parse_boolean returns false for boolean false
@api_logic_owner.send(:parse_boolean, false)
#=> false

## parse_boolean returns false for nil
@api_logic_owner.send(:parse_boolean, nil)
#=> false

## parse_boolean returns false for string 'false'
@api_logic_owner.send(:parse_boolean, 'false')
#=> false

## parse_boolean returns false for string '0'
@api_logic_owner.send(:parse_boolean, '0')
#=> false

## parse_boolean returns false for integer 0
@api_logic_owner.send(:parse_boolean, 0)
#=> false

## parse_boolean returns false for empty string
@api_logic_owner.send(:parse_boolean, '')
#=> false

## parse_boolean is consistent across ApiConfig and HomepageConfig
api_results = [true, 'true', '1', 1, false, nil, 'false', '0', 0].map { |v| @api_logic_owner.send(:parse_boolean, v) }
hp_results = [true, 'true', '1', 1, false, nil, 'false', '0', 0].map { |v| @homepage_logic_owner.send(:parse_boolean, v) }
api_results == hp_results
#=> true

# ============================================================
# load_custom_domain
# ============================================================

## load_custom_domain returns domain when found by extid
loaded = @api_logic_owner.send(:load_custom_domain, @domain.extid)
loaded.display_domain
#=> @domain.display_domain

## load_custom_domain raises RecordNotFound for unknown extid
begin
  @api_logic_owner.send(:load_custom_domain, 'nonexistent_extid_abc123')
  'unexpected_success'
rescue Onetime::RecordNotFound
  'not_found'
end
#=> 'not_found'

# ============================================================
# load_organization_for_domain
# ============================================================

## load_organization_for_domain returns org from domain's org_id
org = @api_logic_owner.send(:load_organization_for_domain, @domain)
org.org_id
#=> @org.org_id

## load_organization_for_domain raises RecordNotFound for orphan domain
@orphan_domain = Onetime::CustomDomain.parse("orphan-#{@test_id}.example.com", 'nonexistent_org_id')
@orphan_domain.save
begin
  @api_logic_owner.send(:load_organization_for_domain, @orphan_domain)
  'unexpected_success'
rescue Onetime::RecordNotFound
  'not_found'
end
#=> 'not_found'

# ============================================================
# verify_organization_owner
# ============================================================

## verify_organization_owner passes for org owner
begin
  @api_logic_owner.send(:verify_organization_owner, @org)
  'passed'
rescue Onetime::Forbidden
  'forbidden'
end
#=> 'passed'

## verify_organization_owner raises Forbidden for non-owner
begin
  @api_logic_non_owner.send(:verify_organization_owner, @org)
  'passed'
rescue Onetime::Forbidden
  'forbidden'
end
#=> 'forbidden'

# ============================================================
# Concern module inclusion
# ============================================================

## ApiConfig::Base includes DomainConfigAuthorization concern
DomainsAPI::Logic::ApiConfig::Base.include?(DomainsAPI::Logic::Concerns::DomainConfigAuthorization)
#=> true

## HomepageConfig::Base includes DomainConfigAuthorization concern
DomainsAPI::Logic::HomepageConfig::Base.include?(DomainsAPI::Logic::Concerns::DomainConfigAuthorization)
#=> true

## ApiConfig::Base includes AuthorizationPolicies via concern
DomainsAPI::Logic::ApiConfig::Base.include?(Onetime::Application::AuthorizationPolicies)
#=> true

# ============================================================
# config_entitlement / config_entitlement_error
# ============================================================

## ApiConfig Base returns 'api_access' as config_entitlement
@api_logic_owner.send(:config_entitlement)
#=> 'api_access'

## HomepageConfig Base returns 'homepage_secrets' as config_entitlement
@homepage_logic_owner.send(:config_entitlement)
#=> 'homepage_secrets'

## ApiConfig Base returns correct error message
@api_logic_owner.send(:config_entitlement_error)
#=> 'API configuration requires the api_access entitlement. Please upgrade your plan.'

## HomepageConfig Base returns correct error message
@homepage_logic_owner.send(:config_entitlement_error)
#=> 'Homepage secrets management requires the homepage_secrets entitlement. Please upgrade your plan.'

# ============================================================
# verify_config_entitlement
# ============================================================

# In test mode billing is disabled, so standalone entitlements include
# both api_access and homepage_secrets. We verify the shared method
# returns without error when the entitlement is present.

## verify_config_entitlement passes for ApiConfig (org has api_access in standalone mode)
begin
  @api_logic_owner.send(:verify_config_entitlement, @org)
  'passed'
rescue OT::FormError
  'forbidden'
end
#=> 'passed'

## verify_config_entitlement passes for HomepageConfig (org has homepage_secrets in standalone mode)
begin
  @homepage_logic_owner.send(:verify_config_entitlement, @org)
  'passed'
rescue OT::FormError
  'forbidden'
end
#=> 'passed'

## Both config types have the shared verify_config_entitlement method
[@api_logic_owner.respond_to?(:verify_config_entitlement, true), @homepage_logic_owner.respond_to?(:verify_config_entitlement, true)]
#=> [true, true]

# ============================================================
# authorize_domain_config! (shared concern method)
# ============================================================

## authorize_domain_config! sets custom_domain and organization
@api_config_fresh = make_logic(DomainsAPI::Logic::ApiConfig::Base, @owner)
@api_config_fresh.send(:authorize_domain_config!, @domain.extid)
[@api_config_fresh.custom_domain.display_domain, @api_config_fresh.organization.org_id]
#=> [@domain.display_domain, @org.org_id]

## authorize_domain_config! raises Forbidden for non-owner
begin
  @api_config_non_owner = make_logic(DomainsAPI::Logic::ApiConfig::Base, @non_owner)
  @api_config_non_owner.send(:authorize_domain_config!, @domain.extid)
  'passed'
rescue Onetime::Forbidden
  'forbidden'
end
#=> 'forbidden'

## authorize_domain_config! raises RecordNotFound for missing domain
begin
  @api_config_missing = make_logic(DomainsAPI::Logic::ApiConfig::Base, @owner)
  @api_config_missing.send(:authorize_domain_config!, 'missing_domain_xyz')
  'passed'
rescue Onetime::RecordNotFound
  'not_found'
end
#=> 'not_found'

# ============================================================
# Full authorize wrappers (delegate to authorize_domain_config!)
# ============================================================

## authorize_domain_api! sets custom_domain and organization for owner
@api_owner_fresh = make_logic(DomainsAPI::Logic::ApiConfig::Base, @owner)
@api_owner_fresh.send(:authorize_domain_api!, @domain.extid)
[@api_owner_fresh.custom_domain.display_domain, @api_owner_fresh.organization.org_id]
#=> [@domain.display_domain, @org.org_id]

## authorize_domain_api! raises Forbidden for non-owner
begin
  @api_non_owner_fresh = make_logic(DomainsAPI::Logic::ApiConfig::Base, @non_owner)
  @api_non_owner_fresh.send(:authorize_domain_api!, @domain.extid)
  'passed'
rescue Onetime::Forbidden
  'forbidden'
end
#=> 'forbidden'

## authorize_domain_api! raises RecordNotFound for missing domain
begin
  @api_logic_owner.send(:authorize_domain_api!, 'missing_domain_xyz')
  'passed'
rescue Onetime::RecordNotFound
  'not_found'
end
#=> 'not_found'

## authorize_domain_homepage! sets custom_domain and organization for owner
@hp_owner_fresh = make_logic(DomainsAPI::Logic::HomepageConfig::Base, @owner)
@hp_owner_fresh.send(:authorize_domain_homepage!, @domain.extid)
[@hp_owner_fresh.custom_domain.display_domain, @hp_owner_fresh.organization.org_id]
#=> [@domain.display_domain, @org.org_id]

## authorize_domain_homepage! raises Forbidden for non-owner
begin
  @hp_non_owner_fresh = make_logic(DomainsAPI::Logic::HomepageConfig::Base, @non_owner)
  @hp_non_owner_fresh.send(:authorize_domain_homepage!, @domain.extid)
  'passed'
rescue Onetime::Forbidden
  'forbidden'
end
#=> 'forbidden'

## authorize_domain_homepage! raises RecordNotFound for missing domain
begin
  @homepage_logic_owner.send(:authorize_domain_homepage!, 'missing_domain_xyz')
  'passed'
rescue Onetime::RecordNotFound
  'not_found'
end
#=> 'not_found'

# ============================================================
# Cross-type consistency: same domain works through both auth paths
# ============================================================

## Same domain authorizes through both ApiConfig and HomepageConfig for same owner
@api_cross = make_logic(DomainsAPI::Logic::ApiConfig::Base, @owner)
@hp_cross = make_logic(DomainsAPI::Logic::HomepageConfig::Base, @owner)
@api_cross.send(:authorize_domain_api!, @domain.extid)
@hp_cross.send(:authorize_domain_homepage!, @domain.extid)
[@api_cross.custom_domain.display_domain, @hp_cross.custom_domain.display_domain]
#=> [@domain.display_domain, @domain.display_domain]

# Teardown
Familia.dbclient.flushdb
