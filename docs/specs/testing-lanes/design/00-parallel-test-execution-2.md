# docs/specs/testing-lanes/design/00-parallel-test-execution-2.md

---

# Parallel Test Execution — Execution Plan (revision 2)

Status: Proposed (supersedes
[00-parallel-test-execution-1.md](00-parallel-test-execution-1.md))
Date: 2026-08-15
Baseline data: CI run 31913345473 (green, ~20 min wall clock)
Inputs: revision 1 plus two assessments
([assessment 1](00-parallel-test-execution-1-assessment-1.md),
[assessment 2](00-parallel-test-execution-1-assessment-2.md))

## What changed from revision 1

Revision 1's findings and priorities stand. This revision incorporates the
assessment feedback:

- Absolute claims ("100% duplicated", "zero coverage cost",
  "concurrent-safe lanes") are replaced with measured, explicitly bounded
  guarantees and the verification steps that would justify them.
- Gating conditions are specified exactly (success-or-skipped per
  prerequisite, never a broad not-failure).
- The local isolation namespace is designed as a whole — Valkey, PostgreSQL,
  RabbitMQ, generated files, result files — instead of salting one datastore
  key and deferring the rest.
- `LANES_SKIP_CODEGEN` as an inherited environment variable is dropped: it
  conflicts with the hermetic scrub. Codegen control becomes a runner
  argument.
- Same-lane concurrent invocations are explicitly declared unsupported and
  detected, rather than implied safe.

## Item 1 — remove the CI smoke job (after suite-set verification)

The 580s smoke job re-runs suites that other jobs in the same workflow run
anyway. The revision-1 evidence matched aggregate example counts; that is
strong but not proof. Notably smoke `spec:unit` logged 4238 examples versus
ruby-unit's 4150 for the same task — a discrepancy that must be explained
before claiming duplication, since both invoke the same `spec:unit` task.

**Verification gate (before the ci.yml edit):**

1. Run smoke and ruby-unit components with RSpec JSON output and diff the
   executed example IDs, not counts. Explain the 4238 vs 4150 delta.
2. Confirm `pnpm test` (smoke) and `pnpm test:base run --coverage`
   (typescript-unit) select the same Vitest projects and files.
3. Confirm both jobs ran the same commit and equivalent environment, and
   that no smoke-only ordering behavior exists.

**Change:** delete the `smoke-test` job from `ci.yml` and remove its entries
from downstream `needs:` lists (`ci.yml:824` and `ci.yml:885` —
aggregate-test-results and ci-metrics). The `smoke` lane remains for local
use, and `lib/tasks/spec.rake` keeps framing `smoke:*` as the fast local
pre-check.

If a CI boot-smoke is wanted later, build an actual smoke — app boots,
serves `/`, one request per API surface — rather than re-running unit
suites; T4's container test already half-covers this.

Risk: **low** (was "none"), pending the verification gate. Saving: the
longest job in the workflow, with less total compute.

## Item 2 — regate T3 and T4 with exact conditions

Both gates are policy choices, not data dependencies. The regating must
preserve path-filter semantics: prerequisites can be legitimately `skipped`
by the `changes` filter, and the condition must say so per job rather than
accepting anything that is not a failure.

**T3 integration jobs** (currently `needs: [changes, ruby-unit]`):

```yaml
needs: [changes, ruby-lint, build-assets]
if: >-
  (needs.ruby-lint.result == 'success' || needs.ruby-lint.result == 'skipped') &&
  (needs.build-assets.result == 'success' || needs.build-assets.result == 'skipped') &&
  !contains(needs.*.result, 'cancelled')
```

Do not collapse this to `!contains(needs.*.result, 'failure')`: an
unexpectedly skipped prerequisite would then let integration run without the
workflow expressing why that is valid.

**T4 container validation:** `check-oci-image` downloads the build-assets
artifact but deliberately builds assets inline when it is absent.
`build-assets` is therefore an *optimization* dependency (avoids duplicate
frontend compilation), not a correctness dependency. Regate as
`needs: [changes, build-assets]` with `build-assets == 'skipped'` allowed so
OCI-only changes still run it.

Cost: wasted T3 compute when ruby-unit is red — rare on final pushes, and
`cancel-in-progress: true` bounds waste from rapid re-pushes. Keep the
cancelled-check intact so cancellation still short-circuits.

Projected wall clock with items 1–2: roughly **9–11 min** from ~20 min, no
additional runners. Verify with the measurement protocol below, not a single
run.

## Item 3 — consolidate `spec:fast` into one rspec invocation

~14 rspec processes each pay 2.3–4s of file load plus ~5s of rake/bundler/
boot for suites that finish in under a second. Consolidation recovers ~1 min
per run site (ruby-unit, `smoke:rspec`, local `rake spec`).

Revision 1 claimed all suites run "the same exclusion tags." They do not:

- `spec:unit` and `spec:cli`: **no** tag exclusions;
- app suites (`apps/*/*/spec`): `~postgres_database` and `~integration`
  tags plus a directory-level integration exclusion.

A single invocation with global exclusion tags would silently change
unit/CLI selection if those trees ever gain matching metadata, and a global
`--exclude-pattern` must preserve the app-level integration exclusions
without dropping unrelated root specs.

**Equivalence gate:** generate the exact file list (and executed example
IDs) selected by the old and new forms and diff them. Add a spec or helper
that asserts this equivalence so future `apps/*/*/spec` directories remain
automatically included and selection drift fails loudly.

**State-leakage expectation:** separate processes currently give each suite
a fresh RSpec world *and* a fresh application process. Consolidation removes
both. Expect a cleanup tail: class-level memoization, Familia connection
state, global mutations in `before(:all)`, helper loading order, and RSpec
config drift between per-app `spec_helper` variants. Ship as its own PR,
validated by the full lane matrix, and run the lane repeatedly (different
seeds) to expose ordering leaks before merging.

Do this before reaching for `parallel_tests`: consolidation is most of the
win for a fraction of the risk.

## Item 4 — local parallel lanes: a complete invocation namespace

Revision 1 proposed salting the datastore index with the lane name. The
assessments showed that is necessary but not sufficient. The isolation unit
is the **invocation**, and every shared resource needs an answer, not just
Valkey:

| Resource | Isolation mechanism |
| --- | --- |
| Valkey | DB index derived from `${REPO_ROOT}:${LANE}:${OVERLAYS}` |
| PostgreSQL | `onetime_auth_test_w<index>` from the same derivation |
| RabbitMQ | per-index vhost (see below) — **precondition, not follow-up** |
| Generated files | one-shot codegen phase in the wrapper (runner flag) |
| Result/coverage files | per-lane output paths when produced concurrently |

### 4a. Isolation key includes lane and normalized overlays

Derive the index from `${REPO_ROOT}:${LANE}:${sorted overlays}` and record
the full key in the `_lanes:owner` marker value. Revision 1 exempted
overlays because "the wrapper never runs variants concurrently" — that
couples a datastore invariant to one wrapper's scheduling policy. Including
overlays costs nothing (the 65535-index space absorbs the extra keys, and
the owner-marker preflight still fails loudly on collision) and keeps the
door open to local parity with the six-row CI matrix.

### 4b. Same-lane concurrency is unsupported and must be detected

Lane salting isolates *different* lanes. Two concurrent runs of the same
lane+overlay set (a developer runs `run unit` twice; an editor task overlaps
`run-all`; two `run-all` processes) still share both datastores, and the
owner marker cannot distinguish them — same key, same marker value, both
proceed.

Decision: **same-lane concurrent invocations are unsupported.** Do not
imply general concurrency safety. Add cheap detection: the runner writes a
per-invocation liveness token (e.g. `_lanes:active` with the runner PID and
a short TTL, refreshed during the run) and aborts when a live token from
another PID exists. This is best-effort collision detection, not a lock — it
turns silent contamination into a loud error, which is the same posture the
worktree owner marker takes.

The alternative — wrapper-assigned per-invocation run IDs with explicit
index assignment — buys true same-lane concurrency at the cost of
provisioning a fresh PG database and vhost per invocation. Nothing in the
local workflow needs that today; revisit only if a real use case appears.

### 4c. RabbitMQ vhost isolation (precondition)

RabbitMQ currently has **no** isolation across lanes or worktrees — the
already-shipped worktree datastore isolation is silently incomplete for any
integration spec that consumes from shared queue names. This makes vhost
isolation a fix to the existing contract, not merely an enabler for
`run-all`.

Provision a per-index vhost (`/w<key-index>`), the same lifecycle shape as
the PG database. The investigation must verify:

- which specs (notably under `spec/integration/all`) actually consume from
  shared queues, to size the blast radius;
- the configured user can create and access vhosts (or a provisioning path
  with adequate permissions exists);
- queue, exchange, and DLQ names cannot cross vhosts;
- provisioning is atomic under simultaneous startup (advisory-lock
  equivalent);
- cleanup (`pnpm clean:db` or a sibling) cannot delete another active run's
  vhost.

This lands **before** enabling any parallel lane execution.

### 4d. Codegen control is a runner phase, not inherited environment

Revision 1's `LANES_SKIP_CODEGEN` guard cannot work as described: the
hermetic scrub removes it, and adding it to the retained allowlist would
weaken the rule that caller state cannot alter lane behavior.

Instead, make generation an explicit runner phase controlled by an argument:

```text
tests/lanes/run unit --skip-codegen
```

The runner sets the internal variable after the scrub (or better, owns the
codegen step itself so tasks files stop interpreting inherited control
state). The default direct invocation **must keep generating** — a direct
lane run must never silently use stale generated files. Only the `run-all`
wrapper, which generates once up front, passes `--skip-codegen` to its
children.

### 4e. Deliverable

`tests/lanes/run-all [--parallel]` running `unit simple disabled
full-sqlite` (optionally the PG lanes) with prefixed streamed output, a
per-lane pass/fail summary, and per-lane result-file paths. Bounded by the
slowest lane (~4 min) instead of the sum (~15 min). The wrapper composes
lanes; it never bypasses `tests/lanes/run`.

## Item 5 — vitest environment tuning

Unchanged from revision 1 in substance: the 385-file run spends 74s in
tests against 128s setup + 207s environment + 212s import — per-file DOM
environment setup outweighs execution 3:1, so the lever is isolation tuning
(move non-DOM suites to `environment: 'node'`, evaluate `pool`, group DOM
suites), not more workers.

Per assessment 2: capture per-project/per-environment timing **first** and
tune against it; the 207s will shrink incrementally per migrated suite, not
vanish. Lowest priority; opportunistic.

## Sequencing

1. **Verify then remove CI smoke** (item 1 verification gate, then the
   ci.yml edit including downstream `needs:` cleanup).
2. **Regate T3/T4** in a separate PR with the exact conditions above;
   collect 5–10 green-run measurements before declaring the saving.
3. **Consolidate `spec:fast`** with the selection-equivalence gate; run the
   lane repeatedly to shake out ordering leaks.
4. **RabbitMQ vhost investigation and fix** (item 4c) — also closes the
   existing worktree-isolation gap.
5. **Isolation key extension + same-lane detection + codegen phase**
   (items 4a/4b/4d), updating [testing-lanes.md](../testing-lanes.md) and
   `tests/lanes/README.md` in the same change.
6. **`run-all` wrapper** (item 4e).
7. **Vitest tuning** (item 5), measurement-first.

Steps 1–3 are independent and can ship in any order relative to each other.
Steps 4–6 are ordered among themselves.

## Measurement protocol

A single baseline run can be distorted by cache state, runner allocation,
coverage upload, or network variance. For before/after claims:

- **Wall-clock latency**: `changes` start → required checks complete.
- **Total runner-minutes**: quantifies the cost of speculative parallelism
  (item 2 trades some of this for latency).
- Use medians and p90 over 5–10 green runs, not single samples.

## Invariants preserved

- The lane remains the supported contract; the wrapper composes lanes, it
  does not bypass `tests/lanes/run`.
- CI keeps index 0 / unsuffixed database names and its own per-job services;
  the `CI` branch in the runner is untouched by every item above.
- The 21xx port boundary and the hermetic scrub are unchanged; codegen
  control enters as a runner argument precisely so the scrub allowlist does
  not grow.
- Coverage is never reduced: item 1 removes re-execution only after
  example-ID-level verification; items 2–5 change *when* and *how*, never
  *what*.
- Direct lane invocations keep generating their prerequisites; only the
  wrapper opts children out after generating once itself.
