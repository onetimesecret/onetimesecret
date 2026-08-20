# docs/specs/testing-lanes/design/00-parallel-test-execution-3-verification.md

---

# Parallel Test Execution — Verification Record

Status: Evidence log for
[00-parallel-test-execution-2.md](00-parallel-test-execution-2.md)
Date: 2026-08-15
Scope: the verification gates revision 2 required before any code change, plus
the measurements taken while implementing items 1–5.

Revision 2 replaced revision 1's absolute claims with gates. This document
records what was actually measured, including the one gate premise that
turned out to be false. Where a gate passed, the evidence is here so a future
reader does not have to re-derive it; where it failed, the correction is
here so the claim is not repeated.

## Item 1 gate — CI smoke duplication

Revision 2 required three checks before deleting the `smoke-test` job.

### Gate 1.1 — executed example IDs, not aggregate counts: PASSED

The 4238 vs 4150 discrepancy is **not** a selection or environment
difference. It is a checkout-ref difference:

- `ruby-unit` (ci.yml:385-388) and `typescript-unit` (ci.yml:475-478) are the
  only jobs that override checkout with
  `ref: ${{ github.event.pull_request.head.sha || github.sha }}`. The comment
  at ci.yml:383-384 gives the reason: coverage line numbers must map to the
  diff for GitHub Code Quality.
- Every other job, `smoke-test` included, uses the `*checkout-step` anchor
  (ci.yml:93-95), which on a `pull_request` event checks out
  `refs/pull/N/merge`.

In baseline run 31913345473 (event: `pull_request`), `ruby-unit` tested PR
head `8512922ad` while `smoke-test` tested the merge commit `3e59b0e`
(`8512922ad` merged into base `8ec5647ac`). The base contributed five
`spec/unit` files that the PR head did not carry, totalling exactly 88
examples:

| File | Examples |
| --- | --- |
| `spec/unit/onetime/application/middleware_manifest_spec.rb` | 29 |
| `spec/unit/onetime/application/middleware_profile_spec.rb` | 20 |
| `spec/unit/onetime/application/registry_spec.rb` | 3 |
| `spec/unit/onetime/middleware/http_origin_options_spec.rb` | 11 |
| `spec/unit/onetime/middleware/registry_spec.rb` | 25 |
| **Total** | **88** |

4238 − 88 = 4150. Reproduced locally by dry-run; `COVERAGE=true` was
refuted as a contributing cause (4238 with and without it).

Corollary worth keeping: **comparing these two jobs by example count is
meaningless unless the same ref is compared.** The discrepancy recurs on
every PR whose base advances.

### Gate 1.2 — vitest selection identity: PASSED

`pnpm test` (smoke) and `pnpm test:base run --coverage` (typescript-unit)
select the same 385 files, proven with `vitest list --filesOnly` with and
without `--coverage`.

### Gate 1.3 — "both jobs ran the same commit": FAILED, and that is fine

This premise was false (see 1.1). It does not change the decision, because
every smoke component still maps 1:1 onto another job in the same workflow at
command-line level:

| Smoke component | Also run by | Basis |
| --- | --- | --- |
| `spec:unit`, `spec:cli` | ruby-unit (`spec:fast`, lib/tasks/spec.rake:313) | same task |
| four app suites (spec.rake:463) | ruby-unit (`spec:apps:all`, 11 suites) | strict subset |
| `spec:integration:simple` | ruby-integration-simple | byte-identical rspec line, 1276/0/2 both |
| `try:unit` | unit lane | identical tryouts line, 358/358 both |
| `pnpm test` | typescript-unit (`--coverage`) | identical 385-file selection |

**No example or file is unique to smoke.**

### What the removal actually costs

One thing genuinely disappears, and it is not "nothing": smoke was the only
job running the unit/CLI/app/tryouts/vitest suites against the **merge
commit**. After removal those suites run only against the PR head on
`pull_request` events.

This is accepted deliberately rather than papered over:

- T3 integration and T4 container validation still run on the merge ref, so
  boot-level and integration-level merge conflicts are still caught pre-merge.
- The push-triggered run on the target branch covers the merged tree.
- The obvious "fix" — dropping the explicit `ref:` from ruby-unit and
  typescript-unit — is rejected: that ref exists so coverage lines map to the
  diff (ci.yml:383-384).

If semantic merge conflicts at unit level ever bite, the right answer is a
cheap merge-ref guard job, not restoring a 580s duplicate.

### Adjacent defects found while verifying

Both are repaired in this branch rather than left as folklore:

1. **`aggregate-test-results` reports nothing.** RSpec results JSONs are
   written to `tmp/` by `.github/actions/run-test-lane` but never uploaded,
   so the download `pattern: '*-results'` only ever matched
   `rubocop-results`; the published `unified-report.json` for run
   31913345473 reads `total_examples: 0, file_count: 1`. The plan's own
   measurement protocol cannot use this job until it is fixed.
2. **`check-ci-metrics` tier-3 selectors are stale.** They still name
   "Full Mode - SQLite" / "Full Mode - PostgreSQL", which the current matrix
   (ci.yml:601) no longer produces, so tier-3 numbers reported on PRs today
   are wrong.

## Item 3 gate — `spec:fast` selection equivalence

`spec:fast` is **13** rspec child processes (not ~14): `spec:unit`,
`spec:cli`, and one per `apps/*/*/spec` (11 trees). Enumerated selection:
**398 files, 9486 examples**, no overlap between suites.

### Equivalence: two invocations reproduce the selection exactly

```
bundle exec rspec --pattern 'spec/unit/**/*_spec.rb,spec/cli/**/*_spec.rb'
bundle exec rspec --pattern 'apps/*/*/spec/**/*_spec.rb' \
  --exclude-pattern 'apps/*/*/spec/integration/**/*_spec.rb' \
  --tag '~postgres_database' --tag '~integration'
```

Verified against the legacy 13-invocation enumeration: missing 0, extra 0.

### Why two invocations and not one

A single invocation *can* reproduce the selection (three spellings verified
identical), but it cannot preserve *behaviour*:
`apps/web/billing/spec/support/billing_spec_helper.rb` registers hooks on the
generic `type: :cli` / `:controller` / `:billing` / `:integration` keys, and
`spec/cli/**` is `type: :cli`. A single merged process would wrap all 430 CLI
examples in VCR cassettes, stub `OT.billing_config`, and install
`allow_any_instance_of(Object).to receive(:sleep)`. Keeping the
no-exclusion trees in their own process removes that class of hazard
entirely.

### The pattern trap, recorded so it is not rediscovered

Never mix a `spec/…`-prefixed include pattern with an `apps/…`-prefixed
exclude pattern in one invocation. `Configuration#gather_directories` applies
include and exclude globs per checked path, and `file_glob_from` returns a
pattern verbatim only when it prefix-matches the checked path. The default
checked path is `spec`, which prefix-matches the include but not the exclude
— so the exclude silently matches nothing and **807 extra examples from 52
integration spec files** join the run.

### Landmine: exclusion tags are inert today

On rspec-core 4.0.0.beta1, `MetadataFilter.apply?` uses `filters.all?` and
`ExclusionRules` is a bare alias of `FilterRules` (the rspec-3
`any_apply?` override is gone), so exclusion filters are **ANDed**. Combined
with `spec/support/postgres_mode_suite_database.rb:378`, which always
contributes a second exclusion rule when PostgreSQL is unavailable, the app
suites' `--tag ~postgres_database --tag ~integration` currently excludes
**nothing**: roughly 500 `:integration`-tagged billing examples run inside
`spec:fast` right now.

Decision: **keep the flags verbatim.** "Fixing" them would remove ~500
examples from the fast lane — a coverage reduction, which this plan forbids.
The flags are commented in place, and the lane-membership question is a
follow-up (below), deliberately not bundled with the consolidation.

### Pre-existing selection drift

Two spec files are claimed by no lane at all — real drift introduced with
#3810:

- `spec/lib/onetime/jobs/workers/favicon_fetch_worker_spec.rb`
- `spec/lib/onetime/jobs/workers/session_revocation_sweep_worker_spec.rb`

They are placed into the fast lane as part of this work, and the new
`rake spec:verify_selection` guard fails loudly if any spec file is ever
claimed by zero lanes or by more than one.

## Item 4c gate — RabbitMQ isolation

Confirmed, and broader than revision 2 stated: **every lane in every worktree
connects to the single default vhost `/`** at `127.0.0.1:2156`
(`tests/lanes/base.env:18`). The lane runner rewrites the Valkey URL and the
four `AUTH_DATABASE_URL`s for per-worktree isolation but leaves
`RABBITMQ_URL` untouched, and RabbitMQ appears in no cleanup path. The
already-shipped per-worktree datastore isolation was therefore silently
incomplete.

Blast radius is small but unfixable at the spec level: two examples in
`spec/integration/all/jobs/rabbitmq_publishing_spec.rb` declare, publish to
and consume from the literal production names `email.message.send` /
`dlq.email.message` / `dlx.email.message`, and they cannot be salted because
`lib/onetime/jobs/publisher.rb:178,222` hardcode the queue name. A per-run
vhost is the only isolation available. Those examples ship in 5 of the 11
lanes.

Failure mode is quiet, which is why this ranks as a defect rather than a
nice-to-have: if a concurrent run deletes `email.message.send` while another
run's message is in flight, the victim blocks in `Timeout.timeout(5)` and
reports a timeout — indistinguishable from flakiness.

## Item 5 gate — vitest measurement before tuning

One config, 385 files, all `jsdom`, `pool: 'forks'`, five setup files.

Measured on a bounded, faithful probe rather than the full suite: the 73
files under `src/tests/{schemas,contracts,i18n,scripts,types,build}` run
green under `environment: 'node'` with `setupFiles: []`, producing identical
results (2018 passed | 34 skipped | 6 todo both ways).

| Metric (73-file slice) | jsdom | node |
| --- | --- | --- |
| Wall | 15.97s | 6.90s |
| Environment | 58.62s | 0.005s |
| Setup | 34.98s | 0s |
| Import | 52.70s | 53.66s |

Two honest caveats, stated here because the plan's framing understates them:

- **Import time does not improve.** Roughly a third of the reported cost is
  transform+import, which the environment switch does not touch. Only
  `isolate: false` moved it (53.66s → 28.27s on the same slice) — held back
  as a follow-up because it shares the module registry across files and needs
  repeated shuffled-seed runs first.
- **The CI wall-clock saving is unknown**, because CI worker count is not in
  the workflow. The defensible claim is cumulative worker time removed:
  63.5s at the plan's reported per-file CI rates, 93.6s at locally measured
  rates.

`environmentMatchGlobs` does not exist in vitest 4.1.0; the migration is
`test.projects`. Project entries do not inherit the root `resolve.alias`
block, and `globalSetup` must stay at the root so two projects cannot race
`locales:sync` against `generated/locales/` in a shared worktree forest.

## Measurement protocol status

Wall-clock and runner-minute medians over 5–10 green CI runs, as revision 2
requires, cannot be produced in the same change that makes the edits. The
before/after CI numbers in this branch are single-run projections. The
`aggregate-test-results` repair above is the prerequisite for collecting the
real series; the numbers should be filled in after the branch has accumulated
green runs.

## Follow-ups deliberately not bundled

| # | Item | Why separate |
| --- | --- | --- |
| 1 | rspec-core exclusion-filter AND semantics; decide whether ~500 `:integration`-tagged billing examples belong in the fast lane | Changes coverage; needs its own decision and possibly an upstream issue |
| 2 | `isolate: false` for the vitest node project | Bigger win than the environment split, but needs repeated shuffled-seed validation |
| 3 | Merge-ref guard job, if unit-level semantic merge conflicts appear | Speculative until observed |
| 4 | Per-invocation run IDs for true same-lane concurrency | Nothing in the local workflow needs it; costs a PG database and vhost per invocation |
