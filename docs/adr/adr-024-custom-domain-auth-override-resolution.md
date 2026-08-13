---
id: 024
status: accepted
decided: 2026-07-11
title: "ADR-024: Custom-Domain Auth Override Resolution and Single-Control Settings UI"
---

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

### Custom-domain default-OFF diverges by SSO source, deliberately (#3672)

Custom domains are fail-closed by default: sign-in/sign-up is unavailable
unless an *enabled* per-domain config exists, and the global flags are a
kill-switch ceiling only. Two implementations enforce this — the model
resolver (masthead link, runtime POST gates, settings API) and
`ConfigSerializer#resolve_signin` (the /signin page display gate) — and
their SSO carve-outs intentionally differ: the masthead advertises
tenant-configured SSO only, while the /signin page also renders the
operator's platform-SSO fallback when the operator allows it. The
fail-closed default and the kill-switch ceiling are otherwise identical in
both; a change to either must be checked against the other.

`AUTH_ENABLED` (the master switch) disables both the tenant SSO carve-out
and the platform fallback, including the Rodauth `/auth` surface itself.
`AUTH_SIGNIN` is narrower: it disables the password/email path only and
does not touch either SSO carve-out.

## References

Source of truth is this ADR. Principal implementation: the model resolvers
in `lib/onetime/models/custom_domain/signin_config.rb` and
`signup_config.rb`. Coverage is asserted by
`try/unit/models/custom_domain_auth_killswitch_try.rb` and
`apps/api/domains/spec/integration/simple/domain_signup_config_spec.rb`.
Use source search for the current call sites rather than treating this list
as an inventory.

`restrict_to` enforcement, degradation, and coverage-scope decisions live in
[ADR-034](adr-034-restrict-to-enforcement.md). Account↔domain identity scope
lives in [ADR-035](adr-035-tenant-identity-auth-policy-scope.md).
