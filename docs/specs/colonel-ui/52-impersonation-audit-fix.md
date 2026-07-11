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
