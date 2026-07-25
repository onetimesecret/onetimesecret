# try/unit/models/custom_domain_auth_default_off_try.rb
#
# frozen_string_literal: true

# Tests for the CUSTOM-DOMAIN sign-in / sign-up availability resolvers:
# SigninConfig.resolve_signin_enabled_for_custom_domain and
# SignupConfig.resolve_signup_enabled_for_custom_domain.
#
# The security property under test: custom domains FAIL CLOSED. Anonymous
# sign-in and sign-up on a branded custom domain require an explicitly
# *enabled* per-domain SigninConfig/SignupConfig — absence of that opt-in
# (no record, or a record whose master switch is off) resolves to false even
# when the install-level flags are on. The install-level AUTH_* flags act
# only as a kill-switch CEILING: an enabled config can narrow availability
# but can never re-enable a feature the operator disabled globally.
#
# The one exception is the tenant-SSO carve-out on the sign-in side: DISPLAY
# surfaces (masthead link, settings page) pass domain_id: so an SSO-only
# tenant (enabled SsoConfig, no SigninConfig) still reports sign-in as
# available — its /signin page works via the omniauth routes. Callers gating
# the password/email POST /signin handler omit domain_id and keep the strict
# false. Sign-up has no carve-out by design: SSO signup flows through the
# signin path.
#
# The carve-out ignores the password-signin `global` param (AUTH_SIGNIN does
# not govern SSO) but NOT the master switch: tenant_sso_available_for?
# consults SigninConfig.global_auth_enabled (AUTH_ENABLED) itself, so a
# master kill darkens SSO-only display surfaces too (#3901 follow-up).
#
# See: #3672, ADR-024 (resolution invariants), ADR-030 (config layering).
# Complements try/unit/models/custom_domain_auth_killswitch_try.rb, which
# covers the shared canonical resolvers (resolve_signin_enabled /
# resolve_signup_enabled / global_signin_enabled / global_signup_enabled).
#
# Run:
#   try try/unit/models/custom_domain_auth_default_off_try.rb --agent

require_relative '../../support/test_models'

OT.boot! :test

# The SSO carve-out reads persisted records — SsoConfig.tenant_sso_available_for?
# loads SsoConfig (and, via sso_permitted_for?, SigninConfig) by domain_id — so
# unlike the killswitch tryout this one persists fixtures to the test datastore.
Familia.dbclient.flushdb
OT.info 'Cleaned Redis for custom-domain default-OFF resolver test run'

@ts      = Familia.now.to_i
@entropy = SecureRandom.hex(4)

# SSO-only tenant: enabled SsoConfig, no SigninConfig record at all.
@sso_only_domain = "dof_sso_only_#{@ts}_#{@entropy}"
Onetime::CustomDomain::SsoConfig.create!(domain_id: @sso_only_domain, enabled: true)

# Tenant with a persisted SsoConfig whose master switch is OFF (present but
# not available).
@sso_disabled_domain = "dof_sso_off_#{@ts}_#{@entropy}"
Onetime::CustomDomain::SsoConfig.create!(domain_id: @sso_disabled_domain, enabled: false)

# Tenant with an enabled SsoConfig AND a persisted-but-DISABLED SigninConfig:
# the record exists but its master switch is off, so the tenant is "not
# explicitly configured" for password sign-in while SSO remains permitted
# (sso_permitted_for? defers when the master switch is off).
@sso_with_disabled_signin = "dof_sso_dis_signin_#{@ts}_#{@entropy}"
Onetime::CustomDomain::SsoConfig.create!(domain_id: @sso_with_disabled_signin, enabled: true)
@disabled_signin_cfg = Onetime::CustomDomain::SigninConfig.create!(
  domain_id: @sso_with_disabled_signin, enabled: false, signin_enabled: false
)

# In-memory builders (no persistence) mirroring the killswitch tryout — the
# resolvers only read enabled?/signin_enabled?/signup_enabled? off the param.
def signin_config(enabled:, signin_enabled:)
  Onetime::CustomDomain::SigninConfig.new(
    domain_id: 'dof_signin', enabled: enabled, signin_enabled: signin_enabled
  )
end

def signup_config(enabled:, signup_enabled:)
  Onetime::CustomDomain::SignupConfig.new(
    domain_id: 'dof_signup', enabled: enabled, signup_enabled: signup_enabled
  )
end

# --- SigninConfig.resolve_signin_enabled_for_custom_domain ---

## DEFAULT OFF (#3672 core property): global on, no per-domain config, no
## domain_id => unavailable, even though the install is open
Onetime::CustomDomain::SigninConfig.resolve_signin_enabled_for_custom_domain(true, nil)
#=> false

## disabled config == no config: master switch off means "not explicitly
## allowed" even when the override value would allow sign-in
Onetime::CustomDomain::SigninConfig.resolve_signin_enabled_for_custom_domain(true, signin_config(enabled: false, signin_enabled: true))
#=> false

## explicit opt-in works: enabled config allowing sign-in, global on => available
Onetime::CustomDomain::SigninConfig.resolve_signin_enabled_for_custom_domain(true, signin_config(enabled: true, signin_enabled: true))
#=> true

## KILL SWITCH ceiling: global off, enabled config allows sign-in => still
## unavailable (per-domain opt-in can never re-enable a global kill)
Onetime::CustomDomain::SigninConfig.resolve_signin_enabled_for_custom_domain(false, signin_config(enabled: true, signin_enabled: true))
#=> false

## explicit disable honored: enabled config with signin_enabled=false, global
## on => unavailable (this branch also hides SSO — an enabled config falls
## through to the shared resolver instead of the carve-out)
Onetime::CustomDomain::SigninConfig.resolve_signin_enabled_for_custom_domain(true, signin_config(enabled: true, signin_enabled: false))
#=> false

# --- SSO carve-out (domain_id: kwarg, display surfaces only) ---

## carve-out negative: domain_id given but no SsoConfig persisted for it =>
## unavailable (tenant_sso_available_for? finds nothing)
Onetime::CustomDomain::SigninConfig.resolve_signin_enabled_for_custom_domain(true, nil, domain_id: "dof_absent_#{@ts}_#{@entropy}")
#=> false

## carve-out: SSO-only tenant (enabled SsoConfig, no SigninConfig) => display
## surfaces report sign-in available so the masthead /signin link renders
Onetime::CustomDomain::SigninConfig.resolve_signin_enabled_for_custom_domain(true, nil, domain_id: @sso_only_domain)
#=> true

## POST gate parity: the SAME SSO-only tenant WITHOUT the domain_id kwarg
## keeps the strict false — SSO never flows through POST /signin
Onetime::CustomDomain::SigninConfig.resolve_signin_enabled_for_custom_domain(true, nil)
#=> false

## carve-out negative: persisted SsoConfig present but its master switch is
## off => unavailable (SSO configured-but-disabled is not an opt-in)
Onetime::CustomDomain::SigninConfig.resolve_signin_enabled_for_custom_domain(true, nil, domain_id: @sso_disabled_domain)
#=> false

## carve-out with a persisted-but-disabled SigninConfig record: the disabled
## record does not count as explicit config, and sso_permitted_for? defers
## when the master switch is off => SSO keeps the display available
Onetime::CustomDomain::SigninConfig.resolve_signin_enabled_for_custom_domain(true, @disabled_signin_cfg, domain_id: @sso_with_disabled_signin)
#=> true

## enabled config bypasses the carve-out entirely: explicit
## signin_enabled=false wins even when tenant SSO is available for the domain
Onetime::CustomDomain::SigninConfig.resolve_signin_enabled_for_custom_domain(true, signin_config(enabled: true, signin_enabled: false), domain_id: @sso_only_domain)
#=> false

## carve-out does not consult the password-signin global param: SSO
## availability is governed by the SsoConfig gates (enabled? +
## sso_permitted_for?) plus the AUTH_ENABLED master switch (on in test
## config), not AUTH_SIGNIN — the asymmetry the resolver docstring records
## as intentional
Onetime::CustomDomain::SigninConfig.resolve_signin_enabled_for_custom_domain(false, nil, domain_id: @sso_only_domain)
#=> true

## master switch gates the carve-out (#3901 follow-up): AUTH_ENABLED=false
## suppresses an SSO-only tenant's sign-in availability — sessionauth is
## never registered when the master switch is off, so an SSO sign-in could
## only mint a session the app ignores. Injectable auth hash exercises the
## gate without mutating boot config.
Onetime::CustomDomain::SsoConfig.tenant_sso_available_for?(@sso_only_domain, auth: { 'enabled' => false })
#=> false

## master switch on via the same injection: gate passes and availability is
## governed by the SsoConfig gates as before
Onetime::CustomDomain::SsoConfig.tenant_sso_available_for?(@sso_only_domain, auth: { 'enabled' => true })
#=> true

## strict-boolean master switch: an absent enabled key reads as off
Onetime::CustomDomain::SigninConfig.global_auth_enabled({})
#=> false

## resolver wiring: the carve-out reaches the master-switch gate through
## tenant_sso_available_for?'s default OT.conf read — flip the live setting
## around the call to prove the path (restored immediately after)
@auth_conf     = OT.conf['site']['authentication']
@saved_enabled = @auth_conf['enabled']
@auth_conf['enabled'] = false
@masterkill_result = Onetime::CustomDomain::SigninConfig.resolve_signin_enabled_for_custom_domain(true, nil, domain_id: @sso_only_domain)
@auth_conf['enabled'] = @saved_enabled
@masterkill_result
#=> false

# --- SignupConfig.resolve_signup_enabled_for_custom_domain ---

## DEFAULT OFF (#3672 core property): global on, no per-domain config =>
## unavailable, even though the install is open
Onetime::CustomDomain::SignupConfig.resolve_signup_enabled_for_custom_domain(true, nil)
#=> false

## disabled config == no config: master switch off means "not explicitly
## allowed" even when the override value would allow signup
Onetime::CustomDomain::SignupConfig.resolve_signup_enabled_for_custom_domain(true, signup_config(enabled: false, signup_enabled: true))
#=> false

## explicit opt-in works: enabled config allowing signup, global on => available
Onetime::CustomDomain::SignupConfig.resolve_signup_enabled_for_custom_domain(true, signup_config(enabled: true, signup_enabled: true))
#=> true

## KILL SWITCH ceiling: global off, enabled config allows signup => still
## unavailable (per-domain opt-in can never re-enable a global kill)
Onetime::CustomDomain::SignupConfig.resolve_signup_enabled_for_custom_domain(false, signup_config(enabled: true, signup_enabled: true))
#=> false

## explicit disable honored: enabled config with signup_enabled=false, global
## on => unavailable
Onetime::CustomDomain::SignupConfig.resolve_signup_enabled_for_custom_domain(true, signup_config(enabled: true, signup_enabled: false))
#=> false

# --- Cleanup ---

Familia.dbclient.flushdb
OT.info 'Cleaned Redis after custom-domain default-OFF resolver test run'
