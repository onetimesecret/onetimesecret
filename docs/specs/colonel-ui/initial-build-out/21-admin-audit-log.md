---
labels: admin-v2, phase-1, backend
depends: none
epic: "#3653"
---

# Admin rebuild: AdminAuditEvent — every mutating operation records actor/verb/target/result

## Context
Part of the Colonel Admin Rebuild epic. Phase-1: born in the customers slice so audit logging is free in every later phase rather than retrofitted. Every mutating admin operation records who did what to whom, and the result.

## Scope
- Add an `AdminAuditEvent` **Familia model** backed by a **capped sorted set** (bounded retention). Fields: actor (colonel identity), verb (operation name), target (customer/resource id), result (success/failure symbol + minimal detail).
- Provide a write path that operations call at the end of `#call` — so any op extracted in #20 (SetRole, SetVerification, Purge, …) records an event without per-endpoint plumbing.
- Read path sufficient for a future admin audit view (list newest-first, bounded).

## Grounding — files & pointers
- Model conventions: follow existing Familia Horreum models and the operations contract in `lib/onetime/operations/README.md` (ops return symbols / immutable `Data` — the audit write consumes that result).
- Operations that will emit events: `Operations::Customers::*` extracted in #20 (based in `apps/web/auth/operations/` + central). Colonel logic base `apps/api/colonel/logic/base.rb`.
- Capped sorted set: mirror existing Familia sorted-set retention patterns in the codebase (bounded event history — see receipt/event-feature study for the capped sorted-set precedent).

## Acceptance criteria
- [ ] `AdminAuditEvent` Familia model persists actor, verb, target, result; backed by a capped sorted set with bounded size.
- [ ] A single write helper lets an operation record an event from within `#call` (no per-endpoint duplication).
- [ ] Every mutating customer operation in #20 emits exactly one event (success and failure both recorded).
- [ ] Events are readable newest-first for a future audit view.
- [ ] Tryouts + RSpec coverage: event written on success, on failure, and capped-set trimming enforced.

## Notes / risks
- Keep it stateless from the op's perspective: the op passes actor/verb/target/result; the model owns storage + capping.
- No HTTP/session inside the model or write helper (operations contract).
- Retention cap is a deliberate design point — pick a bound and document it; unbounded audit sets are a memory risk in Valkey.
