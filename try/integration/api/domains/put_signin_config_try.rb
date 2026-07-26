# try/integration/api/domains/put_signin_config_try.rb
#
# frozen_string_literal: true

# Integration tests for PutSigninConfig API logic class.
#
# Exercises the full logic lifecycle: process_params, raise_concerns, process.
# Uses the same harness pattern as update_domain_brand_validate_try.rb.
#
# Covers:
#   1. Authorization — SigninConfig::Base reports correct entitlement/log tag
#   2. validate_restrict_to — rejects invalid values, accepts valid values
#   3. Create path — new config when none exists
#   4. Replace path — PUT replaces existing config
#   5. Serialization shape — success_data returns expected structure
#   6. Authentication guard — anonymous users rejected
#   7. Missing domain_id — rejected
#   8. Entitlement gating — org without custom_signin_config is rejected
#  11. ADR-024 details resolution — details.effective_enabled uses the
#      custom-domain resolver (default OFF, opt-in, SSO carve-out) so the
#      settings page agrees with the masthead link and POST gate (#3814)
#
# Run:
#   bundle exec try try/integration/api/domains/put_signin_config_try.rb --agent

require_relative '../../../support/test_helpers'
require_relative '../../../../apps/web/billing/lib/test_support/billing_helpers'

OT.boot! :test

# Disable billing so standalone entitlements apply
BillingTestHelpers.disable_billing!

require 'apps/api/domains/logic/base'
require 'apps/api/domains/logic/signin_config/base'
require 'apps/api/domains/logic/signin_config/put_signin_config'
require 'apps/api/domains/logic/signin_config/get_signin_config'
require 'apps/api/domains/logic/signin_config/delete_signin_config'
require 'apps/api/domains/logic/signup_config/base'
require 'apps/api/domains/logic/signup_config/get_signup_config'

Familia.dbclient.flushdb
OT.info "Cleaned Redis for PutSigninConfig test run"

@ts = Familia.now.to_i
@entropy = SecureRandom.hex(4)
@owner = Onetime::Customer.create!(email: "psc_owner_#{@ts}_#{@entropy}@test.com")
@org = Onetime::Organization.create!("PSC Test Org #{@ts}", @owner, "psc_#{@ts}@test.com")
@domain = Onetime::CustomDomain.create!("psc-#{@ts}.example.com", @org.objid)

@session = {}
@strategy_result = MockStrategyResult.new(
  session: @session,
  user: @owner,
  metadata: { organization_context: { organization: @org } },
)

# Helper to build a fresh logic instance
def build_put(extid:, params: {}, strategy_result: @strategy_result)
  full_params = { 'extid' => extid }.merge(params)
  DomainsAPI::Logic::SigninConfig::PutSigninConfig.new(strategy_result, full_params)
end

def build_get(extid:, strategy_result: @strategy_result)
  DomainsAPI::Logic::SigninConfig::GetSigninConfig.new(strategy_result, { 'extid' => extid })
end

def build_delete(extid:, strategy_result: @strategy_result)
  DomainsAPI::Logic::SigninConfig::DeleteSigninConfig.new(strategy_result, { 'extid' => extid })
end

# ============================================================
# 1. Authorization — SigninConfig::Base metadata
# ============================================================

## SigninConfig::Base reports 'custom_signin_config' as entitlement
@logic_base = build_put(extid: @domain.extid)
@logic_base.send(:config_entitlement)
#=> 'custom_signin_config'

## SigninConfig::Base reports correct entitlement error message
@logic_base.send(:config_entitlement_error)
#=> 'Sign-in configuration requires the custom_signin_config entitlement. Please upgrade your plan.'

## SigninConfig::Base reports 'SigninConfig' as log tag
@logic_base.send(:config_log_tag)
#=> 'SigninConfig'

## SigninConfig::Base includes DomainConfigAuthorization policy
DomainsAPI::Logic::SigninConfig::Base.include?(DomainsAPI::Policies::DomainConfigAuthorization)
#=> true

# ============================================================
# 2. validate_restrict_to
# ============================================================

## validate_restrict_to accepts nil
@logic_rt_nil = build_put(extid: @domain.extid)
begin
  @logic_rt_nil.send(:validate_restrict_to, nil)
  'accepted'
rescue Onetime::FormError
  'rejected'
end
#=> 'accepted'

## validate_restrict_to accepts 'sso'
begin
  @logic_rt_nil.send(:validate_restrict_to, 'sso')
  'accepted'
rescue Onetime::FormError
  'rejected'
end
#=> 'accepted'

## validate_restrict_to accepts 'password'
begin
  @logic_rt_nil.send(:validate_restrict_to, 'password')
  'accepted'
rescue Onetime::FormError
  'rejected'
end
#=> 'accepted'

## validate_restrict_to accepts 'email_auth'
begin
  @logic_rt_nil.send(:validate_restrict_to, 'email_auth')
  'accepted'
rescue Onetime::FormError
  'rejected'
end
#=> 'accepted'

## validate_restrict_to accepts 'webauthn'
begin
  @logic_rt_nil.send(:validate_restrict_to, 'webauthn')
  'accepted'
rescue Onetime::FormError
  'rejected'
end
#=> 'accepted'

## validate_restrict_to rejects invalid value
begin
  @logic_rt_nil.send(:validate_restrict_to, 'magic_link')
  'accepted'
rescue Onetime::FormError => ex
  ex.message.include?('restrict_to must be one of')
end
#=> true

# ============================================================
# 3. Create path — new config
# ============================================================

## PUT creates new signin config when none exists
@logic_create = build_put(
  extid: @domain.extid,
  params: {
    'enabled' => 'true',
    'signin_enabled' => 'true',
    'email_auth_enabled' => 'false',
    'sso_enabled' => 'true',
    'restrict_to' => 'sso',
  },
)
@logic_create.raise_concerns
@result_create = @logic_create.process
@result_create[:record][:enabled]
#=> true

## Created config has correct signin_enabled
@result_create[:record][:signin_enabled]
#=> true

## Created config has correct sso_enabled
@result_create[:record][:sso_enabled]
#=> true

## Created config has correct email_auth_enabled (false)
@result_create[:record][:email_auth_enabled]
#=> false

## Created config has correct restrict_to
@result_create[:record][:restrict_to]
#=> 'sso'

## Created config has timestamps
@result_create[:record][:created_at] > 0
#=> true

## success_data includes user_id
@result_create[:user_id]
#=> @owner.extid

# ============================================================
# 4. Replace path — PUT replaces existing config
# ============================================================

## PUT replaces existing config (second call to same domain)
@logic_replace = build_put(
  extid: @domain.extid,
  params: {
    'enabled' => 'true',
    'signin_enabled' => 'false',
    'email_auth_enabled' => 'true',
    'sso_enabled' => 'false',
    'restrict_to' => 'email_auth',
  },
)
@logic_replace.raise_concerns
@result_replace = @logic_replace.process
@result_replace[:record][:signin_enabled]
#=> false

## Replaced config flipped email_auth_enabled to true
@result_replace[:record][:email_auth_enabled]
#=> true

## Replaced config flipped sso_enabled to false
@result_replace[:record][:sso_enabled]
#=> false

## Replaced config updated restrict_to
@result_replace[:record][:restrict_to]
#=> 'email_auth'

## Replaced config updated_at >= created_at
@result_replace[:record][:updated_at] >= @result_replace[:record][:created_at]
#=> true

# ============================================================
# 5. PUT defaults — omitted fields get conservative defaults
# ============================================================

## PUT with no boolean params defaults all to false
@domain_def = Onetime::CustomDomain.create!("psc-def-#{@ts}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@logic_def = build_put(
  extid: @domain_def.extid,
  params: {},
)
@logic_def.raise_concerns
@result_def = @logic_def.process
[@result_def[:record][:enabled], @result_def[:record][:signin_enabled], @result_def[:record][:email_auth_enabled], @result_def[:record][:sso_enabled]]
#=> [false, false, false, false]

## PUT with no restrict_to sets it to nil
@result_def[:record][:restrict_to]
#=> nil

# ============================================================
# 6. form_fields returns expected structure
# ============================================================

## form_fields includes all expected keys
@logic_ff = build_put(
  extid: @domain.extid,
  params: { 'enabled' => 'true', 'restrict_to' => 'sso' },
)
@ff = @logic_ff.form_fields
@ff.keys.sort
#=> [:domain_id, :email_auth_enabled, :enabled, :restrict_to, :signin_enabled, :sso_enabled].sort

# ============================================================
# 7. Authentication guard
# ============================================================

## Anonymous user is rejected
@anon_cust = Onetime::Customer.new
@anon_cust.role = 'anonymous'
@anon_result = MockStrategyResult.new(
  session: {},
  user: @anon_cust,
  auth_method: 'anonymous',
  metadata: {},
)
@logic_anon = build_put(extid: @domain.extid, strategy_result: @anon_result)
begin
  @logic_anon.raise_concerns
  'unexpected_success'
rescue Onetime::FormError => ex
  ex.message
end
#=> 'Authentication required'

# ============================================================
# 8. Missing domain_id
# ============================================================

## Empty extid is rejected
@logic_empty = build_put(extid: '')
begin
  @logic_empty.raise_concerns
  'unexpected_success'
rescue Onetime::FormError => ex
  ex.message
end
#=> 'Domain ID required'

# ============================================================
# 9. GET and DELETE paths
# ============================================================

## GET returns existing signin config
@domain_get = Onetime::CustomDomain.create!("psc-get-#{@ts}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@logic_create_for_get = build_put(
  extid: @domain_get.extid,
  params: { 'enabled' => 'true', 'sso_enabled' => 'true' },
)
@logic_create_for_get.raise_concerns
@logic_create_for_get.process
@logic_get = build_get(extid: @domain_get.extid)
@logic_get.raise_concerns
@get_result = @logic_get.process
@get_result[:record][:sso_enabled]
#=> true

## GET returns nil record when no signin config exists (ADR-024: unconfigured is 200, not 404)
@domain_no_config = Onetime::CustomDomain.create!("psc-noconfig-#{@ts}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@logic_get_missing = build_get(extid: @domain_no_config.extid)
@logic_get_missing.raise_concerns
@missing_result = @logic_get_missing.process
[@missing_result[:record], @missing_result[:details].nil?]
#=> [nil, false]

## DELETE removes existing signin config
@domain_del = Onetime::CustomDomain.create!("psc-del-#{@ts}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@logic_create_for_del = build_put(
  extid: @domain_del.extid,
  params: { 'enabled' => 'true' },
)
@logic_create_for_del.raise_concerns
@logic_create_for_del.process
@logic_del = build_delete(extid: @domain_del.extid)
@logic_del.raise_concerns
@del_result = @logic_del.process
@del_result[:success]
#=> true

## DELETE returns 404 after config was already deleted
begin
  @logic_del2 = build_delete(extid: @domain_del.extid)
  @logic_del2.raise_concerns
  'unexpected_success'
rescue Onetime::RecordNotFound
  'not_found'
end
#=> 'not_found'

# ============================================================
# 10. restrict_to validation at API level
# ============================================================

## PUT rejects invalid restrict_to via raise_concerns
@logic_bad_rt = build_put(
  extid: @domain.extid,
  params: { 'restrict_to' => 'biometric' },
)
begin
  @logic_bad_rt.raise_concerns
  'unexpected_success'
rescue Onetime::FormError => ex
  ex.message.include?('restrict_to must be one of')
end
#=> true

# ============================================================
# 11. ADR-024 details resolution — custom-domain default OFF (#3814)
#
# details.effective_enabled must use the same custom-domain resolver
# (default OFF, opt-in, tenant-SSO carve-out) as the runtime POST gate
# and the branded masthead. Global signin is ON in the test config, so
# these cases discriminate: the canonical-surface resolver
# (resolve_signin_enabled) would report true for an unconfigured domain
# — the exact bug where the settings page read "Enabled (Workspace
# default)" while the domain's /signin was closed.
# ============================================================

## Sanity: global signin is ON in test config (makes the cases below discriminating)
Onetime::CustomDomain::SigninConfig.global_signin_enabled
#=> true

## GET details: unconfigured domain, no SSO — effective_enabled false despite global true
@domain_unconf = Onetime::CustomDomain.create!("psc-unconf-#{@ts}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@logic_get_unconf = build_get(extid: @domain_unconf.extid)
@logic_get_unconf.raise_concerns
@details_unconf = @logic_get_unconf.process[:details]
[@details_unconf[:global_enabled], @details_unconf[:effective_enabled]]
#=> [true, false]

## GET details: SSO-only tenant (enabled SsoConfig, NO SigninConfig) — effective_enabled true (SSO carve-out)
@domain_ssoonly = Onetime::CustomDomain.create!("psc-ssoonly-#{@ts}-#{SecureRandom.hex(2)}.example.com", @org.objid)
Onetime::CustomDomain::SsoConfig.create!(
  domain_id: @domain_ssoonly.identifier,
  provider_type: 'oidc',
  display_name: 'PSC SSO',
  enabled: true,
  issuer: 'https://idp-psc.example.com',
  client_id: 'client-psc',
)
@logic_get_ssoonly = build_get(extid: @domain_ssoonly.extid)
@logic_get_ssoonly.raise_concerns
@logic_get_ssoonly.process[:details][:effective_enabled]
#=> true

## PUT details: enabled config with signin_enabled=true — effective_enabled true (explicit opt-in)
@domain_opt = Onetime::CustomDomain.create!("psc-opt-#{@ts}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@logic_put_opt = build_put(
  extid: @domain_opt.extid,
  params: { 'enabled' => 'true', 'signin_enabled' => 'true' },
)
@logic_put_opt.raise_concerns
@logic_put_opt.process[:details][:effective_enabled]
#=> true

## PUT details: enabled config with signin_enabled=false wins over tenant SSO (explicit opt-out, #3415 parity)
@logic_put_ssooff = build_put(
  extid: @domain_ssoonly.extid,
  params: { 'enabled' => 'true', 'signin_enabled' => 'false', 'sso_enabled' => 'false' },
)
@logic_put_ssooff.raise_concerns
@logic_put_ssooff.process[:details][:effective_enabled]
#=> false

## DELETE details: post-delete reverts to default OFF (nil config, no SSO)
@logic_del_opt = build_delete(extid: @domain_opt.extid)
@logic_del_opt.raise_concerns
@logic_del_opt.process[:details][:effective_enabled]
#=> false

## DELETE details: post-delete with tenant SSO stays true (carve-out survives config removal)
@logic_del_ssoonly = build_delete(extid: @domain_ssoonly.extid)
@logic_del_ssoonly.raise_concerns
@logic_del_ssoonly.process[:details][:effective_enabled]
#=> true

## GET signup details: unconfigured domain — effective_enabled false despite global signup true (no SSO carve-out for signup)
@logic_get_signup = DomainsAPI::Logic::SignupConfig::GetSignupConfig.new(@strategy_result, { 'extid' => @domain_unconf.extid })
@logic_get_signup.raise_concerns
@signup_details = @logic_get_signup.process[:details]
[@signup_details[:global_enabled], @signup_details[:effective_enabled]]
#=> [true, false]

# --- Cleanup ---

Familia.dbclient.flushdb
OT.info "Cleaned Redis after PutSigninConfig test run"
