---
labels: admin-v2, backend, tech debt, performance
depends: none
epic: "#3653"
---

# Admin rebuild: replace SCAN-counted secret counts with per-customer counters

## Context

Part of the Colonel Admin Rebuild epic (backend debt, §7 — fix while in there). Per-owner secret counts are currently derived from a Redis SCAN over `secret:*` keys with a 10k cap, so any owner past 10k secrets is silently undercounted. Since the admin rebuild touches these surfaces, replace the scan with maintained counters.

## Scope

- Replace the SCAN-over-`secret:*` count (10k cap) with a per-customer counter.
- Maintain the counter at the `Receipt.spawn_pair` chokepoint — the single place secrets are created — so every create/expire path updates it exactly once.
- Backfill existing customers' counters once at rollout.
- The load-all `ListUsers` pagination is out of scope here — it is handled in issue 20 (ops customers extraction).

## Grounding — files & pointers

- Creation chokepoint to instrument: `Receipt.spawn_pair`.
- Colonel logic handlers (where the count is consumed): `apps/api/colonel/logic/colonel/*.rb`.
- Colonel API surface: `/api/colonel`, routes `apps/api/colonel/routes.txt`.
- Related prior art to link: #2211 "Colonel API using blocking Redis KEYS operations" (closed).

## Acceptance criteria

- [ ] Per-customer secret count comes from a maintained counter, not a SCAN.
- [ ] The counter is incremented/decremented at `Receipt.spawn_pair` (and the corresponding expire/destroy path), never double-counted.
- [ ] Counts are correct beyond 10k secrets per owner.
- [ ] A one-time backfill populates counters for existing customers.
- [ ] No remaining `secret:*` SCAN in the count path.
- [ ] Issue links #2211 as prior art.

## Notes / risks

- Counter drift is the main risk: ensure every secret create AND every removal/expiry path passes through the instrumented chokepoint, or the counter diverges from reality.
- Consider a periodic reconciliation or a colonel-only recount tool as a safety valve.
- Keep the change additive to CLI behavior — extraction/parity is preserved elsewhere in the epic.
