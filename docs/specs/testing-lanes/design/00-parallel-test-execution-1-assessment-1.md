00-parallel-test-execution-1-assessment-1.md
---

It captures the full investigation with the measured baseline (run 31913345473):

- Finding 1 — the 580s CI smoke job is ~100% duplication (suite-by-suite evidence table matching example counts against ruby-unit, ruby-integration-simple, and typescript-unit); decision is to remove it from ci.yml, keep the lane locally.
- Finding 2 — T3→ruby-unit and T4→all-of-T3 gates are policy, not data dependencies; regating saves ~5 min wall.
- Finding 3 — spec:fast's ~14 rspec processes waste ~60–70s of boot; consolidate to one invocation before considering parallel_tests.
- Finding 4 — local parallel lanes need lane-salted LANES_DATASTORE_DB, a run-all wrapper with one-shot codegen (LANES_SKIP_CODEGEN), and an answer to the shared-RabbitMQ-vhost question first.
- Finding 5 — vitest is environment-setup-bound (3:1 overhead vs test time); tuning, not more workers.

> /btw feasible?

Yes — items 1–3 are straightforwardly feasible; 4–5 are feasible with caveats I already flagged.

1. Remove/reduce the CI smoke job — trivially feasible. It's deleting a job block from ci.yml (or trimming smoke:all). The duplication evidence is solid: I matched example counts (4238/430/1565/etc.) between the smoke log and the ruby-unit/simple-integration logs, so coverage loss is zero. Only caveat: aggregate-test-results and ci-metrics list smoke in needs: and would need that reference removed too.
2. Regate T3 on lint+build-assets, T4 on build-assets — feasible, pure needs:/if: edits. The one real cost is compute waste when ruby-unit is red (T3 jobs run anyway and fail on the same defect). That's a policy trade, not a technical blocker. Worth keeping !contains(needs.*.result, 'cancelled') logic intact so cancel-in-progress still short-circuits.
3. Consolidate spec:fast into one rspec invocation — feasible with moderate confidence. All 14 suites run in the same env with the same --tag ~integration --tag ~postgres_database exclusions, so mechanically it's one invocation with multiple patterns. The risk is latent inter-suite state leakage that separate processes were masking (class-level memoization, Familia connection state, RSpec config drift between spec_helper variants across apps). Expect a small cleanup tail the first time it runs combined — that's why I'd do it as its own PR with the full lane matrix as the check.
4. Lane-salted LANES_DATASTORE_DB + parallel run-all — feasible; the runner change itself is ~5 lines (salt the cksum input, include lane in the owner marker). The two genuine unknowns are the ones I flagged: whether integration tests consume shared RabbitMQ queue names (needs a check before enabling parallel simple+full), and the codegen write race (solvable with generate-once in the wrapper). Neither looks like a blocker, but I wouldn't ship parallel-by-default until the rabbit question is answered.
5. Vitest environment tuning — feasible but the payoff is the least certain; 207s of environment setup across 385 files won't vanish, it'll shrink incrementally per suite you move to environment: 'node'.

Net: nothing in the plan requires new infrastructure or new runners, and the two biggest wins (1 and 2) are low-risk YAML changes. The realistic failure mode isn't "can't be done" — it's item 3 surfacing hidden test-state coupling, which is bounded and fixable.
