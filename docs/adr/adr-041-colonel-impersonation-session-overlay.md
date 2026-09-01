---
id: "041"
status: accepted
title: "ADR-041: Colonel Impersonation as a Bounded Read-Only Session Overlay"
---

## Status

Accepted

## Date

2026-09-01

## Context

Support work periodically needs to see the application as a specific customer
sees it: a rendering bug that only reproduces against that account's data, a
"the button isn't there" report where the console's plan and entitlement views
say the button should be there. The console's existing answers — user detail,
session listing, entitlement preview — cover the plan-shaped cases and none of
the rendering-shaped ones.

`docs/specs/colonel-ui/initial-build-out/52-impersonation-audit-fix.md` §(c)
already set the price of admission. Any impersonation design must first supply
a bounded lifetime independent of the session store's configured
`expire_after` (re-applied on every commit, `lib/onetime/session.rb:703-708`);
a marker that cannot go missing, because the session sidecar's admission rule
(`lib/onetime/session/sidecar.rb:99`) admits only fields whose *absence is the
safe state*; and capability restriction at the point of use, because some
capabilities reachable with a session identity are irreversible and some emit
artifacts that outlive the session.

PR #4359 approached this from the other end. It landed an inert
`ImpersonationGrant` bearer-token primitive (`lib/onetime/models/impersonation_grant.rb`)
plus a `bin/ots customers impersonate` CLI issuer, deferring the redemption
side. Both are removed here. The CLI issuer cannot satisfy the spec's own
audit requirement: every CLI adapter passes the sentinel actor
`Customers::Shared::CLI_ACTOR = 'cli'`, and
[ADR-023](adr-023-audit-actor-attribution-accuracy.md) forbids recording an
actor the system cannot verify — for impersonation the operator's identity *is*
the control being relied on, so an `actor=cli` row identifies nobody. With no
CLI issuer, the grant has nothing to carry: the only redeemer that yields a
verified actor is the authenticated colonel on the web surface, and for that
redeemer issue and redeem happen inside a single request. A bearer token that
never crosses a boundary is a credential with no journey — pure attack surface.
It is also not break-glass: it grants no access the colonel's own session does
not already have.

## Decision

Impersonation is a marker **overlaid on the colonel's own logged-in session**,
bounded to 30 minutes, restricted to a positive list of safe requests, and
audited at both ends.

Section headings declare their own citation anchors
(ADR-036#anchors-are-declared); cite `ADR-041#slug`, not positions. <!-- adr-lint:ignore -->

### Overlay, never swap {#overlay-not-swap}

`session['external_id']` keeps the **colonel's** external id for the entire
impersonation. The marker is a separate key:

```ruby
session['impersonation'] = {
  'id' => 'imp_…', 'target_extid' => …, 'target_email' => …,
  'reason' => …, 'started_at' => …, 'expires_at' => …,
}
```

One shared resolver — `Onetime::SessionImpersonation`, in
`lib/onetime/session/impersonation.rb` (a flat name, not nested: `Onetime::Session`
is a class) — decides the effective customer from (principal, marker) and is the
only place that decides it; the three sites that today read
`session['external_id']` independently
(`lib/onetime/application/auth_strategies/base_session_auth_strategy.rb`,
`lib/onetime/helpers/session_helpers.rb`,
`lib/onetime/application/auth_strategies/helpers.rb`) call it.

This is what satisfies §(c)'s absence requirement without needing a home where
absence is impossible: a lost marker leaves an ordinary colonel session, which
is the safe direction, so the sidecar's admission rule is not in tension — the
marker simply stays in the blob and is never externalized. Overlaying also
keeps the session indexed under the colonel in `TrackMetadata` /
`active_sessions`, so the operator's session never migrates into the target's
session list and never appears there to be revoked, listed, or counted.

The principal's own gates keep applying to the principal: suspension and
credential-watermark revocation are evaluated against the colonel, unchanged.
If the principal stops being a verified colonel, or the target cannot be
loaded, is suspended, or is itself a colonel, the marker is ended with the
matching `ended_by` and the request continues **as the colonel** — never a 401,
which would strand the operator in a session they cannot use or leave.

### Thirty minutes, enforced by the context middleware {#bounded-lifetime}

The marker carries `expires_at`, set from a fixed constant (30 minutes). There
is no caller-supplied TTL. `lib/onetime/middleware/impersonation_context.rb`
— mounted beside `Onetime::Middleware::EntitlementPreviewContext`
(`lib/onetime/application/middleware_stack.rb:616`) and modelled on it — reads
the marker once per request, treats an expired marker as ended, and publishes
the result as a Fiber-local context so the banner and the served identity
cannot disagree. This is a lifetime the session store does not need to learn
about, which is the point: `expire_after` continues to do the right thing for
ordinary sessions.

### A positive list, not a deny list {#positive-list}

While the marker is active the same middleware allows only safe methods
(GET/HEAD/OPTIONS) on non-blocked paths, plus the stop endpoint. Everything
else is refused with 403 — JSON `{error: <human sentence>, error_code:
'impersonation_read_only'}`, or a minimal HTML 403 for page requests. Three
path classes are blocked outright, regardless of method:

- `/api/auth/*` and `/auth/*` — Rodauth authenticates from its own
  `account_id`, which is still the **colonel's** account. A "change password"
  or "add passkey" there would act on the operator's own credentials, not the
  target's. This is the sharpest consequence of choosing overlay over swap and
  the reason the block is unconditional rather than method-based.
- `/api/colonel/*` and `/colonel*` — no admin powers while presenting as
  someone else. The effective-customer role check would already 403 these; the
  explicit block makes the rule testable and stops it from depending on a
  role-resolution detail.

The list is therefore **safe methods minus known consuming reads**, not safe
methods. Implementation found one read that mutates: `GET /api/v2/secret/:id`
and `GET /api/v3/secret/:id` with `?continue=true` burn the secret, because
`V2::Logic::Secrets::ShowSecret#process_params` gates the reveal on the
parameter rather than on the request method. The guard denies those requests
regardless of method. Standing obligation: a GET that mutates is invisible to a
method-based rule, so any future one must be added to the deny list at the same
time it is written — the rule cannot discover it.

This is §(c)'s third requirement, and it is the requirement revocation cannot
substitute for: refusing the write is the only control that works on an
irreversible action or on an artifact that outlives the session.

### The stop path is not a colonel path {#stop-is-reachable}

`POST /api/account/impersonation/stop` (AccountAPI) is `auth=sessionauth` with
**no** `role=` option and lives outside `/api/colonel/*`, because a session that is
denied the colonel surface must still be able to end its own impersonation —
and because `/api/colonel/*` sits behind `AdminNetworkIsolation`
(`lib/onetime/middleware/admin_network_isolation.rb`), which can be configured
to a network the customer surface is not served on. Authorization is the
principal's: colonel, verified, and a marker active; anything else gets 404
rather than disclosing the endpoint to ordinary sessions.

### Both ends are audited, and the reason is mandatory {#audited-both-ends}

Start emits `customer.impersonate.start` (actor: colonel extid, target:
customer extid, detail: reason, impersonation id, expires_at); the reason is
required and carried in the record. Stop emits `customer.impersonate.stop`
with the impersonation id, duration, and an `ended_by` of `operator`,
`expired`, `logout`, `colonel_demoted`, `target_missing`, `target_suspended`,
or `target_privileged`. Both verbs are emitted from the lib primitive so every
path produces the same shape — an impersonation that ends by timeout is as
visible in the trail as one the operator ended. `GET /logout` stays reachable
while impersonating and destroys the whole session, so
`Core::Controllers::Authentication#logout` emits the audited stop
(`ended_by: 'logout'`) *before* tearing the session down; otherwise the one
path that certainly ends an impersonation would be the one that never records
it. Existing failure auditing on the start operation stays, so refused attempts
are also recorded.

Starting an impersonation clears the session's entitlement-preview state
through `Onetime::EntitlementPreview.clear_session!(session)` — extracted so
the start operation and `SetEntitlementPreview#clear_test_mode` share one clear
path rather than each naming the keys.
Two overlays on one session would produce a view that is neither the customer's
real state nor a stated hypothetical, and no reader of a bug report could tell
which they were looking at.

## Alternatives rejected

**A CLI-minted session.** Rejected on [ADR-023](adr-023-audit-actor-attribution-accuracy.md):
the shell has no verified operator identity, so the row reads `actor=cli` and
names nobody — useless for the single control the feature depends on. An
operator-supplied name would be an unverified assertion, which is worse.

**A bearer grant redeemed in a fresh browser context** (PR #4359's shape).
Whoever redeems the grant must be a verified colonel for the audit trail to
mean anything; once that is required, the redeemer is already authenticated in
the browser and the grant carries nothing across the boundary it was invented
to cross. It adds a short-lived credential in a URL or header, with the
storage, expiry, single-use, and leak-handling obligations that implies, to
move information between two points inside one request.

**Swapping `session['external_id']` to the target.** Simplest to write and
wrong in both directions §(c) warns about. Absence becomes unsafe: lose the
"you are impersonating" marker and what remains is a fully-authenticated
session *as the customer* with no indication it was minted by an operator.
And it migrates the session into the target's identity everywhere the session
is indexed — `TrackMetadata` and `active_sessions` — so the operator's session
appears in the customer's session list and the customer's session-revocation
controls act on it.

## Consequences

An impersonating session can read the customer surface and nothing else. It
cannot create, reveal, or burn a secret; cannot change account settings,
credentials, or MFA; cannot make a billing change; cannot use the colonel
console; cannot start a second impersonation. The two things it can always do
are stop and log out, and both are audited. Operators reproducing a
write-path bug still cannot do so as the customer — that is the deliberate
limit, and the escalation path remains asking the customer.

The cookie is host-scoped, so impersonation applies only to the host the
console was used on. Custom-domain hosts are not covered: an operator who
impersonates on the canonical host and then visits a customer's custom domain
is anonymous there, not impersonating. This is a real gap for custom-domain
bug reports and is not addressed here.

Expiry is lazy. The marker ends on the first request after `expires_at`, not on
a timer, so a session left idle past the window is still nominally
impersonating until it is used again — at which point the request is served as
the colonel and the stop event is recorded with the expiry time it should have
had. Nothing is authorized in the interval, because nothing is requested in it.

Every future identity-resolution site inherits an obligation: read the
effective customer through the resolver, not `session['external_id']`. A site
that reads the raw field will silently act as the colonel while the operator
believes they are seeing the customer. `lib/onetime/middleware/identity_resolution.rb`
is non-authoritative today and is left alone with a comment saying so.

## Related

- [ADR-023](adr-023-audit-actor-attribution-accuracy.md): never fabricate an
  audit actor — the reason the CLI issuer and the bearer grant were removed
- `docs/specs/colonel-ui/initial-build-out/52-impersonation-audit-fix.md`:
  the confirm-then-fix spike, the §(c) requirements this design answers, and
  the 2026-09-01 addendum recording that they are met
