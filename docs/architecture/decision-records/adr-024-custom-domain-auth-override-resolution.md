---
id: "024"
status: accepted
title: "ADR-024: Custom-Domain Auth Override Resolution and Single-Control Settings UI"
---

## Status

Accepted

## Date

2026-07-11

## Context

Per-domain sign-in and sign-up behavior is stored in `CustomDomain::SigninConfig` and `CustomDomain::SignupConfig`, each carrying **two independent boolean flags**:

- `enabled` — whether this per-domain config is consulted at all. When `false`, runtime resolution ignores every other field and falls back to the install-level (global) configuration.
- `signin_enabled` / `signup_enabled` — the override value, combined with the global capability under **AND semantics**: an enabled config can only *narrow* availability, never re-enable a feature the operator disabled globally (`AUTH_ENABLED` / `AUTH_SIGNIN` / `AUTH_SIGNUP`).

Runtime resolution is centralized in class-level resolvers on the models (`SigninConfig.resolve_signin_enabled`, `SignupConfig.resolve_signup_enabled`):

```ruby
def resolve_signin_enabled(global, config)
  global = global == true
  return global unless config&.enabled?   # no override → global is authoritative

  global && config.signin_enabled?        # override active → AND with global
end
```

Both the display gate (`Core::Views::ConfigSerializer#resolve_signin` → bootstrap `features.signin`) and the runtime gate (`Core::Controllers::Base#signin_enabled?` → POST /signin) route through these resolvers, so the public page and the POST handler cannot disagree. **The public surface is coherent.**

The workspace settings surface was not:

1. The settings API (`GET /api/domains/:extid/signin-config`) returned only the raw flag pair; the resolved effective value and the global inputs were absent. The settings UI could not display runtime truth and did not try.
2. The settings pages rendered **both flags as co-equal user-facing controls** — a header "Enabled/Disabled" toggle bound to `enabled`, and a mode switch / select bound to `signin_enabled`/`signup_enabled` — with no reconciliation. An untouched domain showed a header reading "Disabled" above an active-looking "Any available method" mode: enabled and disabled at the same time, while the runtime truth (inherit global, usually *on*) matched neither.
3. Latent write bug: mode selections and availability toggles patched `signin_enabled`/`restrict_to`/`email_auth_enabled` but never set `enabled: true`. On an unconfigured domain, choosing "Sign-in disabled" created a record with `enabled=false` — which the resolver ignores entirely. The user's explicit choice silently did nothing.

A product requirement shapes the fix: **the distinction between "never configured" and "explicitly configured" must survive** in storage. When a customer takes an explicit configuration action, their domain must keep operating the same way if the install-level *default* for unconfigured domains later changes. (The global master switch is exempt: it is a kill switch and always wins — see Resolution invariants below.)

## Decision

### 1. Storage keeps two flags; `enabled` becomes bookkeeping, not a user control

`enabled` remains in storage with a sharpened meaning: **"the customer has explicitly configured this domain"** (the pin). It also continues to gate the sibling overrides (`restrict_to`, `email_auth_enabled`, `sso_enabled`), which is why it cannot be folded into `signin_enabled`. It is **no longer presented as a user-facing control**. `{feature}_enabled` remains the override value under AND semantics.

Reachable effective states (signin shown; signup is identical minus `restrict_to`):

```
                          unconfigured     explicit allow      explicit disable
                          (no record or    (enabled=true,      (enabled=true,
                           enabled=false)   signin_en=true)     signin_en=false)
  effective value         global           global && true      false
  fallback default        follows the      pinned              pinned
  changes (on→off)        new default
  global master flipped   OFF              OFF (kill switch    OFF
  (AUTH_SIGNIN=false)                      wins — not pinned)
```

Note the AND semantics make "unconfigured" and "explicit allow" behaviorally identical *today* (both yield `global`); they diverge only when a future default change is applied at the unconfigured-fallback layer. That is the pinning mechanism: **default-behavior changes are implemented by changing what the resolver returns for unconfigured domains, never by rewriting customer records and never by weakening the global master.**

### 2. Resolution authority: the model resolvers, plus model-owned global inputs

`SigninConfig.resolve_signin_enabled` / `SignupConfig.resolve_signup_enabled` remain the single authority for combining global + override. The global inputs are now also defined once, next to the resolvers:

- `SigninConfig.global_signin_enabled` — `site.authentication.enabled && site.authentication.signin`, strict-boolean
- `SignupConfig.global_signup_enabled` — same with `signup`

All three gates consume them: the runtime gate (`Core::Controllers::Base`), the settings API details (below), and — via the same conf values — the display gate (`ConfigSerializer`). No caller may re-derive "global" from raw conf keys.

### 3. Settings API serializes resolved truth (`details`)

`GET`/`PUT`/`DELETE` on `/api/domains/:extid/signin-config` and `signup-config` include a `details` object alongside `record`:

```jsonc
{
  "record": { /* raw flags, or null when unconfigured (GET) */ },
  "details": {
    "global_enabled": true,        // install-level capability (kill switch input)
    "effective_enabled": true,     // resolver output for this domain, post-write
    "global_restrict_to": null     // signin only: install-level restrict_to
  }
}
```

- `GET` returns **200 with `record: null`** for an unconfigured domain (previously 404). "Unconfigured" is a first-class state the UI must render — it needs `details` to do so. Clients keep a 404 fallback for older backends.
- The client **displays** `effective_enabled`; it never re-implements the resolver. Client-side derivation is exactly the drift this ADR exists to kill.

### 4. Settings UI: one control, seeded from inherited state, writes materialize the pin

- The `enabled` toggle is **removed** from both settings pages. The remaining control (signin: the Any / One / Disabled mode switch; signup: the Enabled/Disabled select) is the single user-facing concept: *can end users sign in / sign up on this domain?*
- For an unconfigured domain, the form state is **seeded from the inherited global state** (`details` + the page's global method availability), not from static defaults. What the user sees selected is what actually runs. No dual display path in the form.
- **Every write sets `enabled: true`** (applied once, in the composable save path — not per call site). Touching any control is an explicit configuration action and materializes the full inherited snapshot plus the user's change. This both records the pin and fixes the latent `enabled=false` write bug.
- A **"Workspace default" badge** shows while the domain is unconfigured (`record` null or `enabled=false`); it disappears on first explicit configuration. An **effective-status line** driven by `effective_enabled` states the runtime truth and cannot contradict it.
- When the global capability is off, controls stay **active** (customers may pre-configure; the pin matters for future default changes) with a **dormant warning** — matching the existing signup-page precedent — and the status line shows the feature as off.
- **"Reset to defaults"** (DELETE) remains the way back from pinned to unconfigured.

Behavior is defined once and implemented twice: shared frontend module `useAuthOverrideState` (derived state + the writes-materialize rule) and shared component `DomainAuthOverrideBanner.vue` (status line, badge, dormant warning), consumed by both the sign-in and sign-up pages.

### Resolution invariants (normative)

1. **Kill switch wins**: `effective = false` whenever global is off, regardless of any record. Explicit config can narrow, never widen.
2. **No record / `enabled=false` → global**: the resolver returns the install-level value untouched.
3. **Pin at the fallback layer**: future default changes alter invariant 2's fallback only; records with `enabled=true` are unaffected.
4. **One resolver**: every gate — display, runtime, settings — routes through `resolve_{signin,signup}_enabled`. New gates must too.

## Consequences

- The settings UI can no longer contradict runtime behavior: its displayed state comes from the same resolver output the POST gate uses.
- "Configured but inherit defaults" (`enabled=false` with a record) is no longer *producible* from the UI — writes always pin, DELETE always unpins. Legacy records in that state render identically to unconfigured (badge shown, inherited state displayed), which is also how the resolver treats them.
- The GET contract change (404 → 200/`record: null`) is visible to any API consumer; the workspace UI is the only known consumer and handles both forms.
- `enabled` in the PUT payload is now client-supplied constant `true`; the field stays in the wire format for auditability and for the (colonel/support) ability to unpin without deleting.

### Custom-domain default-OFF is implemented twice — intentionally divergent (#3672)

The custom-domain fail-closed posture (sign-in/sign-up unavailable on a custom domain unless an *enabled* per-domain config exists; the global flags remain a kill-switch ceiling only) has **two implementations** whose SSO carve-outs deliberately differ:

1. **Model resolver** — `SigninConfig.resolve_signin_enabled_for_custom_domain` (and its signup twin, which has no carve-out: SSO signup flows through the signin path). Consumed by the branded-masthead link gate (`Core::Views::DomainSerializer#effective_signin_enabled?`), the runtime POST gates (`Core::Controllers::Base`), and the settings API `details`. Its SSO carve-out (via the `domain_id:` kwarg) is **tenant-only**: `SsoConfig.tenant_sso_available_for?`. A branded front door advertises only what the domain owner opted into; the operator's platform-SSO fallback is deliberately out of scope, so a platform-fallback-only domain gets no masthead Sign In link.
2. **`ConfigSerializer#resolve_signin`** — the /signin **page** display gate (`apps/web/core/views/serializers/config_serializer.rb`). It implements the same default-OFF posture inline, but its carve-out uses `sso_available?`, which **includes platform-SSO fallback** via `build_sso_config`. The page must stay reachable and render platform provider buttons when the operator allows fallback for tenants and the master switch is on (#3911) — even though the masthead shows no link for that same domain.

The divergence is confined to *which SSO sources the carve-out consults*; the fail-closed default and the kill-switch ceiling are identical in both. Maintenance rule: **change one, check the other** — any change to the default-OFF condition or a carve-out in either implementation must be verified against (and kept in lockstep with) the other, since only the model resolver is covered by invariant 4's "one resolver" discipline.

**Master switch gates the tenant carve-out** (#3901 follow-up): `SsoConfig.tenant_sso_available_for?` consults `SigninConfig.global_auth_enabled` (`AUTH_ENABLED` alone, strict boolean) before the credential checks. With the master switch off, sessionauth is never registered and every session reads as unauthenticated, so an SSO sign-in could only mint a session the app ignores — the carve-out must not advertise it. Because the predicate is shared, all tenant-SSO gates go dark together: the masthead link (impl 1), the /signin page's tenant source (impl 2 via `resolve_tenant_sso_config`), the settings API `details`, and the omniauth runtime hook (`apps/web/auth/config/hooks/omniauth_tenant.rb`), which treats the state like an unconfigured tenant (reject, or platform fallback per policy). `AUTH_SIGNIN` remains deliberately unconsulted by the carve-out — it retires only the password/email path.

**Master switch darkens the platform fallback and the Rodauth `/auth` surface** (#3911): the same predicate (`SigninConfig.global_auth_enabled`) gates the operator's platform-SSO fallback at both of its surfaces — display (`ConfigSerializer#build_platform_sso_config` serializes platform SSO as disabled with no providers) and runtime (the omniauth tenant hook's `handle_missing_tenant_config` refuses fallback even when the fallback policy allows it) — mirroring `tenant_sso_available_for?`. The Rodauth `/auth` surface gets a **request-level guard in `Auth::Router`**: with `AUTH_ENABLED=false`, every `/auth/*` request returns 404 before `r.rodauth` runs — no credential processing, no session mint — except `/auth/health`, which stays serviceable. The registry **mount is unchanged**: mount-gating was rejected because Core's `routes.txt` re-serves several `/auth/*` paths, and unmounting would silently reroute them to simple-mode controllers with a different response shape. Here too, `AUTH_SIGNIN` is deliberately narrower and is not consulted.

## References — source of truth is this ADR; these implement it

Backend:
- `lib/onetime/models/custom_domain/signin_config.rb` — resolver + `global_signin_enabled`
- `lib/onetime/models/custom_domain/signup_config.rb` — resolver + `global_signup_enabled`
- `apps/web/core/controllers/base.rb` — runtime gates (`signin_enabled?` / `signup_enabled?`)
- `apps/web/core/views/serializers/config_serializer.rb` — display gate (`resolve_signin` / `resolve_email_auth`); platform-SSO master-switch gate (#3911)
- `apps/web/auth/router.rb` — request-level `/auth` surface guard on `AUTH_ENABLED` (#3911)
- `apps/web/auth/config/hooks/omniauth_tenant.rb` — omniauth tenant hook (master-switch gate on platform fallback, #3911)
- `apps/api/domains/logic/signin_config/*` / `signup_config/*` — settings API (`details` serialization)

Frontend:
- `src/shared/composables/useAuthOverrideState.ts` — shared derived state + writes-materialize rule
- `src/shared/composables/useSigninConfig.ts` / `useSignupConfig.ts` — per-feature composables (seeding, pinning saves)
- `src/apps/workspace/components/domains/DomainAuthOverrideBanner.vue` — status line / badge / dormant warning
- `src/apps/workspace/components/domains/DomainSigninConfigForm.vue` / `DomainSignupConfigForm.vue`

Tests:
- `try/unit/models/custom_domain_auth_killswitch_try.rb` — resolver truth table (kill switch, narrowing, inherit)
- `try/unit/models/custom_domain_auth_default_off_try.rb` — custom-domain default-OFF resolvers + tenant-SSO carve-out (#3672)
- `apps/api/domains/spec/integration/simple/domain_signup_config_spec.rb` — settings API contract
- `src/tests/composables/useSigninConfig.spec.ts`, `src/tests/apps/workspace/components/domains/DomainSigninConfigForm.spec.ts` — seeding + materialization

## Amendments

### 2026-08-11 — `restrict_to` semantics: enforcement, degradation, webauthn status, identity scope

PR #4130 shipped the display half of domain `restrict_to` (every value
rendered, single-method picker enabled) and recorded two deliberate gaps —
no server-side enforcement, no server-side re-validation — as wanting a
decision rather than a drive-by change. The decisions below resolve them.
Deciding principle throughout: security, privacy, and long-term codebase
health; the default posture is fail-closed.

#### A1. Domain `restrict_to` is an access control, not a display preference

Normative: when resolution yields a single method for a request host, the
server MUST reject submission of every other method on that host — crafted
POSTs included. Corollary, broader than `restrict_to`: a disabled auth
method must never function even when fully and correctly configured (e.g. a
complete SSO configuration with SSO disabled stays dark at every surface).
Configuration presence is never availability.

Current state, for the record: display-only. The only server-side teeth
anywhere is *global* `restrict_to='sso'` via `SsoOnlyGating`
(account-management operations, keyed to the global value). Enforcement is
follow-up work to PR #4130; until it ships, domain `restrict_to` must not
be documented as an access control.

Scope note: A1 is request-host enforcement — *which methods* work on this
host. *Which accounts* may authenticate on this host is A6.

#### A2. Invariant 5: `restrict_to` resolution is model-owned

Invariant 4's discipline extends to `restrict_to`: resolution moves behind
a model-owned resolver (`SigninConfig.resolve_restrict_to(global, config)`)
consumed by all three gates — display (`ConfigSerializer`), runtime
(`Core::Controllers::Base`, once A1 ships), and settings API `details`
(A4). No caller re-derives. `ConfigSerializer#resolve_restrict_to`, today
an inline display-only implementation — exactly the drift shape invariant 4
exists to kill — becomes a consumer. `email_auth_enabled`'s inline AND
resolution follows the same rule when next touched.

#### A3. Domain-level degradation is fail-closed

A domain restriction whose backing method is unavailable — globally
disabled, credentials dormant, or incapable on this host — resolves to
*sign-in unavailable* (or its method-specific notice, e.g. "SSO required").
It never widens to standard mode: widening re-exposes exactly the methods
the domain owner chose to hide. This retires two fail-open paths:

- `restrict_to='sso'` with dormant credentials falling through to
  password/email forms (display side fixed in #4123/#4130; runtime side
  lands with A1);
- the frontend's globally-disabled-method → standard-mode fallback shipped
  in #4130 (retired by A4's repoint).

The webauthn special case is deleted entirely: the resolver's
webauthn→standard-mode degradation and the PUT carry-over exemption both
guarded a legacy population of persisted `restrict_to='webauthn'` records
that does not exist — webauthn first functioned in the same release that
introduced the PUT write gate. A stray value is invalid data and fails
closed like the rest.

No asymmetry (ratified 2026-08-11, superseding this amendment's original
drop-to-standard carve-out): the *global* path fails closed too. A global
`restrict_to` naming a method the system can already determine is
unavailable at boot is a fatal boot error, not a fallback. Today
`AuthConfig#restrict_to` silently returns nil when the named method's
prerequisites fail and every caller reads that as "unrestricted" — the
install widens to standard mode with no signal at all, re-exposing exactly
the methods the operator restricted away. The #4062 lockout-trap argument
was considered and overruled: a boot failure *is* the loud failure,
surfaced at deploy time to the operator who holds the config file and can
fix it; the trap to avoid is a silent runtime widen, not a refused boot.
Unavailability only discoverable after boot degrades fail-closed like the
domain path.

#### A4. Settings API serializes `effective_restrict_to`

`details` gains `effective_restrict_to` (A2 resolver output) alongside
`global_restrict_to`. The frontend fallback introduced in #4130 repoints at
it and client-side re-derivation is removed, per §3's principle that the
client displays resolver output and never re-implements resolution.

#### A5. Custom-domain webauthn: pending support, not banned (#4137)

There is no security, privacy, or UX objection to passkeys on custom
domains. WebAuthn origin binding (rp_id registrable-suffix match,
browser-enforced) is the protocol's phishing resistance working as
designed; the limitation is ours: `webauthn_rp_id` is already dynamic
(`request.host`), but every credential is registered on the canonical host
and `account_webauthn_keys` carries no rp_id column, so nothing can assert
— or be registered — on a branded domain. The sanctioned path is
per-domain credential scoping (#4137: rp_id column, host-filtered
allow-lists, per-domain registration UX). Related Origin Requests were
evaluated and rejected: browsers cap related origins at ~5 distinct labels
platform-wide, a nonstarter for unbounded customer domains.

Accordingly the existing guards — the PUT rejection of new webauthn
restrictions, fail-closed resolution (A3), and the suppressed passkey
tab/locked form row on custom domains — are **not-yet-supported guards,
not policy**. #4137 retires them, at which point `restrict_to='webauthn'`
becomes a valid, enforced domain restriction.

#### A6. Account↔domain identity scope (#4138)

Stance: an account's authenticatable surface is governed by its owning
domain/org policy. Canonical-pool accounts are not valid logins on branded
custom domains. Custom-domain signup, where the owner enables it, produces
org-scoped accounts — never canonical-pool accounts. Account-management
operations are governed by the owning org's auth policy: `SsoOnlyGating`
re-keys from global-only to owning-org policy under #4138 — never to the
request host, since account management is account-scoped, not host-scoped.

Both prevailing SaaS identity models agree on this invariant —
tenant-scoped identity (Keycloak realms, Slack workspaces) and global
identity plus domain claim (Notion managed users, Google Workspace): the
tenant's auth policy governs every auth surface for identities under its
authority. The current shared-pool behavior (any account authenticates on
any host with sign-in enabled) matches neither and is a long-standing
defect. A1's request-host enforcement is the interim mitigation (it
restricts methods, not accounts); #4138 is the robust fix.

#### A7. A1's reject semantics: not-found, not forbidden

A1 says the server MUST reject a restricted-away method; it does not say
how. Settled 2026-08-11: **reject as not-found**, matching Rodauth's
behavior for a feature that was never loaded — the route is simply
undefined and the router answers 404. Not a 403 gate.

The rationale is not secrecy. A 403 would leak close to nothing here: the
sign-in page on that host already advertises the single method it offers,
so the marginal disclosure is nil. Note also that OWASP's uniform-response
guidance is about *account* enumeration — whether a given email is
registered, a fact about a person — and does not govern disclosure of
server configuration. Reaching for it here would be citing the wrong rule.

The reason is A1's own corollary. A 403 gate means the handler is still
mounted, still reachable, still one bug away from executing; that is
configuration presenting as availability, the exact shape A1 exists to
kill. A disabled auth method should present no reachable surface at all.
Not-found is the honest description of what a restricted-away method is on
that host.

Implementation note, and the part principle does not settle: Rodauth mounts
routes once at boot, but `restrict_to` varies per request host, so routes
cannot be un-mounted per host. The gate is therefore request-time and
*emulates* non-existence rather than achieving it structurally. Two
consequences follow. First, the gate must cover every reachable route per
method — secondary endpoints included (verify, resend, callback,
ceremony-start), since a gate that covers the primary POST and misses
`webauthn-auth-begin` leaves the gap open while looking closed, which is
worse than no gate because it invites documenting `restrict_to` as an
access control it does not yet provide. Second, `SsoOnlyGating` predates
this decision and its existing reject shape may not match; reconcile the
two when A1 lands rather than leaving two conventions.

**A7 implementation findings (2026-08-11).** Rodauth's `route_hash` is built
once and frozen in `post_configure`, and `route!` is a frozen-hash lookup —
so returning nil from `login_route` per request does nothing. The gate is
`before_rodauth` (fires inside the matched route, after `@current_route` is
set and CSRF checked) halting with a 404, matching the app's existing 404
shape in `apps/web/auth/router.rb`. Host and strategy are on the request
env via `Onetime::Middleware::DomainStrategy`, which sits above the `/auth`
mount. This is Rodauth-supported, not a workaround; only the policy is ours.

Two surfaces sit outside `before_rodauth` and must be gated separately, or
enforcement is silently partial:

- **SSO** is not in `route_hash` at all — the OmniAuth request phase is
  served by middleware, so `before_rodauth` never fires. Gate at
  `omniauth_setup` and `before_omniauth_callback_route`, which already halt
  for tenant mismatch.
- **Simple mode** serves `POST /auth/login` from Core, not Rodauth, and its
  existing gate returns a 302 to `/`. Without a Core-side gate, enforcement
  is mode-dependent — present in full mode, absent in simple.

**Scope, settled — A7 governs the pre-auth sign-in surface only.**
Credential *management* endpoints reachable only when authenticated
(`change-password`, `webauthn-setup`, `webauthn-remove`) are deliberately
exempt from the 404 rule. This is not an oversight; per A1's own scope note,
A1 is request-host enforcement (*which methods work on this host*) while
account-scoped questions belong to A6/#4138. Management operations are
account-scoped, so keying them to the request host would be the wrong axis.
They stay with `SsoOnlyGating`, whose 403 + `error_key` is correct for an
already-identified user — converting that into a 404 would turn an
actionable error into a mystery. `SsoOnlyGating`'s divergence from A7 is
therefore ratified as a deliberate split, not a reconciliation debt.

Pre-auth password surfaces are *not* exempt: `create-account`,
`reset-password-request`, and `reset-password` are reachable unauthenticated
and go dark with the method.

#### A8. Resolution intersects; a domain config never widens a global restriction

Found while implementing A2 (2026-08-11). Resolution was **replace**: an
`enabled?` domain config decided alone, so an enabled domain config with
`restrict_to` *unset* erased a global restriction on that host. An operator
who globally restricted to SSO lost that restriction on any host where a
tenant enabled a signin config — a tenant escaping an operator-level
restriction, silently.

This is not a new policy. Invariant 1 already says explicit config may
narrow, never widen; the code contradicted an invariant this ADR already
carried. Normative resolution is intersection:

| global | domain | result |
|---|---|---|
| set | unset | global restriction stands |
| unset | set | domain restriction stands |
| set | set, equal | that method |
| set | set, different | `:unavailable` |
| unset | unset | `:unrestricted` |

Two different single-method restrictions have no intersection, so a
conflict fails closed rather than picking a winner. Picking one would mean
either a tenant overriding the operator (A8's whole defect) or the operator
silently discarding a tenant's deliberate setting.

#### A9. Conflicting `AUTH_*_ONLY` env flags are a boot error

Found while implementing A3-global (2026-08-11). `etc/defaults/auth.defaults.yaml`
renders `restrict_to` from four `AUTH_*_ONLY` env vars and emits **nothing**
when more than one is true. An operator setting both `AUTH_SSO_ONLY=true`
and `AUTH_PASSWORD_ONLY=true` gets no restriction and no signal. `AuthConfig`
cannot detect this — it receives only the rendered blank, so #4140's fix
does not reach it.

Same class as #4140, one layer up, and it fails closed the same way:
conflicting flags are a fatal boot error naming every flag set, per A3's
ratified position that boot-determinable unavailability fails loud. Zero or
one flag behaves as before.

Recorded for posterity: three independent silent fail-opens in one feature —
#4140 (availability check returning nil), A8 (domain widening past global),
A9 (template swallowing conflicts). Each was written by someone reasonably
choosing "degrade gracefully" at a local decision point. Graceful
degradation of an *access control* is a fail-open by another name; the
default for this feature is to refuse, loudly.

#### A10. Second-factor ceremonies are exempt — A7's enumeration corrected

Found while implementing A1 (2026-08-11). A7 listed `POST /webauthn-auth`
and `GET /webauthn-auth-js` among the endpoints to gate. That was wrong, and
A7's own stated principle overrides its own list.

Both routes carry `require_login` + `require_two_factor_not_authenticated` —
they are reachable only with a partially-authenticated session. That is
exactly the "reachable only when authenticated, therefore account-scoped"
test A7 uses to exempt `webauthn-setup` and `webauthn-remove`. `restrict_to`
governs which methods may be **offered as a sign-in choice** on a host; a
second factor is not a choice. The account has already authenticated with a
first factor the host permits, and which second factor it holds is a
property of the account — the #4138 axis, not the request host.

Gating them is a lockout: on a host restricted to `sso` or `password`, an
account whose second factor is a passkey could never complete the challenge.

The tell was an internal inconsistency: `otp_auth`, the TOTP second-factor
ceremony, was already exempt. The same ceremony must not be gated for one
authenticator and exempt for another. When classifying a route, ask which
axis it turns on — offer-time (host) or account-time (identity) — rather
than matching on the method name it happens to mention.

**Also corrected in A7's enumeration, found the same way:**

- `verify-account` and `verify-account-resend` were missing and ARE gated.
  Unauthenticated, and `verify_account_autologin?` mints a session, so a key
  issued on an unrestricted host would otherwise replay on a restricted one.
- The multi-phase magic link is not a route. With `email_auth` loaded,
  `POST /login` for a passwordless account dispatches a magic link via
  `force_email_auth?`, so route-level gating alone emits an `email_auth`
  credential on a password-restricted host. Closed at
  `before_email_auth_request`.
- `handle_internal_request` calls `before_rodauth` with a synthesized env
  carrying no Host. It must be exempt, or invite-signup autologin 404s.
- `webauthn-credentials` needs nothing — already `logged_in?`-gated
  throughout, hence exempt under A7's own rule.

The general lesson, recorded because A7 was written confidently and was
still short four entries: an endpoint enumeration written from documentation
is a hypothesis. The assertion that has teeth is the coverage spec reading
the live frozen `route_hash` and failing on any route classified neither
gated nor exempt — exemptions listed explicitly, never defaulted-open.

#### A11. Invite signup is gated; the internal-request exemption left a hole

Found while implementing A1 (2026-08-11). `POST /api/invite/:token/signup`
was the last unguarded path to mint a session by a restricted-away method.
It escaped every other gate because it creates the account through
`Auth::Config.create_account` (Rodauth `internal_request`), and A10 exempts
internal requests — correctly, since an internal request carries no request
host. But the *endpoint* does know the host. The exemption was written for
the inner call and silently covered the outer one.

Gated: `Auth::RestrictTo.allows?(env, 'password')` as the first line of
`raise_concerns`, before the rate limiter — a dark endpoint should cost no
budget and touch no invitation state. Rejects 404 per A7. `GET /:token` and
`POST /:token/accept` stay ungated: display surface and account-scoped
respectively.

**Why gating beats the surgical alternative.** The obvious softer fix —
create the account, suppress only the autologin — is wrong twice over, and
both errors are worth recording because they look like the careful choice:

1. It preserves nothing. This endpoint deliberately leaves the invitation
   *pending*; acceptance happens later via the `sessionauth` route. There is
   no "invite still accepted" state to protect. Its only outputs are an
   account and a session.
2. The orphan account it leaves behind actively strands the invitee. On an
   SSO-restricted tenant host, an unauthenticated SSO callback whose email
   matches an existing *unlinked* account hits the H-3 refusal in
   `apps/web/auth/config/hooks/omniauth.rb`, because the password-challenge
   interstitial mints on the platform surface only. The account we would
   have created is exactly what prevents SSO from creating a clean one.
   Creating nothing is what lets the invitee in.

No exemption is warranted on reachability grounds. The invitation email
links to the canonical host, but the endpoint is host-agnostic (served on
every host by a single `Rack::URLMap`) and the *global* `restrict_to` half
applies on canonical anyway. The live case is an SSO-only install; the
per-domain case is the edge, not the reverse.

Scope correction: this endpoint is full-mode-only in practice regardless of
the gate — `email_exists_in_authdb?` reaches `Auth::Database.connection`,
which is nil unless `full_enabled?`, so a simple-mode POST 500s before
reaching any of this.
