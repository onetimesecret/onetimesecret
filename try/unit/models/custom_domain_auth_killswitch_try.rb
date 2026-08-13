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
# Also covers SigninConfig.resolve_restrict_to
# (ADR-034#resolution-is-model-owned) — the single owner
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

def restrict_config(enabled:, restrict_to:, signin_enabled: true, email_auth_enabled: true, sso_enabled: true)
  Onetime::CustomDomain::SigninConfig.new(
    domain_id: 'ks_restrict',
    enabled: enabled,
    restrict_to: restrict_to,
    signin_enabled: signin_enabled,
    email_auth_enabled: email_auth_enabled,
    sso_enabled: sso_enabled
  )
end

# The resolver as PRODUCTION calls it: no domain_available:, so the domain
# half's availability is DERIVED live from
# restriction_available_for_custom_domain?. Real callers never inject the flag,
# so injecting it by default here would pin the one branch production cannot
# take and leave the derivation — where the interesting failures live —
# untested (#4139).
def resolve_restrict(global, config)
  Onetime::CustomDomain::SigninConfig.resolve_restrict_to(global, config)
end

# The same resolver with the domain verdict INJECTED. Only for cases whose
# point is the precedence table rather than the availability derivation, and
# whose derived answer would otherwise depend on this lane's config values.
def resolve_restrict_with(global, config, domain_available:)
  Onetime::CustomDomain::SigninConfig.resolve_restrict_to(
    global,
    config,
    domain_available: domain_available,
  )
end

# The derivation itself, so a case can assert that the resolver ASKED it
# without hard-coding a lane-dependent answer.
def domain_method_available?(value, config)
  Onetime::CustomDomain::SigninConfig.restriction_available_for_custom_domain?(value, config)
end

# Same resolver with the GLOBAL restriction's backing method dead post-boot
# (ADR-034#degradation-is-fail-closed runtime half, #4139): available:
# false. The flag lives on the resolver rather than in each consumer so
# the display gate, the route gate
# and the settings API cannot drift on it.
def resolve_restrict_dead(global, config)
  Onetime::CustomDomain::SigninConfig.resolve_restrict_to(
    global,
    config,
    available: false,
    domain_available: true,
  )
end

# --- SigninConfig.restriction_available_for_request? (ADR-034#resolution-is-model-owned, #4139) ---
#
# The availability INPUT every gate hands to the resolver. It lives on the
# model, not in the gate that first needed it, because all three consumers must
# ask it identically: the route gate (Auth::RestrictTo), the /signin page
# (ConfigSerializer) and the settings API. When it lived in the gate alone, a
# custom host with no enabled SigninConfig under a global 'password'
# restriction 404'd every Rodauth route while the page still advertised the
# password form.
def available_for_request?(global, config, domain_id: nil, custom_host: false)
  Onetime::CustomDomain::SigninConfig.restriction_available_for_request?(
    global, config, domain_id: domain_id, custom_host: custom_host
  )
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

# --- SigninConfig.resolve_restrict_to (ADR-034#resolution-is-model-owned) ---
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
resolve_restrict_with('sso', restrict_config(enabled: true, restrict_to: 'sso'), domain_available: true).restrict_to
#=> 'sso'

## both agreeing => still :restricted
resolve_restrict_with('sso', restrict_config(enabled: true, restrict_to: 'sso'), domain_available: true).state
#=> :restricted

## both agreeing => attributed to the domain, which asserted it explicitly
resolve_restrict_with('sso', restrict_config(enabled: true, restrict_to: 'sso'), domain_available: true).source
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
resolve_restrict_with('', restrict_config(enabled: true, restrict_to: 'email_auth'), domain_available: true).state
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

# --- DOMAIN AVAILABILITY DERIVATION (A3 domain half, #4139) ---
#
# Production never injects domain_available:, so the branch that matters is the
# DERIVATION: resolve_restrict_to asking
# restriction_available_for_custom_domain? itself. Cases whose answer would
# depend on this lane's config values assert against that predicate rather than
# a hard-coded verdict; the rest are true regardless of config, because they
# turn on the domain record alone.

## DERIVATION: the resolver asks the capability predicate rather than guessing
cfg = restrict_config(enabled: true, restrict_to: 'password')
resolve_restrict(nil, cfg).restricted? == domain_method_available?('password', cfg)
#=> true

## DERIVATION: a domain that turned sign-in off cannot honor its own password restriction
resolve_restrict(nil, restrict_config(enabled: true, restrict_to: 'password', signin_enabled: false)).state
#=> :unavailable

## DERIVATION: the same domain cannot honor an email_auth restriction either
resolve_restrict(nil, restrict_config(enabled: true, restrict_to: 'email_auth', signin_enabled: false)).state
#=> :unavailable

## DERIVATION: email-auth off on the domain fails an email_auth restriction closed
resolve_restrict(nil, restrict_config(enabled: true, restrict_to: 'email_auth', email_auth_enabled: false)).state
#=> :unavailable

## SSO ASKS THE SSO LADDER, NOT signin_enabled (#4139). restrict_to gates the
## SSO ROUTE, and that route obeys sso_available_for_tenant_host? →
## sso_permitted_for? (keyed on sso_enabled?). A signin_enabled short-circuit
## here 404'd a route omniauth_tenant served successfully.
sso_cfg = restrict_config(enabled: true, restrict_to: 'sso', signin_enabled: false)
domain_method_available?('sso', sso_cfg) ==
  Onetime::CustomDomain::SsoConfig.sso_available_for_tenant_host?('ks_restrict')
#=> true

## SSO: withholding sso_enabled is what takes SSO down, and it does so through
## the same ladder (sso_permitted_for? => false)
domain_method_available?('sso', restrict_config(enabled: true, restrict_to: 'sso', sso_enabled: false))
#=> false

# --- SigninConfig.restriction_available_for_request? (the shared gatherer) ---

## a canonical host has no custom-domain capabilities to intersect
available_for_request?('password', nil, domain_id: 'ks_restrict', custom_host: false)
#=> true

## an install with nothing restricted is never taken dark
available_for_request?(nil, nil, domain_id: 'ks_restrict', custom_host: true)
#=> true

## an unclassified custom host keeps the global verdict
available_for_request?('password', nil, domain_id: nil, custom_host: true)
#=> true

## THE #4139 DEFECT: an INHERITED global restriction IS narrowed by the custom
## host. No enabled SigninConfig means password is off there, so the page must
## report what the route gate enforces instead of advertising a dark form.
available_for_request?('password', nil, domain_id: 'ks_restrict', custom_host: true)
#=> false

# --- available: false — post-boot global unavailability (A3, #4139) ---
#
# The flag says "the global restriction stands, but its backing method is dead
# here". It may only NARROW: a standing restriction goes :unavailable, and an
# install with nothing restricted stays :unrestricted — a false flag must never
# take an unrestricted install dark.

## global restriction whose method died post-boot => :unavailable
resolve_restrict_dead('sso', nil).state
#=> :unavailable

## it does NOT widen to standard mode
resolve_restrict_dead('sso', nil).unrestricted?
#=> false

## nothing is permitted, not even the named method
resolve_restrict_dead('sso', nil).allows?('sso')
#=> false

## the other methods are not re-exposed
resolve_restrict_dead('sso', nil).allows?('password')
#=> false

## the named method is retained for a method-specific notice
resolve_restrict_dead('sso', nil).restrict_to
#=> 'sso'

## attributed to the global layer — the global half is why nothing is offered
resolve_restrict_dead('sso', nil).source
#=> :global

## NOTHING RESTRICTED: a false flag cannot take an unrestricted install dark
resolve_restrict_dead(nil, nil).state
#=> :unrestricted

## NOTHING RESTRICTED: every method still allowed
resolve_restrict_dead(nil, nil).allows?('password')
#=> true

## NOTHING RESTRICTED: blank global is equally untouched
resolve_restrict_dead('', nil).state
#=> :unrestricted

## an AGREEING domain config does not resurrect the dead method (A8 agreement)
resolve_restrict_dead('sso', restrict_config(enabled: true, restrict_to: 'sso')).state
#=> :unavailable

## agreement + dead global => attributed to global, not the agreeing domain
resolve_restrict_dead('sso', restrict_config(enabled: true, restrict_to: 'sso')).source
#=> :global

## agreement + dead global => the agreed method is not permitted
resolve_restrict_dead('sso', restrict_config(enabled: true, restrict_to: 'sso')).allows?('sso')
#=> false

## an enabled domain config with NO restriction inherits the dead global (A8)
resolve_restrict_dead('sso', restrict_config(enabled: true, restrict_to: nil)).state
#=> :unavailable

## a CONFLICTING domain config stays :unavailable, and keeps the richer source
resolve_restrict_dead('sso', restrict_config(enabled: true, restrict_to: 'password')).state
#=> :unavailable

## conflict attribution is unchanged by the flag
resolve_restrict_dead('sso', restrict_config(enabled: true, restrict_to: 'password')).source
#=> :conflict

## conflict + dead global permits nothing
resolve_restrict_dead('sso', restrict_config(enabled: true, restrict_to: 'password')).allows?('password')
#=> false

## DOMAIN-ONLY restriction is untouched: the flag describes the GLOBAL value
resolve_restrict_dead(nil, restrict_config(enabled: true, restrict_to: 'password')).state
#=> :restricted

## domain-only restriction still permits its method
resolve_restrict_dead(nil, restrict_config(enabled: true, restrict_to: 'password')).allows?('password')
#=> true

## a disabled domain config is still ignored; the dead global stands
resolve_restrict_dead('sso', restrict_config(enabled: false, restrict_to: 'password')).state
#=> :unavailable

## available: true is the default and changes nothing
Onetime::CustomDomain::SigninConfig.resolve_restrict_to('sso', nil, available: true).state
#=> :restricted

# ============================================================
# RestrictToResolution#to_wire — the ONE serialization (#4139)
#
# Both API surfaces that publish a resolution (settings API
# details.effective_restrict_to,
# ADR-034#settings-api-serializes-effective-restrict-to; GET
# /api/invite/:token record.effective_restrict_to,
# ADR-034#invite-signup-is-gated) call this method. They each carried a
# private copy of the hash until #4139; the contract is pinned here so the
# next consumer inherits it instead of re-deriving it.
# ============================================================

## the wire shape is exactly three keys, in this order
Onetime::CustomDomain::SigninConfig::RestrictToResolution.unrestricted(:global).to_wire.keys
#=> [:state, :restrict_to, :source]

## unrestricted serializes with a null method
Onetime::CustomDomain::SigninConfig::RestrictToResolution.unrestricted(:global).to_wire
#=> { state: 'unrestricted', restrict_to: nil, source: 'global' }

## restricted names the method and the deciding layer
Onetime::CustomDomain::SigninConfig::RestrictToResolution.restricted('sso', :domain).to_wire
#=> { state: 'restricted', restrict_to: 'sso', source: 'domain' }

## :unavailable survives the wire — it is NOT projected down to a bare null
## the way the display field features.restrict_to must be. A null here would
## read as "unrestricted" and re-offer every method the restriction hid (A3).
Onetime::CustomDomain::SigninConfig::RestrictToResolution.unavailable('sso', :domain).to_wire
#=> { state: 'unavailable', restrict_to: 'sso', source: 'domain' }

## the named method is retained on the wire so a consumer can render a
## method-specific notice rather than a generic "unavailable"
Onetime::CustomDomain::SigninConfig::RestrictToResolution.unavailable('sso', :conflict).to_wire[:restrict_to]
#=> 'sso'

## :conflict attribution reaches the wire (A8: neither layer won)
Onetime::CustomDomain::SigninConfig::RestrictToResolution.unavailable('sso', :conflict).to_wire[:source]
#=> 'conflict'

## state and source are STRINGS on the wire, not symbols — this is why to_h
## (which emits the members verbatim) is not the wire form
Onetime::CustomDomain::SigninConfig::RestrictToResolution.restricted('password', :global).to_wire.values_at(:state, :source).map(&:class)
#=> [String, String]

## restrict_to passes through unconverted (String or nil, never a symbol)
Onetime::CustomDomain::SigninConfig::RestrictToResolution.restricted('password', :global).to_wire[:restrict_to].class
#=> String

## to_h is deliberately NOT the wire form: it emits symbols
Onetime::CustomDomain::SigninConfig::RestrictToResolution.restricted('password', :global).to_h
#=> { state: :restricted, restrict_to: 'password', source: :global }

## a resolver-produced resolution serializes the same way as a hand-built one
Onetime::CustomDomain::SigninConfig.resolve_restrict_to('sso', nil).to_wire
#=> { state: 'restricted', restrict_to: 'sso', source: 'global' }
