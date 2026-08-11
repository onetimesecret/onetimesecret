# try/unit/models/custom_domain_auth_killswitch_try.rb
#
# frozen_string_literal: true

# Tests for the shared sign-in / sign-up availability resolvers that back both
# the display gate (ConfigSerializer) and the runtime gate (Core::Controllers::Base).
#
# The security property under test: the install-level (global) kill switch
# always wins. A per-domain SigninConfig/SignupConfig may only NARROW the
# global capability — it can never re-enable sign-in or sign-up when the
# operator has disabled it globally (AUTH_ENABLED / AUTH_SIGNIN / AUTH_SIGNUP).
#
# Also covers SigninConfig.resolve_restrict_to (ADR-024 A2) — the single owner
# of restrict_to resolution — whose degradation rule is fail-CLOSED: a domain
# restriction naming a method that cannot be honored here resolves to
# :unavailable, never to "unrestricted" (A3).
#
# Run:
#   try try/unit/models/custom_domain_auth_killswitch_try.rb --agent

require_relative '../../support/test_models'

OT.boot! :test

# Helper builders for in-memory configs (no persistence needed — the resolvers
# only read enabled?/signin_enabled?/signup_enabled?).
def signin_config(enabled:, signin_enabled:)
  Onetime::CustomDomain::SigninConfig.new(
    domain_id: 'ks_signin', enabled: enabled, signin_enabled: signin_enabled
  )
end

def signup_config(enabled:, signup_enabled:)
  Onetime::CustomDomain::SignupConfig.new(
    domain_id: 'ks_signup', enabled: enabled, signup_enabled: signup_enabled
  )
end

def restrict_config(enabled:, restrict_to:)
  Onetime::CustomDomain::SigninConfig.new(
    domain_id: 'ks_restrict', enabled: enabled, restrict_to: restrict_to
  )
end

def resolve_restrict(global, config)
  Onetime::CustomDomain::SigninConfig.resolve_restrict_to(global, config)
end

# --- SigninConfig.resolve_signin_enabled ---

## global on, no per-domain config => available
Onetime::CustomDomain::SigninConfig.resolve_signin_enabled(true, nil)
#=> true

## global off, no per-domain config => unavailable
Onetime::CustomDomain::SigninConfig.resolve_signin_enabled(false, nil)
#=> false

## nil global coerces to unavailable (defensive)
Onetime::CustomDomain::SigninConfig.resolve_signin_enabled(nil, nil)
#=> false

## global on, enabled config that allows sign-in => available
Onetime::CustomDomain::SigninConfig.resolve_signin_enabled(true, signin_config(enabled: true, signin_enabled: true))
#=> true

## global on, enabled config that disables sign-in => narrowed to unavailable
Onetime::CustomDomain::SigninConfig.resolve_signin_enabled(true, signin_config(enabled: true, signin_enabled: false))
#=> false

## KILL SWITCH: global off but enabled config tries to allow sign-in => still unavailable
Onetime::CustomDomain::SigninConfig.resolve_signin_enabled(false, signin_config(enabled: true, signin_enabled: true))
#=> false

## disabled config (master switch off) is ignored; global is authoritative
Onetime::CustomDomain::SigninConfig.resolve_signin_enabled(true, signin_config(enabled: false, signin_enabled: false))
#=> true

# --- SignupConfig.resolve_signup_enabled ---

## global on, no per-domain config => available
Onetime::CustomDomain::SignupConfig.resolve_signup_enabled(true, nil)
#=> true

## global off, no per-domain config => unavailable
Onetime::CustomDomain::SignupConfig.resolve_signup_enabled(false, nil)
#=> false

## nil global coerces to unavailable (defensive) — mirrors the SigninConfig invariant
Onetime::CustomDomain::SignupConfig.resolve_signup_enabled(nil, nil)
#=> false

## global on, enabled config that allows signup => available
Onetime::CustomDomain::SignupConfig.resolve_signup_enabled(true, signup_config(enabled: true, signup_enabled: true))
#=> true

## global on, enabled config that disables signup => narrowed to unavailable
Onetime::CustomDomain::SignupConfig.resolve_signup_enabled(true, signup_config(enabled: true, signup_enabled: false))
#=> false

## KILL SWITCH: global off but enabled config tries to allow signup => still unavailable
Onetime::CustomDomain::SignupConfig.resolve_signup_enabled(false, signup_config(enabled: true, signup_enabled: true))
#=> false

## disabled config (master switch off) is ignored; global is authoritative
Onetime::CustomDomain::SignupConfig.resolve_signup_enabled(true, signup_config(enabled: false, signup_enabled: false))
#=> true

# --- SigninConfig.resolve_restrict_to (ADR-024 A2) ---
#
# Three explicit states: :unrestricted (allow every enabled method),
# :restricted (allow only the named one), :unavailable (allow nothing —
# fail-closed degradation, A3). Precedence is INTERSECTION (A8): a domain
# config narrows, never widens; two different restrictions intersect to
# nothing and fail closed.

## no global, no domain config => unrestricted
resolve_restrict(nil, nil).state
#=> :unrestricted

## no global, no domain config => allows every method
resolve_restrict(nil, nil).allows?('password')
#=> true

## unrestricted carries no method name
resolve_restrict(nil, nil).restrict_to
#=> nil

## empty-string global is an absent restriction, not a restriction to ''
resolve_restrict('', nil).state
#=> :unrestricted

## global only => restricted to the global method
resolve_restrict('sso', nil).state
#=> :restricted

## global only => the method is the global value
resolve_restrict('sso', nil).restrict_to
#=> 'sso'

## global only => attributed to the global layer
resolve_restrict('sso', nil).source
#=> :global

## global only => allows the restricted method
resolve_restrict('sso', nil).allows?('sso')
#=> true

## global only => rejects every other method
resolve_restrict('sso', nil).allows?('password')
#=> false

## allows? accepts a symbol
resolve_restrict('sso', nil).allows?(:sso)
#=> true

## domain only => restricted to the domain method
resolve_restrict(nil, restrict_config(enabled: true, restrict_to: 'password')).restrict_to
#=> 'password'

## domain only => attributed to the domain layer
resolve_restrict(nil, restrict_config(enabled: true, restrict_to: 'password')).source
#=> :domain

## no global, no domain restriction => nothing restricts, attributed to global
resolve_restrict(nil, restrict_config(enabled: true, restrict_to: nil)).source
#=> :global

## both agreeing => that method, domain-sourced
resolve_restrict('sso', restrict_config(enabled: true, restrict_to: 'sso')).restrict_to
#=> 'sso'

## both agreeing => still :restricted
resolve_restrict('sso', restrict_config(enabled: true, restrict_to: 'sso')).state
#=> :restricted

## both agreeing => attributed to the domain, which asserted it explicitly
resolve_restrict('sso', restrict_config(enabled: true, restrict_to: 'sso')).source
#=> :domain

## INTERSECTION (A8): two different restrictions intersect to nothing
resolve_restrict('sso', restrict_config(enabled: true, restrict_to: 'password')).state
#=> :unavailable

## conflict => neither layer wins; the domain does not override the operator
resolve_restrict('sso', restrict_config(enabled: true, restrict_to: 'password')).allows?('password')
#=> false

## conflict => the global method is not permitted either
resolve_restrict('sso', restrict_config(enabled: true, restrict_to: 'password')).allows?('sso')
#=> false

## conflict => retains the GLOBAL method for a method-specific notice
resolve_restrict('sso', restrict_config(enabled: true, restrict_to: 'password')).restrict_to
#=> 'sso'

## conflict => attributed to neither layer
resolve_restrict('sso', restrict_config(enabled: true, restrict_to: 'password')).source
#=> :conflict

## conflict fails closed even when the domain half would be honorable alone
resolve_restrict('password', restrict_config(enabled: true, restrict_to: 'email_auth')).unrestricted?
#=> false

## A8 FIX: an enabled domain config with no restriction NO LONGER widens past global
resolve_restrict('sso', restrict_config(enabled: true, restrict_to: nil)).state
#=> :restricted

## A8 FIX: the global restriction stands, attributed to the global layer
resolve_restrict('sso', restrict_config(enabled: true, restrict_to: nil)).source
#=> :global

## A8 FIX: the global method is the effective one
resolve_restrict('sso', restrict_config(enabled: true, restrict_to: nil)).restrict_to
#=> 'sso'

## A8 FIX: a tenant cannot re-expose the methods the operator restricted away
resolve_restrict('sso', restrict_config(enabled: true, restrict_to: nil)).allows?('password')
#=> false

## A8 FIX: blank (not nil) domain restrict_to is also "unset"
resolve_restrict('sso', restrict_config(enabled: true, restrict_to: '  ')).restrict_to
#=> 'sso'

## domain-only restriction is unaffected by the intersection (global unset)
resolve_restrict('', restrict_config(enabled: true, restrict_to: 'email_auth')).state
#=> :restricted

## master switch off: the domain restriction is ignored, global stands
resolve_restrict('sso', restrict_config(enabled: false, restrict_to: 'password')).restrict_to
#=> 'sso'

## master switch off: attribution stays global
resolve_restrict('sso', restrict_config(enabled: false, restrict_to: 'password')).source
#=> :global

## master switch off with no global => unrestricted
resolve_restrict(nil, restrict_config(enabled: false, restrict_to: 'password')).state
#=> :unrestricted

## FAIL CLOSED (A3): domain 'webauthn' cannot be honored on a custom domain
resolve_restrict(nil, restrict_config(enabled: true, restrict_to: 'webauthn')).state
#=> :unavailable

## FAIL CLOSED: it does NOT widen to standard mode
resolve_restrict(nil, restrict_config(enabled: true, restrict_to: 'webauthn')).unrestricted?
#=> false

## FAIL CLOSED: no method is permitted, not even the named one
resolve_restrict(nil, restrict_config(enabled: true, restrict_to: 'webauthn')).allows?('webauthn')
#=> false

## FAIL CLOSED: password is not re-exposed either
resolve_restrict(nil, restrict_config(enabled: true, restrict_to: 'webauthn')).allows?('password')
#=> false

## FAIL CLOSED: the named method is retained for a method-specific notice
resolve_restrict(nil, restrict_config(enabled: true, restrict_to: 'webauthn')).restrict_to
#=> 'webauthn'

## FAIL CLOSED: an unavailable domain restriction does not fall back to global either
resolve_restrict('password', restrict_config(enabled: true, restrict_to: 'webauthn')).state
#=> :unavailable

## FAIL CLOSED: a stray/invalid persisted value is invalid data, not "unrestricted"
resolve_restrict(nil, restrict_config(enabled: true, restrict_to: 'bogus')).state
#=> :unavailable

## global 'webauthn' is honored — the host-scoping problem is custom-domain only
resolve_restrict('webauthn', nil).state
#=> :restricted
