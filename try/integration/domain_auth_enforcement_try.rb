# try/integration/domain_auth_enforcement_try.rb
#
# frozen_string_literal: true

# Integration tests for per-domain signin enforcement wiring.
#
# Exercises the REAL gate logic in Core::Controllers::Base#signin_enabled?
# using a lightweight controller stub (same pattern as
# homepage_mode_integration_try.rb). The controller class overrides
# `domain_signin_config` and `auth_settings` so we control both sides of
# the fallback without needing a full Rack request cycle.
#
# Also exercises the serializer-level visibility gates:
#   - DomainSerializer.effective_signin_enabled? / effective_signup_enabled?
#   - ConfigSerializer.resolve_restrict_to
#   - ConfigSerializer.resolve_signin (features.signin display gate)
#
# Covers:
#   1. No SigninConfig record -> falls back to global
#   2. SigninConfig exists, enabled=false (master switch off) -> falls back to global
#   3. SigninConfig exists, enabled=true, signin_enabled=true -> allows signin
#   4. SigninConfig exists, enabled=true, signin_enabled=false -> blocks signin
#   5. Default reconciliation: new SigninConfig conservative defaults
#   6. Serializer visibility gates
#   7. ConfigSerializer resolve_restrict_to domain override
#   11. ConfigSerializer resolve_signin AND semantics (#3415)
#
# Run:
#   try try/integration/domain_auth_enforcement_try.rb --agent

require_relative '../../lib/onetime'
require 'rack/mock'

OT.boot! :test

Familia.dbclient.flushdb
OT.info "Cleaned Redis for domain auth enforcement test run"

# Load controller and serializer modules
require_relative '../../apps/web/core/controllers/base'
require_relative '../../apps/web/core/views/serializers/domain_serializer'
require_relative '../../apps/web/core/views/serializers/config_serializer'

# Unique test identifiers
@ts = Familia.now.to_i
@entropy = SecureRandom.hex(4)

# Create fixtures for tests that need persisted SigninConfig
@owner = Onetime::Customer.create!(email: "dae_owner_#{@ts}_#{@entropy}@test.com")
@org = Onetime::Organization.create!("DAE Test Org #{@ts}", @owner, "dae_#{@ts}@test.com")

# -------------------------------------------------------------------
# Controller stub: exercises real Base#signin_enabled? with injectable
# domain_signin_config and auth_settings.
# -------------------------------------------------------------------
SigninGateController = Class.new do
  include Core::Controllers::Base

  attr_accessor :req, :res, :injected_signin_config, :injected_auth_settings

  def initialize(signin_config:, auth_settings:)
    env = { 'REQUEST_METHOD' => 'GET', 'PATH_INFO' => '/', 'SERVER_NAME' => 'test', 'SERVER_PORT' => '443' }
    @req = Rack::Request.new(env)
    @res = Rack::Response.new
    @injected_signin_config = signin_config
    @injected_auth_settings = auth_settings
  end

  # Override private helpers to inject test data
  private

  def domain_signin_config
    injected_signin_config
  end

  def auth_settings
    injected_auth_settings
  end

  # Expose the protected method
  public :signin_enabled?
end

# Global settings where signin IS enabled (the typical default)
GLOBAL_SIGNIN_ON  = { 'enabled' => true, 'signin' => true }
# Global settings where signin is OFF (discriminating: differs from config)
GLOBAL_SIGNIN_OFF = { 'enabled' => true, 'signin' => false }
# Global settings where auth master switch is off
GLOBAL_AUTH_OFF   = { 'enabled' => false, 'signin' => true }

# ===================================================================
# 1. No SigninConfig record -> falls back to global
# ===================================================================

## No SigninConfig: returns global signin value (true)
ctrl = SigninGateController.new(signin_config: nil, auth_settings: GLOBAL_SIGNIN_ON)
ctrl.signin_enabled?
#=> true

## No SigninConfig: returns global signin value (false) when global disables signin
ctrl = SigninGateController.new(signin_config: nil, auth_settings: GLOBAL_SIGNIN_OFF)
ctrl.signin_enabled?
#=> false

## No SigninConfig: returns false when global auth master switch is off
ctrl = SigninGateController.new(signin_config: nil, auth_settings: GLOBAL_AUTH_OFF)
ctrl.signin_enabled?
#=> false

# ===================================================================
# 2. SigninConfig exists, enabled=false (master switch off) -> falls back to global
# ===================================================================

## Master switch off: falls back to global even when config.signin_enabled=true
@domain_ms = Onetime::CustomDomain.create!("dae-ms-#{@ts}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@config_ms = Onetime::CustomDomain::SigninConfig.create!(
  domain_id: @domain_ms.identifier,
  enabled: false,
  signin_enabled: true,
)
ctrl = SigninGateController.new(signin_config: @config_ms, auth_settings: GLOBAL_SIGNIN_OFF)
ctrl.signin_enabled?
#=> false

## Master switch off: falls back to global (true) ignoring config.signin_enabled=false
@domain_ms2 = Onetime::CustomDomain.create!("dae-ms2-#{@ts}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@config_ms2 = Onetime::CustomDomain::SigninConfig.create!(
  domain_id: @domain_ms2.identifier,
  enabled: false,
  signin_enabled: false,
)
ctrl = SigninGateController.new(signin_config: @config_ms2, auth_settings: GLOBAL_SIGNIN_ON)
ctrl.signin_enabled?
#=> true

# ===================================================================
# 3. SigninConfig exists, enabled=true, signin_enabled=true
#    -> allows signin ONLY when the global kill switch also permits it.
#       AND semantics: an enabled domain config narrows, never widens,
#       the install-level capability. The global kill switch always wins,
#       and the runtime gate matches the display gate (resolve_signin).
# ===================================================================

## Enabled config with signin_enabled=true allows signin when global also permits
@domain_on = Onetime::CustomDomain.create!("dae-on-#{@ts}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@config_on = Onetime::CustomDomain::SigninConfig.create!(
  domain_id: @domain_on.identifier,
  enabled: true,
  signin_enabled: true,
)
ctrl = SigninGateController.new(signin_config: @config_on, auth_settings: GLOBAL_SIGNIN_ON)
ctrl.signin_enabled?
#=> true

## Global kill switch wins: an enabled config cannot re-enable signin when AUTH_SIGNIN is off
ctrl_signin_off = SigninGateController.new(signin_config: @config_on, auth_settings: GLOBAL_SIGNIN_OFF)
ctrl_signin_off.signin_enabled?
#=> false

## Global kill switch wins: an enabled config cannot re-enable signin when AUTH_ENABLED is off
ctrl_auth_off = SigninGateController.new(signin_config: @config_on, auth_settings: GLOBAL_AUTH_OFF)
ctrl_auth_off.signin_enabled?
#=> false

# ===================================================================
# 4. SigninConfig exists, enabled=true, signin_enabled=false -> blocks signin
# ===================================================================

## Enabled config with signin_enabled=false blocks signin (regardless of global)
@domain_off = Onetime::CustomDomain.create!("dae-off-#{@ts}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@config_off = Onetime::CustomDomain::SigninConfig.create!(
  domain_id: @domain_off.identifier,
  enabled: true,
  signin_enabled: false,
)
ctrl = SigninGateController.new(signin_config: @config_off, auth_settings: GLOBAL_SIGNIN_ON)
ctrl.signin_enabled?
#=> false

## Enabled config with signin_enabled=false overrides global=true
ctrl2 = SigninGateController.new(signin_config: @config_off, auth_settings: GLOBAL_SIGNIN_ON)
ctrl2.signin_enabled?
#=> false

# ===================================================================
# 5. Default reconciliation: conservative boolean defaults
# ===================================================================

## New SigninConfig defaults signin_enabled to false (conservative)
@domain_def = Onetime::CustomDomain.create!("dae-def-#{@ts}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@config_def = Onetime::CustomDomain::SigninConfig.create!(domain_id: @domain_def.identifier)
@config_def.signin_enabled?
#=> false

## New SigninConfig defaults email_auth_enabled to false
@config_def.email_auth_enabled?
#=> false

## New SigninConfig defaults sso_enabled to false
@config_def.sso_enabled?
#=> false

## New SigninConfig defaults enabled (master switch) to false
@config_def.enabled?
#=> false

## Round-trip: conservative defaults survive save/load
@config_def_loaded = Onetime::CustomDomain::SigninConfig.find_by_domain_id(@domain_def.identifier)
[@config_def_loaded.signin_enabled?, @config_def_loaded.email_auth_enabled?, @config_def_loaded.sso_enabled?]
#=> [false, false, false]

# ===================================================================
# 6. Serializer visibility gates (class << self methods)
# ===================================================================

## effective_signin_enabled? returns true when no SigninConfig exists
Core::Views::DomainSerializer.send(:effective_signin_enabled?, 'nonexistent_domain_id')
#=> true

## effective_signin_enabled? returns true when SigninConfig exists but master switch off
@domain_vis1 = Onetime::CustomDomain.create!("dae-vis1-#{@ts}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@config_vis1 = Onetime::CustomDomain::SigninConfig.create!(
  domain_id: @domain_vis1.identifier,
  enabled: false,
  signin_enabled: false,
)
Core::Views::DomainSerializer.send(:effective_signin_enabled?, @domain_vis1.identifier)
#=> true

## effective_signin_enabled? returns false when SigninConfig enabled and signin disabled
@domain_vis2 = Onetime::CustomDomain.create!("dae-vis2-#{@ts}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@config_vis2 = Onetime::CustomDomain::SigninConfig.create!(
  domain_id: @domain_vis2.identifier,
  enabled: true,
  signin_enabled: false,
)
Core::Views::DomainSerializer.send(:effective_signin_enabled?, @domain_vis2.identifier)
#=> false

## effective_signin_enabled? returns true when SigninConfig enabled and signin enabled
@domain_vis3 = Onetime::CustomDomain.create!("dae-vis3-#{@ts}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@config_vis3 = Onetime::CustomDomain::SigninConfig.create!(
  domain_id: @domain_vis3.identifier,
  enabled: true,
  signin_enabled: true,
)
Core::Views::DomainSerializer.send(:effective_signin_enabled?, @domain_vis3.identifier)
#=> true

## effective_signup_enabled? returns true when no SignupConfig exists
Core::Views::DomainSerializer.send(:effective_signup_enabled?, 'nonexistent_domain_id')
#=> true

## effective_signup_enabled? returns false when SignupConfig disables signup
@domain_vis4 = Onetime::CustomDomain.create!("dae-vis4-#{@ts}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@config_vis4 = Onetime::CustomDomain::SignupConfig.create!(
  domain_id: @domain_vis4.identifier,
  validation_strategy: 'passthrough',
  signup_enabled: false,
)
Core::Views::DomainSerializer.send(:effective_signup_enabled?, @domain_vis4.identifier)
#=> false

# ===================================================================
# 7. ConfigSerializer resolve_restrict_to domain override
# ===================================================================

## resolve_restrict_to falls back to global when no domain context
Core::Views::ConfigSerializer.send(:resolve_restrict_to, {})
#=> Onetime.auth_config.restrict_to

## resolve_restrict_to falls back to global when domain has no SigninConfig
@domain_rt1 = Onetime::CustomDomain.create!("dae-rt1-#{@ts}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@view_vars_no_config = { 'display_domain' => @domain_rt1.display_domain }
Core::Views::ConfigSerializer.send(:resolve_restrict_to, @view_vars_no_config)
#=> Onetime.auth_config.restrict_to

## resolve_restrict_to uses domain SigninConfig restrict_to when enabled
@domain_rt2 = Onetime::CustomDomain.create!("dae-rt2-#{@ts}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@config_rt2 = Onetime::CustomDomain::SigninConfig.create!(
  domain_id: @domain_rt2.identifier,
  enabled: true,
  restrict_to: 'sso',
)
@view_vars_with_config = { 'display_domain' => @domain_rt2.display_domain }
Core::Views::ConfigSerializer.send(:resolve_restrict_to, @view_vars_with_config)
#=> 'sso'

## resolve_restrict_to falls back to global when SigninConfig master switch off
@domain_rt3 = Onetime::CustomDomain.create!("dae-rt3-#{@ts}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@config_rt3 = Onetime::CustomDomain::SigninConfig.create!(
  domain_id: @domain_rt3.identifier,
  enabled: false,
  restrict_to: 'sso',
)
@view_vars_disabled = { 'display_domain' => @domain_rt3.display_domain }
Core::Views::ConfigSerializer.send(:resolve_restrict_to, @view_vars_disabled)
#=> Onetime.auth_config.restrict_to

# ===================================================================
# 8. ConfigSerializer resolve_email_auth (AND semantics)
# ===================================================================
#
# email_auth uses AND with global: a domain can DISABLE email_auth but
# cannot ENABLE it when the global Rodauth route was never mounted. We
# stub Onetime.auth_config.email_auth_enabled? per-case for determinism
# (the resolver reads the process-global singleton directly — no injection
# point like the controller stub). Each case forces the global predicate
# inline, evaluates resolve_email_auth, then removes the singleton method
# to restore the class implementation — keeping cases independent.

## resolve_email_auth: global true + no domain context => global (true)
Onetime.auth_config.define_singleton_method(:email_auth_enabled?) { true }
@result_ea_a = begin
  Core::Views::ConfigSerializer.send(:resolve_email_auth, {})
ensure
  Onetime.auth_config.singleton_class.send(:remove_method, :email_auth_enabled?)
end
@result_ea_a
#=> true

## resolve_email_auth: global true + master ON + email_auth_enabled false => false (domain disables)
@domain_ea_b = Onetime::CustomDomain.create!("dae-ea-b-#{@ts}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@config_ea_b = Onetime::CustomDomain::SigninConfig.create!(
  domain_id: @domain_ea_b.identifier,
  enabled: true,
  email_auth_enabled: false,
)
Onetime.auth_config.define_singleton_method(:email_auth_enabled?) { true }
@result_ea_b = begin
  Core::Views::ConfigSerializer.send(:resolve_email_auth, { 'display_domain' => @domain_ea_b.display_domain })
ensure
  Onetime.auth_config.singleton_class.send(:remove_method, :email_auth_enabled?)
end
@result_ea_b
#=> false

## resolve_email_auth: global true + master ON + email_auth_enabled true => true
@domain_ea_c = Onetime::CustomDomain.create!("dae-ea-c-#{@ts}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@config_ea_c = Onetime::CustomDomain::SigninConfig.create!(
  domain_id: @domain_ea_c.identifier,
  enabled: true,
  email_auth_enabled: true,
)
Onetime.auth_config.define_singleton_method(:email_auth_enabled?) { true }
@result_ea_c = begin
  Core::Views::ConfigSerializer.send(:resolve_email_auth, { 'display_domain' => @domain_ea_c.display_domain })
ensure
  Onetime.auth_config.singleton_class.send(:remove_method, :email_auth_enabled?)
end
@result_ea_c
#=> true

## resolve_email_auth: global FALSE + master ON + email_auth_enabled true => false (domain cannot enable)
@domain_ea_d = Onetime::CustomDomain.create!("dae-ea-d-#{@ts}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@config_ea_d = Onetime::CustomDomain::SigninConfig.create!(
  domain_id: @domain_ea_d.identifier,
  enabled: true,
  email_auth_enabled: true,
)
Onetime.auth_config.define_singleton_method(:email_auth_enabled?) { false }
@result_ea_d = begin
  Core::Views::ConfigSerializer.send(:resolve_email_auth, { 'display_domain' => @domain_ea_d.display_domain })
ensure
  Onetime.auth_config.singleton_class.send(:remove_method, :email_auth_enabled?)
end
@result_ea_d
#=> false

## resolve_email_auth: master OFF => equals global (config ignored), global forced true
@domain_ea_e = Onetime::CustomDomain.create!("dae-ea-e-#{@ts}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@config_ea_e = Onetime::CustomDomain::SigninConfig.create!(
  domain_id: @domain_ea_e.identifier,
  enabled: false,
  email_auth_enabled: false,
)
Onetime.auth_config.define_singleton_method(:email_auth_enabled?) { true }
@result_ea_e = begin
  Core::Views::ConfigSerializer.send(:resolve_email_auth, { 'display_domain' => @domain_ea_e.display_domain })
ensure
  Onetime.auth_config.singleton_class.send(:remove_method, :email_auth_enabled?)
end
@result_ea_e
#=> true

# ===================================================================
# 9. SigninConfig.sso_permitted_for? + resolve_tenant_sso_config gate
# ===================================================================
#
# sso_permitted_for? is the shared activation authority. SsoConfig is the
# credentials store; resolve_tenant_sso_config returns it only when the
# credentials are enabled AND sso_permitted_for? is true.

## sso_permitted_for? returns true when no SigninConfig exists (defer to credentials)
Onetime::CustomDomain::SigninConfig.sso_permitted_for?('nonexistent_domain_id')
#=> true

## SsoConfig active + no SigninConfig => tenant SSO active (current behavior preserved)
@domain_sso_a = Onetime::CustomDomain.create!("dae-sso-a-#{@ts}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@sso_a = Onetime::CustomDomain::SsoConfig.create!(
  domain_id: @domain_sso_a.identifier,
  provider_type: 'oidc',
  display_name: 'SSO A',
  enabled: true,
  issuer: 'https://idp-a.example.com',
  client_id: 'client-a',
)
Core::Views::ConfigSerializer.send(:resolve_tenant_sso_config, { 'display_domain' => @domain_sso_a.display_domain })&.domain_id
#=> @domain_sso_a.identifier

## SsoConfig active + master ON + sso_enabled false => tenant SSO inactive (gate blocks)
@domain_sso_b = Onetime::CustomDomain.create!("dae-sso-b-#{@ts}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@sso_b = Onetime::CustomDomain::SsoConfig.create!(
  domain_id: @domain_sso_b.identifier,
  provider_type: 'oidc',
  display_name: 'SSO B',
  enabled: true,
  issuer: 'https://idp-b.example.com',
  client_id: 'client-b',
)
@signin_sso_b = Onetime::CustomDomain::SigninConfig.create!(
  domain_id: @domain_sso_b.identifier,
  enabled: true,
  sso_enabled: false,
)
Core::Views::ConfigSerializer.send(:resolve_tenant_sso_config, { 'display_domain' => @domain_sso_b.display_domain })
#=> nil

## SsoConfig active + master ON + sso_enabled true => tenant SSO active
@domain_sso_c = Onetime::CustomDomain.create!("dae-sso-c-#{@ts}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@sso_c = Onetime::CustomDomain::SsoConfig.create!(
  domain_id: @domain_sso_c.identifier,
  provider_type: 'oidc',
  display_name: 'SSO C',
  enabled: true,
  issuer: 'https://idp-c.example.com',
  client_id: 'client-c',
)
@signin_sso_c = Onetime::CustomDomain::SigninConfig.create!(
  domain_id: @domain_sso_c.identifier,
  enabled: true,
  sso_enabled: true,
)
Core::Views::ConfigSerializer.send(:resolve_tenant_sso_config, { 'display_domain' => @domain_sso_c.display_domain })&.domain_id
#=> @domain_sso_c.identifier

## SsoConfig active + master OFF => SsoConfig behavior preserved (gate defers)
@domain_sso_d = Onetime::CustomDomain.create!("dae-sso-d-#{@ts}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@sso_d = Onetime::CustomDomain::SsoConfig.create!(
  domain_id: @domain_sso_d.identifier,
  provider_type: 'oidc',
  display_name: 'SSO D',
  enabled: true,
  issuer: 'https://idp-d.example.com',
  client_id: 'client-d',
)
@signin_sso_d = Onetime::CustomDomain::SigninConfig.create!(
  domain_id: @domain_sso_d.identifier,
  enabled: false,
  sso_enabled: false,
)
Core::Views::ConfigSerializer.send(:resolve_tenant_sso_config, { 'display_domain' => @domain_sso_d.display_domain })&.domain_id
#=> @domain_sso_d.identifier

# ===================================================================
# 10. Parity: sso_permitted_for? drives BOTH the display and runtime gates
# ===================================================================
#
# Runtime hook (omniauth_tenant.rb) ANDs the SAME predicate the serializer
# uses. We cannot boot the Rodauth hook in a tryout, so we assert parity at
# the predicate-value level: for the disable case, sso_permitted_for? is
# false AND the serializer (which consumes it) returns nil. Both gates key
# off the identical value, so they cannot diverge.

## Parity (disable case): sso_permitted_for? is false for the gated domain
Onetime::CustomDomain::SigninConfig.sso_permitted_for?(@domain_sso_b.identifier)
#=> false

## Parity (disable case): serializer consumes the false predicate -> nil
Core::Views::ConfigSerializer.send(:resolve_tenant_sso_config, { 'display_domain' => @domain_sso_b.display_domain })
#=> nil

## Parity (enable case): sso_permitted_for? true, serializer returns the config
[
  Onetime::CustomDomain::SigninConfig.sso_permitted_for?(@domain_sso_c.identifier),
  !Core::Views::ConfigSerializer.send(:resolve_tenant_sso_config, { 'display_domain' => @domain_sso_c.display_domain }).nil?,
]
#=> [true, true]

# ===================================================================
# 11. ConfigSerializer resolve_signin (features.signin, AND semantics)
# ===================================================================
#
# resolve_signin is the DISPLAY gate for per-domain sign-in disable
# (#3415): it feeds features.signin in the bootstrap so the public
# /signin page can render a friendly "not available" notice instead
# of the auth form. Global signin comes from site.authentication
# (AUTH_ENABLED + AUTH_SIGNIN) via view_vars['site'], so each case
# passes it explicitly — no singleton stubbing needed. AND semantics:
# a domain may DISABLE sign-in but can never enable it when sign-in
# is globally off.

@site_signin_on  = { 'authentication' => { 'enabled' => true, 'signin' => true } }
@site_signin_off = { 'authentication' => { 'enabled' => true, 'signin' => false } }
@site_auth_off   = { 'authentication' => { 'enabled' => false, 'signin' => true } }

## resolve_signin: global on + no domain context => true
Core::Views::ConfigSerializer.send(:resolve_signin, { 'site' => @site_signin_on })
#=> true

## resolve_signin: global signin off + no domain context => false
Core::Views::ConfigSerializer.send(:resolve_signin, { 'site' => @site_signin_off })
#=> false

## resolve_signin: global auth master off + no domain context => false
Core::Views::ConfigSerializer.send(:resolve_signin, { 'site' => @site_auth_off })
#=> false

## resolve_signin: domain with no SigninConfig => global (true)
@domain_si_a = Onetime::CustomDomain.create!("dae-si-a-#{@ts}-#{SecureRandom.hex(2)}.example.com", @org.objid)
Core::Views::ConfigSerializer.send(
  :resolve_signin,
  { 'site' => @site_signin_on, 'display_domain' => @domain_si_a.display_domain },
)
#=> true

## resolve_signin: global on + master ON + signin_enabled false => false (domain disables)
@domain_si_b = Onetime::CustomDomain.create!("dae-si-b-#{@ts}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@config_si_b = Onetime::CustomDomain::SigninConfig.create!(
  domain_id: @domain_si_b.identifier,
  enabled: true,
  signin_enabled: false,
)
Core::Views::ConfigSerializer.send(
  :resolve_signin,
  { 'site' => @site_signin_on, 'display_domain' => @domain_si_b.display_domain },
)
#=> false

## resolve_signin: global on + master ON + signin_enabled true => true
@domain_si_c = Onetime::CustomDomain.create!("dae-si-c-#{@ts}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@config_si_c = Onetime::CustomDomain::SigninConfig.create!(
  domain_id: @domain_si_c.identifier,
  enabled: true,
  signin_enabled: true,
)
Core::Views::ConfigSerializer.send(
  :resolve_signin,
  { 'site' => @site_signin_on, 'display_domain' => @domain_si_c.display_domain },
)
#=> true

## resolve_signin: global OFF + master ON + signin_enabled true => false (domain cannot widen)
Core::Views::ConfigSerializer.send(
  :resolve_signin,
  { 'site' => @site_signin_off, 'display_domain' => @domain_si_c.display_domain },
)
#=> false

## resolve_signin: master OFF + signin_enabled false => global (true; config ignored)
@domain_si_d = Onetime::CustomDomain.create!("dae-si-d-#{@ts}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@config_si_d = Onetime::CustomDomain::SigninConfig.create!(
  domain_id: @domain_si_d.identifier,
  enabled: false,
  signin_enabled: false,
)
Core::Views::ConfigSerializer.send(
  :resolve_signin,
  { 'site' => @site_signin_on, 'display_domain' => @domain_si_d.display_domain },
)
#=> true

## resolve_signin: missing site config => false (no global capability to narrow)
Core::Views::ConfigSerializer.send(:resolve_signin, {})
#=> false

# --- Cleanup ---

Familia.dbclient.flushdb
OT.info "Cleaned Redis after domain auth enforcement test run"
