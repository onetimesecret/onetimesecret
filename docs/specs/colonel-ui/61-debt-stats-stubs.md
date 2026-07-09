---
labels: admin-v2, backend, tech debt
depends: none
epic: "#3653"
---

# Admin rebuild: implement real global stats or drop the stubbed tiles

## Context

Part of the Colonel Admin Rebuild epic (backend debt, §7 — fix while in there). `GetColonelStats` returns 0 for `secrets_created`, `secrets_shared`, and `emails_sent` (marked TODO in the file). We must not build dashboard tiles over stubbed zeros — either implement real global counters first, or drop the tiles until the numbers are real.

## Scope

- Confirm the stubbed fields in the stats handler: `secrets_created`, `secrets_shared`, `emails_sent` all return 0.
- Either (a) implement global counters that back these fields with real values, or (b) omit the corresponding dashboard tiles until real counters exist.
- Do not ship dashboard tiles displaying stubbed zeros as if they were data.

## Grounding — files & pointers

- Stats handler: `GetColonelStats` in `apps/api/colonel/logic/colonel/` (the stats handler; TODO markers in the file).
- Colonel API surface: `/api/colonel`, routes `apps/api/colonel/routes.txt`.
- Global-counter approach pairs naturally with the per-customer counter work in issue 60 (shared chokepoints: secret creation, email send).

## Acceptance criteria

- [ ] The three stubbed fields are enumerated and their current zero-return confirmed.
- [ ] Either real global counters back `secrets_created`, `secrets_shared`, `emails_sent`, OR the tiles that would display them are not rendered.
- [ ] No dashboard tile presents a stubbed 0 as a real metric.
- [ ] If counters are implemented, they are maintained at the relevant creation/send chokepoints (align with issue 60's `Receipt.spawn_pair` pattern for secrets).

## Notes / risks

- Prefer dropping tiles over shipping fake data — an empty dashboard beats a lying one.
- If implementing counters, coordinate with issue 60 so secret-creation instrumentation is written once, not twice.
- `emails_sent` needs its own chokepoint (the mail send path), separate from secret creation.
