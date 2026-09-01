---
labels: admin-v2, security, backend
depends: 21-admin-audit-log
epic: "#3653"
---

# Admin rebuild: explicit, audit-logged impersonation operation (confirm-then-fix)

## Context

Part of the Colonel Admin Rebuild epic (Phase 4). The plan flags a possible authentication path in `authenticate_session.rb` where a colonel's passphrase may authenticate as any customer. This is UNVERIFIED by the code survey — it must be confirmed before any fix, and the fix must not be asserted as a known vuln in public artifacts until confirmed. Frame this as spike-then-fix.

## Scope

1. **Spike — confirm the behavior.** Read `authenticate_session.rb` and determine whether a colonel's passphrase can in fact authenticate a session as an arbitrary customer. Document the exact code path (or confirm it does not exist).
2. **If confirmed — replace it.** Swap the implicit path for an explicit impersonation operation that writes an `AdminAuditEvent` (see issue 21) on every use, or remove the capability entirely if it isn't needed by the console.
3. **If not confirmed —** record the finding and close; no code change.

## Grounding — files & pointers

- Suspected path: `authenticate_session.rb`.
- Audit event type / sink: `AdminAuditEvent` — see the Phase-1 admin-audit-log issue (21).
- Two-layer authz invariant an impersonation op must respect: `role=colonel` at the Otto router (`apps/api/colonel/routes.txt`, scope=internal) PLUS `verify_one_of_roles!(colonel:true)` in the logic class `raise_concerns`; `cust.verified?` required for any system role.
- Colonel logic handlers: `apps/api/colonel/logic/colonel/*.rb`.

## Acceptance criteria

- [x] Spike documents the exact `authenticate_session.rb` behavior: confirmed, or confirmed-absent. (confirmed-absent — see "Spike outcome" below)
- [ ] If confirmed: the implicit colonel-passphrase-as-any-customer path is removed.
- [ ] If confirmed: an explicit impersonation operation exists, gated by both authz layers, and writes an `AdminAuditEvent` on every invocation (actor colonel, target customer, timestamp).
- [ ] If confirmed: a test proves a non-audited impersonation path no longer exists.
- [x] If not confirmed: finding recorded (dead `@colonel` branch additionally removed as least-capability hardening).

## Spike outcome: confirmed-absent (then hardened)

Reviewed `apps/web/core/logic/authentication/authenticate_session.rb`. As of the
spike, `success?` read:

```ruby
!cust&.anonymous? && (cust.passphrase?(@passwd) || @colonel&.passphrase?(@passwd))
```

**Finding — the exploitable path was NOT present (confirmed-absent):**

- `@colonel` was never assigned anywhere in `apps/` or `lib/` — that line was its
  sole reference — so `@colonel&.passphrase?(@passwd)` evaluated `nil&.…` → `nil`
  → falsey on every real request. The colonel-passphrase-as-any-customer branch
  was inert.
- `raise_concerns` additionally bails on `@cust.nil?`, so the branch was doubly
  unreachable.

No authenticated-as-arbitrary-customer session could be minted via this method,
so there was no live vulnerability to exploit and no public artifact asserts one.

**Hardening applied (least-capability, zero-risk since the clause was dead):**

The dead `|| @colonel&.passphrase?(@passwd)` clause and the `@colonel` reference
were removed so `success?` is now simply:

```ruby
!cust&.anonymous? && cust.passphrase?(@passwd)
```

Rationale: leaving an unexplained colonel-passphrase branch in the hottest auth
method was a latent hazard — any future assignment of `@colonel` (an
impersonation feature, an injecting strategy, `instance_variable_set`) would
silently re-enable an **unaudited** impersonation path with no `AdminAuditEvent`,
exactly what this ticket exists to prevent. Per "prefer removal over replacement
— least capability wins," the branch is deleted rather than replaced. An inline
comment at the call site records why no such branch belongs there.

No explicit impersonation operation was built: the rebuilt console has no
impersonation need. If one ever arises it must be an explicit operation gated by
both authz layers (Otto `role=colonel` + `verify_one_of_roles!(colonel:true)`)
that writes an `AdminAuditEvent` on every invocation.

## Notes / risks

- Do not assert the vulnerability as fact in commit messages, PRs, or public docs until the spike confirms it.
- Depends on the audit log (21) landing first so the "explicit + logged" replacement has a sink to write to.
- Prefer removal over replacement if the console has no genuine impersonation need — least capability wins.

---

## 2026-07-25 — re-raised as a CLI verb (#3731), re-affirmed no-ship

Issue #3731 ("CLI support commands over the Operations layer") proposed
`bin/ots customers impersonate` among its candidate verbs. **Outcome: not built,
and not deferred — declined.** This section records the reasoning so the next
person does not re-derive it.

This is a design decision about product scope and system capability. It is not a
report of a defect: the spike above already established that no
authenticate-as-arbitrary-customer path exists, and nothing in #3731 changed
that.

### (a) The ratified outcome was removal, and #3731 supplied no reason to reverse it

The spike above closed with "prefer removal over replacement — least capability
wins," and the code was changed accordingly. A standing guard comment now lives
at the call site — `apps/web/core/logic/authentication/authenticate_session.rb:214-225`,
in `success?` — recording that no impersonation clause belongs there and what
would be required if one ever did.

Issue #3731 is a refactoring epic. Its stated premise is thin CLI adapters over
Operations that already exist, with review gated on "does this change behaviour?
it should not." Reversing a ratified product decision is exactly the kind of
change that premise excludes. Nothing in #3731 introduced a product driver — no
support workflow, no customer request, no console gap — that the earlier decision
had not already weighed.

### (b) A CLI adapter structurally cannot satisfy this spec's own audit requirement

The acceptance criteria above require an `AdminAuditEvent` on every invocation
naming "actor colonel, target customer, timestamp."

Every CLI adapter in the tree passes a shared sentinel actor:
`Customers::Shared::CLI_ACTOR = 'cli'` (`lib/onetime/cli/customers/shared.rb:18`),
mirrored by `CLI_ACTOR = 'cli'` in `lib/onetime/cli/session_command.rb:317` and
`lib/onetime/cli/domains/create_command.rb:33`. The shell has no authenticated
operator identity to pass; `'cli'` is an honest statement that the actor is a
shell session, and it names no human.

For every other CLI verb this is acceptable, because the mutation is
reconstructible from the resulting state — an operator can see *that* a plan was
changed, a domain repaired, an org reconciled, and the resulting state is the
record. Impersonation is different in kind: the operator's identity **is** the
control being relied on. An audit row reading `actor=cli` against an
impersonation verb would be the only record of who did it, and it identifies
nobody.

ADR-023 ("Audit Actor Attribution Accuracy — Never Fabricate an Actor") settles
this directly: an audit event must never record a value that "asserts a fact we
cannot support." A CLI impersonation adapter would either record `'cli'` — true
but useless for the one control that matters — or accept an operator-supplied
name, which is an unverified assertion. Neither satisfies the requirement above.

A colonel-console adapter does not have this problem, because the console has an
authenticated colonel. That is a different proposal from the one #3731 raised,
and it is not being made here.

### (c) Requirements any future impersonation adapter must first satisfy

Three properties of the current session design would each have to be solved
*before* an impersonation adapter could be considered. These are stated as
requirements on a hypothetical future design, not as defects in the present one —
none of them is a problem for ordinary sessions, which is why the design is the
way it is.

1. **Bounded lifetime.** An impersonation session would need a lifetime shorter
   than an ordinary session, independent of the configured expiry. The session
   store re-applies the configured `expire_after` on every commit
   (`lib/onetime/session.rb:663-673`), which is correct for ordinary sessions —
   activity should extend them. A shorter-lived session variant is a new concept
   the store does not have today, and it would have to be built before, not
   alongside, any impersonation feature.

2. **A marker that cannot be absent.** An impersonation session would need to be
   distinguishable from an ordinary one at every point that reads session state.
   The session sidecar primitive is explicitly not the right home: its admission
   rule (`lib/onetime/session/sidecar.rb:77-85`) is that a field may be
   externalized "ONLY if its absence is the safe state," and lists fields whose
   absence grants anything as permanently ineligible. An impersonation marker
   fails that rule in the obvious direction — a session with the marker missing
   is just an ordinary session. It would have to live somewhere absence is
   impossible.

3. **Revocation is not a sufficient control.** Some capabilities reachable with a
   session identity are irreversible, and some produce externally-valid artifacts
   that outlive the session that created them. Revoking an impersonation session
   does not undo the first category or invalidate the second. Any design would
   therefore need capability restriction at the point of use — a positive list of
   what an impersonating session may do — rather than relying on being able to
   end the session afterwards.

Solving all three is a substantial piece of session-architecture work. It is not
adapter work, and it is not something to attach to a refactoring epic.

### The request-path guard was deliberately not built

A guard that recognizes an impersonation marker and restricts behaviour on the
request path was considered and rejected as speculative machinery.

It would be a change to the hot path of every authenticated request, in more than
one independent identity-resolution site
(`lib/onetime/application/auth_strategies/base_session_auth_strategy.rb`,
`lib/onetime/middleware/identity_resolution.rb`, and the session helper used by
the web surfaces), for a feature that is not shipping. Unused security machinery
tends to acquire users: the dead `@colonel&.passphrase?` clause this ticket
removed was itself an unused branch that had to be argued about years after
whoever wrote it moved on. Adding an inert impersonation guard would recreate
exactly that hazard in the same code path.

If an impersonation feature is ever genuinely needed, the guard is part of *that*
project and should be built with a caller, not ahead of one.

### What operators should use instead

The console already covers the reproduction cases impersonation is usually
reached for, without assuming another user's identity:

- `GET /users/:user_id` — `ColonelAPI::Logic::Colonel::GetUserDetails`
  (`apps/api/colonel/routes.txt:25`). Account state, verification, role, plan.
- `GET /users/:user_id/sessions` — `ColonelAPI::Logic::Colonel::ListCustomerSessions`
  (`apps/api/colonel/routes.txt:83`), with per-session and bulk revocation at
  `:85-86`. Answers "what is this user's session state right now."
- `POST /entitlement-preview` — `ColonelAPI::Logic::Colonel::SetEntitlementPreview`
  (`apps/api/colonel/routes.txt:16`). For plan- and entitlement-shaped bug
  reports, this reproduces what the customer's plan makes visible **in the
  colonel's own session**, which keeps the audit trail accurate.

Neither assumes another user's identity, and both leave an honest actor in the
trail. That combination is what made the impersonation verb unnecessary in the
first place — it remains the reason.

---

## 2026-09-01 — Addendum: impersonation built

An impersonation feature was built, as a colonel-console operation with an
authenticated operator — the case section (b) above explicitly left open ("A
colonel-console adapter does not have this problem... That is a different
proposal from the one #3731 raised"). The design is recorded in
[ADR-041](../../../adr/adr-041-colonel-impersonation-session-overlay.md). The
CLI verb declined in the 2026-07-25 section is still declined, and the inert
bearer-grant primitive that preceded this work is removed.

The three §(c) requirements are met as follows.

**1. Bounded lifetime.** The session marker carries its own `expires_at`, set
from a fixed 30-minute constant with no caller-supplied TTL, and the
per-request impersonation middleware treats an expired marker as ended. The
session store is untouched: `expire_after` keeps extending ordinary sessions on
activity, which was always correct — the impersonation window simply does not
ask it for anything.

**2. A marker that cannot be absent.** Resolved by inverting the direction
rather than by finding a home where absence is impossible. Impersonation is an
overlay, not a swap: `session['external_id']` stays the colonel's for the whole
window and a separate marker names the effective customer. A lost marker
therefore leaves an ordinary colonel session — absence *is* the safe state — so
the design satisfies the same rule the sidecar admission rule encodes, in the
direction the rule requires. It also keeps the session indexed under the
colonel rather than migrating it into the target's `active_sessions`.

**3. Capability restriction at the point of use.** The middleware enforces a
positive list: safe methods on non-blocked paths, plus the stop endpoint;
everything else is refused with 403. The list is safe methods *minus known
consuming reads* — a secret fetch carrying `?continue=true` burns the secret
and is denied whatever its method, and any future GET that mutates has to join
that deny list explicitly. `/api/auth/*`, `/auth/*`,
`/api/colonel/*`, and `/colonel*` are blocked regardless of method — the
Rodauth block because `account_id` remains the colonel's, so a credential
change there would act on the operator's own account. Nothing is relied on
being undoable afterwards.

### Supersedes "The request-path guard was deliberately not built"

That section is superseded on its own terms. Its objection was to inert
machinery — a guard in the hot path of every authenticated request, across
several identity-resolution sites, for a feature that was not shipping — and it
closed by stating the condition under which the objection lifts: "If an
impersonation feature is ever genuinely needed, the guard is part of *that*
project and should be built with a caller, not ahead of one." That is what
happened. The guard ships in the same change as the console operation that
creates the marker it recognizes, and the several identity-resolution sites are
consolidated behind one shared resolver rather than each growing its own copy
of the check. The reasoning stands; only its premise (no caller) has changed.

Line references in the sections above have drifted with the code: the session
store's expiry re-application is now `lib/onetime/session.rb:703-708`, and the
sidecar admission rule is now `lib/onetime/session/sidecar.rb:99`.
