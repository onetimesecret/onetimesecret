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
#
# Covers:
#   1. No SigninConfig record -> falls back to global
#   2. SigninConfig exists, enabled=false (master switch off) -> falls back to global
#   3. SigninConfig exists, enabled=true, signin_enabled=true -> allows signin
#   4. SigninConfig exists, enabled=true, signin_enabled=false -> blocks signin
#   5. Default reconciliation: new SigninConfig conservative defaults
#   6. Serializer visibility gates
#   7. ConfigSerializer resolve_restrict_to domain override
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
# 3. SigninConfig exists, enabled=true, signin_enabled=true -> allows signin
# ===================================================================

## Enabled config with signin_enabled=true returns true (regardless of global)
@domain_on = Onetime::CustomDomain.create!("dae-on-#{@ts}-#{SecureRandom.hex(2)}.example.com", @org.objid)
@config_on = Onetime::CustomDomain::SigninConfig.create!(
  domain_id: @domain_on.identifier,
  enabled: true,
  signin_enabled: true,
)
ctrl = SigninGateController.new(signin_config: @config_on, auth_settings: GLOBAL_SIGNIN_OFF)
ctrl.signin_enabled?
#=> true

## Enabled config with signin_enabled=true overrides global auth_off
ctrl2 = SigninGateController.new(signin_config: @config_on, auth_settings: GLOBAL_AUTH_OFF)
ctrl2.signin_enabled?
#=> true

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

# --- Cleanup ---

Familia.dbclient.flushdb
OT.info "Cleaned Redis after domain auth enforcement test run"
