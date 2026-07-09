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

- [ ] Spike documents the exact `authenticate_session.rb` behavior: confirmed, or confirmed-absent.
- [ ] If confirmed: the implicit colonel-passphrase-as-any-customer path is removed.
- [ ] If confirmed: an explicit impersonation operation exists, gated by both authz layers, and writes an `AdminAuditEvent` on every invocation (actor colonel, target customer, timestamp).
- [ ] If confirmed: a test proves a non-audited impersonation path no longer exists.
- [ ] If not confirmed: finding recorded, issue closed with no code change.

## Notes / risks

- Do not assert the vulnerability as fact in commit messages, PRs, or public docs until the spike confirms it.
- Depends on the audit log (21) landing first so the "explicit + logged" replacement has a sink to write to.
- Prefer removal over replacement if the console has no genuine impersonation need — least capability wins.
