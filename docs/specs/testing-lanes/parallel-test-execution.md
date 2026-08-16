# docs/specs/testing-lanes/parallel-test-execution.md

---

# Parallel Test Execution — Investigation and Plan

Status: Proposed (investigation complete, nothing implemented)
Date: 2026-08-15
Baseline data: CI run 31913345473 (green, ~20 min wall clock, PR branch
`claude/secret-link-show-more-flaky-8289r8`)

## Purpose

With per-worktree datastore isolation in place (see
[testing-lanes.md](testing-lanes.md)), the next reduction in test turnaround
is running more of the suite concurrently — lanes locally, jobs in CI — and
eliminating work CI runs more than once. This document records where the time
actually goes, the defects and gating choices that inflate it, and a
prioritized plan. Any reduction is paid back on every development iteration.

## Where the time goes (measured)

Job durations from the baseline run:

| Job | Duration | Critical path? |
| --- | --- | --- |
| T3 Smoke Test | 580s | yes — longest job; starts only after both T2 jobs |
| T2 Ruby Unit | 324s | yes — gates all of T3 |
| T2 TypeScript Unit | 306s | yes — gates smoke |
| T3 Full matrix (6 rows) | 66–279s | no — already parallel |
| T3 Simple / Disabled | 260s / 192s | no — parallel |
| T4 Container Validation | 187s | yes — waits for all of T3 |
| T1 Ruby Lint | 90s | yes — gates ruby-unit |
| T1 Build Assets | 47s | no |

Per-job setup (checkout ~5s, `compose up` ~18s, ruby/node/python setup
~25s) totals ~50s per job. The time is inside the lanes, not the plumbing —
shaving job setup is not the lever.

Observed critical path:
`changes (11s) → ruby-lint (90s) → ruby-unit (324s) → smoke/T3 (580s/280s) → T4 (187s) → T5`.

## Finding 1 — the CI smoke job is almost pure duplication

The 580s smoke job (`tests/lanes/smoke`, `pnpm test:smoke`) decomposes as:

- `test:database:clean:dangerously` (~19s)
- `rake smoke:ruby` = `smoke:rspec` + `smoke:tryouts` (~290s)
- `pnpm test` = the **entire vitest suite** (~228s)

Matched against the other jobs in the same run by example counts in the logs:

| Smoke component | Also run by | Evidence |
| --- | --- | --- |
| `spec:unit` (4238 ex.) | ruby-unit (`spec:fast`) | same suite, 4150 ex. same run |
| `spec:cli` (430 ex.) | ruby-unit | identical count |
| `spec:apps:{api_v1,api_v2,api_organizations,web_billing}` | ruby-unit (`spec:apps:all` ⊂ `spec:fast`) | identical counts (314/337/145/1565) |
| `spec:integration:simple` (1276 ex.) | ruby-integration-simple job | entire job duplicated |
| `try:unit` | ruby-unit lane | identical invocation |
| `pnpm test` (385 vitest files, 228s) | typescript-unit — which runs it **with coverage** | identical suite |

`lib/tasks/spec.rake`'s own comments frame `smoke:*` as a fast local
pre-check ("complete in under 2 minutes"). In CI, where every constituent job
runs anyway, the smoke job re-verifies nothing.

**Decision: remove the smoke-test job from `ci.yml`.** The lane stays for
local use. If a CI boot-smoke is wanted, it should be an actual smoke — app
boots, serves `/`, one request per API surface — which T4's container test
already half-covers. Saving: the longest job in the workflow (580s), at zero
coverage cost, with *less* total compute.

## Finding 2 — tier gating serializes ~7 minutes

Two gates in `ci.yml` are policy choices, not data dependencies:

1. **T3 integration jobs `needs: ruby-unit` (success).** T3 consumes nothing
   ruby-unit produces. Regating T3 on `ruby-lint` + `build-assets` runs T2
   and T3 concurrently, saving ~5 min wall on green runs. Cost: wasted T3
   compute when unit fails — rare on final pushes, and
   `cancel-in-progress: true` already bounds waste from rapid re-pushes.
2. **T4 container validation `needs:` all of T3.** The container build
   consumes only the build-assets artifact; it validates boot, not
   integration results. Gating it on `build-assets` takes it off the tail.

Combined with Finding 1, projected wall clock drops from ~20 min to roughly
**9–11 min** with no additional runners.

## Finding 3 — `spec:fast` pays ~60–70s of process-boot overhead

`spec:fast` (`lib/tasks/spec.rake`) fans out to ~14 separate rspec
processes (`spec:unit`, `spec:cli`, one per `apps/*/*/spec`). The unit-lane
log shows suites finishing in 0.3–0.5s after 2.3–4s of file load, with ~5s
between processes (rake + bundler + app boot). All 14 run in an identical
environment with the same exclusion tags (`~integration`,
`~postgres_database`), so they can be **one rspec invocation** with multiple
patterns. Saves ~1 min in ruby-unit and again anywhere the pattern repeats
(`smoke:rspec`, local `rake spec`).

Do this before reaching for `parallel_tests`: consolidation is most of the
win for a fraction of the risk. If in-job parallelism is wanted later, the
isolation mechanism already generalizes — worker N takes a
`LANES_DATASTORE_DB` offset — but it needs per-worker RSpec state review
(shared fixtures, `pnpm clean:db` flushes) and is not part of this plan.

## Finding 4 — local lanes cannot yet run concurrently in one checkout

Per-worktree isolation keys the Valkey DB index (and the
`onetime_auth_test_w<index>` PG database) on `REPO_ROOT` alone. Two lanes in
the **same** checkout therefore share a datastore, so `run unit` and
`run simple` in parallel contaminate each other — the same failure class the
worktree isolation eliminated, one level down.

**Extension: salt the derivation with the lane.** Derive the index from
`${REPO_ROOT}:${LANE}` and include the lane in the `_lanes:owner` marker
value. The 65535-index space absorbs the extra keys (collision odds stay
low; the existing owner-marker preflight still detects and fails loudly).
Overlays do not need their own salt: a lane and its overlayed variant never
run concurrently under the wrapper (below), and both address the same lane
datastore by design.

Two blockers must be handled by an orchestrating wrapper, not by the lanes:

1. **Generated-file races.** Every lane's `tasks` begins with
   `pnpm run locales:sync` (and some `schemas:json:generate`), writing into
   the shared worktree. Concurrent lanes race on those files (partial-read
   hazard). The wrapper generates once up front, then runs lanes with
   generation skipped — a `LANES_SKIP_CODEGEN` guard in the tasks files that
   only the wrapper sets.
2. **RabbitMQ has no isolation at all.** One shared vhost serves every lane
   and every worktree. If integration tests consume from shared queue names,
   parallel lanes can eat each other's messages. This must be answered
   before enabling parallel `simple` + `full` runs; the matching fix is a
   per-lane vhost (`/w<index>`), provisioned the same way the PG database
   is.

Deliverable: `tests/lanes/run-all [--parallel]` running
`unit simple disabled full-sqlite` (and optionally the PG lanes) with
prefixed, streamed output and a per-lane pass/fail summary. Bounded by the
slowest lane (~4 min) instead of the sum (~15 min).

## Finding 5 — vitest is bounded by environment setup, not test time

Vitest already parallelizes across files. Its own report for the 385-file
run: `tests 74s` vs `setup 128s, environment 207s, import 212s` — per-file
DOM environment (happy-dom/jsdom) setup outweighs test execution 3:1. The
lever is isolation tuning, not more workers: move non-DOM suites to
`environment: 'node'`, evaluate `pool` settings, and consider grouping DOM
suites. Opportunistic; measure before and after.

## Plan (priority order)

| # | Change | Scope | Est. saving | Risk |
| --- | --- | --- | --- | --- |
| 1 | Remove CI smoke job (keep lane for local use) | `ci.yml` | −580s job; shortens critical path | none — 100% duplicated coverage |
| 2 | Regate T3 on lint+build-assets; T4 on build-assets | `ci.yml` | ~−5 min wall | wasted compute on red-unit runs |
| 3 | Consolidate `spec:fast` into one rspec process | `lib/tasks/spec.rake` | ~−1 min per run site | ordering-dependent specs surface (fix them) |
| 4 | Lane-salted `LANES_DATASTORE_DB` + `run-all` wrapper + codegen guard | `tests/lanes/run`, tasks files | local: sum → max of lanes | RabbitMQ question must be answered first |
| 5 | Vitest environment tuning | `vitest.config.ts`, suites | TBD (bounded by 128s+207s overhead) | per-suite environment mismatches |

Items 1–3 are small, independent edits and can ship separately. Item 4 is
the only change touching the lane runner's isolation contract and should
update [testing-lanes.md](testing-lanes.md) and `tests/lanes/README.md` when
it lands.

## Invariants preserved

- The lane remains the supported contract; the wrapper composes lanes, it
  does not bypass `tests/lanes/run`.
- CI keeps index 0 / unsuffixed database names (the `CI` branch in the
  runner is untouched by the lane-salting change).
- The 21xx port boundary and the hermetic scrub are unchanged by every item
  above.
- Coverage is never reduced: item 1 removes only re-execution of suites that
  ran in the same workflow; items 2–5 change *when* and *how*, never *what*.
