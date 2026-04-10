# apps/api/domains/try/logic/domain_config_authorization_try.rb
#
# frozen_string_literal: true

# Tests for shared domain config authorization logic
#
# All four config types (ApiConfig, HomepageConfig, SenderConfig,
# SsoConfig) use the DomainConfigAuthorization concern:
#   1. verify_feature_flag! - check feature flag (if defined)
#   2. load_custom_domain - find domain by extid
#   3. load_organization_for_domain - find org from domain's org_id
#   4. verify_organization_owner - check user is org owner (or colonel)
#   5. verify_config_entitlement - check org has the required entitlement
#   6. authorize_domain_config! - full chain (flag, load, verify, entitle)
#   7. parse_boolean - coerce various inputs to boolean
#
# ApiConfig and HomepageConfig have no feature flag (config_feature_flag
# returns nil). SenderConfig requires custom_mail_enabled and SsoConfig
# requires sso_enabled.

require_relative '../../../../../try/support/test_helpers'

OT.boot! :test

require 'onetime/models/custom_domain/api_config'
require 'onetime/models/custom_domain/homepage_config'
require 'onetime/models/custom_domain/mailer_config'
require 'onetime/models/custom_domain/sso_config'
require 'apps/api/domains/logic/base'
require 'apps/api/domains/logic/api_config/base'
require 'apps/api/domains/logic/homepage_config/base'
require 'apps/api/domains/logic/sender_config/base'
require 'apps/api/domains/logic/sso_config/base'

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

# Build logic instances for all config types, as both owner and non-owner
@api_logic_owner = make_logic(DomainsAPI::Logic::ApiConfig::Base, @owner)
@api_logic_non_owner = make_logic(DomainsAPI::Logic::ApiConfig::Base, @non_owner)
@homepage_logic_owner = make_logic(DomainsAPI::Logic::HomepageConfig::Base, @owner)
@homepage_logic_non_owner = make_logic(DomainsAPI::Logic::HomepageConfig::Base, @non_owner)
@sender_logic_owner = make_logic(DomainsAPI::Logic::SenderConfig::Base, @owner)
@sender_logic_non_owner = make_logic(DomainsAPI::Logic::SenderConfig::Base, @non_owner)
@sso_logic_owner = make_logic(DomainsAPI::Logic::SsoConfig::Base, @owner)
@sso_logic_non_owner = make_logic(DomainsAPI::Logic::SsoConfig::Base, @non_owner)

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

## parse_boolean is consistent across all four config types
api_results = [true, 'true', '1', 1, false, nil, 'false', '0', 0].map { |v| @api_logic_owner.send(:parse_boolean, v) }
hp_results = [true, 'true', '1', 1, false, nil, 'false', '0', 0].map { |v| @homepage_logic_owner.send(:parse_boolean, v) }
sender_results = [true, 'true', '1', 1, false, nil, 'false', '0', 0].map { |v| @sender_logic_owner.send(:parse_boolean, v) }
sso_results = [true, 'true', '1', 1, false, nil, 'false', '0', 0].map { |v| @sso_logic_owner.send(:parse_boolean, v) }
api_results == hp_results && hp_results == sender_results && sender_results == sso_results
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

## SenderConfig::Base includes DomainConfigAuthorization concern
DomainsAPI::Logic::SenderConfig::Base.include?(DomainsAPI::Logic::Concerns::DomainConfigAuthorization)
#=> true

## SsoConfig::Base includes DomainConfigAuthorization concern
DomainsAPI::Logic::SsoConfig::Base.include?(DomainsAPI::Logic::Concerns::DomainConfigAuthorization)
#=> true

## ApiConfig::Base includes AuthorizationPolicies via concern
DomainsAPI::Logic::ApiConfig::Base.include?(Onetime::Application::AuthorizationPolicies)
#=> true

## SenderConfig::Base includes AuthorizationPolicies via concern
DomainsAPI::Logic::SenderConfig::Base.include?(Onetime::Application::AuthorizationPolicies)
#=> true

## SsoConfig::Base includes AuthorizationPolicies via concern
DomainsAPI::Logic::SsoConfig::Base.include?(Onetime::Application::AuthorizationPolicies)
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

## SenderConfig Base returns 'custom_mail_sender' as config_entitlement
@sender_logic_owner.send(:config_entitlement)
#=> 'custom_mail_sender'

## SsoConfig Base returns 'manage_sso' as config_entitlement
@sso_logic_owner.send(:config_entitlement)
#=> 'manage_sso'

## ApiConfig Base returns correct error message
@api_logic_owner.send(:config_entitlement_error)
#=> 'API configuration requires the api_access entitlement. Please upgrade your plan.'

## HomepageConfig Base returns correct error message
@homepage_logic_owner.send(:config_entitlement_error)
#=> 'Homepage secrets management requires the homepage_secrets entitlement. Please upgrade your plan.'

## SenderConfig Base returns correct error message
@sender_logic_owner.send(:config_entitlement_error)
#=> 'Custom mail sender requires the custom_mail_sender entitlement. Please upgrade your plan.'

## SsoConfig Base returns correct error message
@sso_logic_owner.send(:config_entitlement_error)
#=> 'SSO management requires the manage_sso entitlement. Please upgrade your plan.'

# ============================================================
# config_feature_flag
# ============================================================

## ApiConfig returns nil as config_feature_flag (no flag required)
@api_logic_owner.send(:config_feature_flag)
#=> nil

## HomepageConfig returns nil as config_feature_flag (no flag required)
@homepage_logic_owner.send(:config_feature_flag)
#=> nil

## SenderConfig returns 'custom_mail_enabled' as config_feature_flag
@sender_logic_owner.send(:config_feature_flag)
#=> 'custom_mail_enabled'

## SsoConfig returns 'sso_enabled' as config_feature_flag
@sso_logic_owner.send(:config_feature_flag)
#=> 'sso_enabled'

# ============================================================
# config_log_tag
# ============================================================

## ApiConfig returns 'ApiConfig' as config_log_tag
@api_logic_owner.send(:config_log_tag)
#=> 'ApiConfig'

## HomepageConfig returns 'HomepageConfig' as config_log_tag
@homepage_logic_owner.send(:config_log_tag)
#=> 'HomepageConfig'

## SenderConfig returns 'SenderConfig' as config_log_tag
@sender_logic_owner.send(:config_log_tag)
#=> 'SenderConfig'

## SsoConfig returns 'SsoConfig' as config_log_tag
@sso_logic_owner.send(:config_log_tag)
#=> 'SsoConfig'

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

## SenderConfig and SsoConfig also have verify_config_entitlement
[@sender_logic_owner.respond_to?(:verify_config_entitlement, true), @sso_logic_owner.respond_to?(:verify_config_entitlement, true)]
#=> [true, true]

# ============================================================
# verify_feature_flag! for configs with and without feature flags
# ============================================================

## verify_feature_flag! passes for ApiConfig (no feature flag)
begin
  @api_flag_check = make_logic(DomainsAPI::Logic::ApiConfig::Base, @owner)
  @api_flag_check.send(:verify_feature_flag!, @domain.extid)
  'passed'
rescue OT::FormError
  'forbidden'
end
#=> 'passed'

## verify_feature_flag! passes for HomepageConfig (no feature flag)
begin
  @hp_flag_check = make_logic(DomainsAPI::Logic::HomepageConfig::Base, @owner)
  @hp_flag_check.send(:verify_feature_flag!, @domain.extid)
  'passed'
rescue OT::FormError
  'forbidden'
end
#=> 'passed'

## verify_feature_flag! raises FormError for SenderConfig when flag is disabled
begin
  original_conf = OT.conf.dup
  test_conf = original_conf.dup
  test_conf['features'] = { 'organizations' => { 'custom_mail_enabled' => false } }
  OT.instance_variable_set(:@conf, test_conf)
  @sender_flag_check = make_logic(DomainsAPI::Logic::SenderConfig::Base, @owner)
  @sender_flag_check.send(:verify_feature_flag!, @domain.extid)
  'unexpected_success'
rescue OT::FormError => ex
  ex.error_type
ensure
  OT.instance_variable_set(:@conf, original_conf)
end
#=> :forbidden

## verify_feature_flag! raises FormError for SsoConfig when flag is disabled
begin
  original_conf = OT.conf.dup
  test_conf = original_conf.dup
  test_conf['features'] = { 'organizations' => { 'sso_enabled' => false } }
  OT.instance_variable_set(:@conf, test_conf)
  @sso_flag_check = make_logic(DomainsAPI::Logic::SsoConfig::Base, @owner)
  @sso_flag_check.send(:verify_feature_flag!, @domain.extid)
  'unexpected_success'
rescue OT::FormError => ex
  ex.error_type
ensure
  OT.instance_variable_set(:@conf, original_conf)
end
#=> :forbidden

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
