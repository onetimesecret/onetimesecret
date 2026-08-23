docs/specs/testing-lanes/00-parallel-test-execution-1-assessment.md
---
Assessment

The plan is directionally correct and prioritizes the highest-value changes. Items 1–2 should materially reduce CI wall time without new infrastructure. I would tighten several claims and adjust item 4 before implementation.

## Material feedback

### 1. Smoke duplication is likely, but “zero coverage cost” is not yet proven

The evidence table says:

- smoke `spec:unit`: 4238 examples
- ruby-unit `spec:fast`: 4150 examples

Those counts do not establish identical execution. Smoke and `spec:fast` invoke the same `spec:unit` task, so the discrepancy should be explained before stating “100% duplication” or “zero coverage cost.”

Compare exact executed example IDs or RSpec JSON results—not aggregate counts. Also verify:

- smoke and unit used the same commit and environment;
- no smoke-only ordering behavior exists;
- `pnpm test` and `pnpm test:base run --coverage` select exactly the same Vitest projects/files.

I still expect removal to be correct, but the plan currently overstates the proof. Change “none” risk to “low,” pending exact suite-set comparison.

### 2. T3 regating must preserve prerequisites and path-filter semantics

T3 currently needs only `changes` and `ruby-unit`. The proposed dependency should be explicit:

```yaml
needs: [changes, ruby-lint, build-assets]
```

Its condition should accept skipped prerequisites where appropriate, as `ruby-unit` already does:

```yaml
(needs.ruby-lint.result == 'success' || needs.ruby-lint.result == 'skipped') &&
(needs.build-assets.result == 'success' || needs.build-assets.result == 'skipped') &&
!contains(needs.*.result, 'cancelled')
```

Do not use only a broad `!contains(..., 'failure')`: an unexpectedly skipped lint/build job could otherwise allow integration tests to run without expressing why that is valid.

### 3. T4 does not strictly depend on `build-assets`

`check-oci-image` downloads the artifact but intentionally builds assets inline if it is absent. Therefore its actual dependency is:

- `changes`, for the `oci`/`frontend` decision;
- optionally `build-assets`, to avoid duplicate frontend compilation.

Regating it on `[changes, build-assets]` is reasonable, but the condition must allow `build-assets == skipped` for OCI-only changes. The plan should describe this as an optimization dependency rather than a correctness dependency.

### 4. Consolidating `spec:fast` is not mechanically “same exclusions”

Current behavior differs by suite:

- `spec:unit`: no tag exclusions;
- `spec:cli`: no tag exclusions;
- app suites: `~postgres_database` and `~integration`, plus directory-level integration exclusion.

A single invocation with global exclusion tags would change unit/CLI selection if those trees ever contain matching metadata. A global `--exclude-pattern` also needs to preserve all app integration exclusions without excluding unrelated root specs.

Before changing it, generate and compare the exact file list selected by the old and new forms. Add a test or helper that asserts this equivalence so future app directories remain automatically included.

The state-leakage risk is correctly identified. Also inspect global mutations in `before(:all)` and helper loading order; `spec:fast` currently gives each suite a fresh RSpec world, not merely a fresh application process.

### 5. Lane-only salting does not provide invocation isolation

`${REPO_ROOT}:${LANE}` isolates different lanes, but two concurrent runs of the same lane still share Valkey and PostgreSQL. Examples:

- a developer launches `run unit` twice;
- an editor task overlaps with `run-all`;
- two `run-all` processes overlap.

That may be an acceptable documented limitation, but the plan should not describe local lanes as generally concurrent-safe.

A stronger model is for `run-all` to generate a run ID and assign explicit database indexes to each child. Because the runner scrub removes arbitrary inherited variables, this needs a deliberate plumbing mechanism—not merely exporting `LANES_DATASTORE_DB`. Alternatively, use a wrapper-owned overlay or a narrowly scoped retained variable.

### 6. Overlay concurrency should not be encoded as a datastore invariant

The plan says overlays need no salt because the initial wrapper will not run variants concurrently. That couples datastore isolation to one wrapper’s scheduling policy. Future callers could run billing-on and billing-off variants concurrently and collide.

Either:

- include normalized overlays in the isolation key; or
- explicitly reject concurrent variants and document that same-lane executions are unsupported.

Including overlays is safer, especially if local parity with the six-row CI matrix becomes desirable.

### 7. RabbitMQ isolation should cover worktrees and lanes

The discovered problem is broader than `simple + full`: current RabbitMQ isolation is absent across both lanes and worktrees. The runner already advertises concurrent-worktree datastore isolation, but RabbitMQ integration specs under `spec/integration/all` may violate that assumption.

Use a per-invocation or per-lane vhost rather than only `/w<index>` if same-lane overlap is supported. Verify that:

- the configured user can create/access the vhost;
- queue, exchange, and DLQ names cannot cross vhosts;
- cleanup does not delete another active run’s vhost;
- provisioning is atomic under simultaneous startup.

This investigation should precede the lane-salting change, as planned.

### 8. `LANES_SKIP_CODEGEN` conflicts with the runner’s hermetic boundary as described

The wrapper cannot simply export `LANES_SKIP_CODEGEN`; `tests/lanes/run` scrubs it because it is not retained. Adding it to the keep-list would weaken the stated rule that caller application behavior cannot leak into lanes.

Prefer a runner argument such as:

```text
tests/lanes/run unit --skip-codegen
```

The runner can then set the variable internally after the scrub. Better still, represent generation as an explicit runner phase rather than making every tasks file interpret inherited control state.

Also protect against a direct lane accidentally using stale generated files. The default direct invocation must continue generating prerequisites.

## Sequencing recommendation

1. Remove CI smoke after exact suite-set verification.
2. Regate T3 and T4 in a separate PR; collect 5–10 green-run measurements.
3. Consolidate `spec:fast`; validate selected file/example equivalence and run the lane repeatedly to expose ordering leaks.
4. Design a complete local resource namespace:
   - Valkey DB;
   - PostgreSQL database;
   - RabbitMQ vhost;
   - generated files;
   - result/coverage files, if produced concurrently.
5. Implement `run-all`.
6. Tune Vitest only after capturing per-project/per-environment timing.

## Measurement improvements

Track both:

- **wall-clock latency**: changes start → required checks complete;
- **total runner-minutes**: to quantify the cost of speculative parallelism.

Use medians and p90 over several runs. A single baseline can be distorted by cache state, runner allocation, coverage upload, or network variance.

## Bottom line

Items 1–3 are feasible and worthwhile. Item 2 is the clearest low-risk wall-time improvement. Item 4 needs an invocation-level isolation decision; lane salting alone is narrower than the wrapper’s implied concurrency guarantee. The main correction to the document is to replace absolute claims—“100% duplicated,” “zero coverage cost,” and generally concurrent-safe lanes—with measured, explicitly bounded guarantees.
