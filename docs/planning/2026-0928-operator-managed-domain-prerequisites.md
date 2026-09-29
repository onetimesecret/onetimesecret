# Operator-managed domains: prerequisite verification

Verification date: 2026-09-28. Local baseline: `1dd1fba9f2`.

Scope: check the narrow #4489 correction and merged stack, then track separate specification and cutover-runbook work. No runtime changes, merges, or new approval claims are part of this work.

Evidence boundary: PR checks and test reports below are historical evidence at their named commits. They are not current-branch or local test results. Current/local attempts are recorded separately and reached no runtime assertions.

## Step 1 — correction present

Correction `b3adf11750` is an ancestor of #4489's merge, each dependent merge, and the local baseline.

| Evidence ID | Observation and disposition |
| --- | --- |
| V1 | `VerifyDomain#persist_changes` routes passthrough to `record_skipped`, without recording a TXT confirmation or clearing `verified_by_override`. Verified by inspection; no further correction needed. |
| V2 | `ConfirmationWindow#record_skipped` clears the unconfirmed clock explicitly. It preserves confirmation for a continuously verified lineage and clears older proof on policy re-promotion after demotion. Verified by inspection. |
| V3 | `try/unit/operations/verify_domain/confirmation_window_try.rb` covers real passthrough, metadata, overrides, clocks, and lineage handling. `spec/integration/all/domains/caddy_on_demand_certificate_gate_spec.rb` covers cutover after refresh. Coverage exists; local execution remains blocked (V6). |
| V4 | Passthrough still returns successful authorization and assumed DNS/TLS health; the metadata correction does not change its access behavior. Verified by inspection. |
| V5 | Stored `verified`/`resolving` still satisfy the ACME `ready?` gate before revalidation after strategy change. This is the known cutover gap, tracked by the separate proposal, not fixed by #4489. |
| V6 | Local focused test reruns could not reach assertions because the Docker/Podman backend was unavailable. Validation remains limited to inspection and existing CI evidence. |

Primary implementation evidence:

- [`VerifyDomain#persist_changes`](../../lib/onetime/operations/verify_domain.rb)
- [`ConfirmationWindow`](../../lib/onetime/operations/verify_domain/confirmation_window.rb)
- [`PassthroughStrategy`](../../lib/onetime/domain_validation/passthrough_strategy.rb)
- [`CustomDomain#ready?`](../../lib/onetime/models/custom_domain.rb)
- [ACME gate](../../apps/internal/acme/application.rb)

The [#4489 disposition](https://github.com/onetimesecret/onetimesecret/pull/4489#discussion_r4116642102) records 21 passing focused cases. That historical report is not a current/local test result.

## Step 2 — historical merges and combined CI complete; review sign-off qualified

Git ancestry confirms every adjacent merge below, through the local baseline. GitHub records the following merge times and PR-head check results:

| PR | Merged (UTC) | Merge commit | Successful / skipped / failed checks |
| --- | --- | --- | --- |
| [#4485](https://github.com/onetimesecret/onetimesecret/pull/4485) | Sep 27 06:01:59 | `a3d6ae4eec` | 57 / 2 / 0 |
| [#4487](https://github.com/onetimesecret/onetimesecret/pull/4487) | Sep 27 06:24:13 | `b8b73c646a` | 47 / 5 / 1 |
| [#4488](https://github.com/onetimesecret/onetimesecret/pull/4488) | Sep 27 06:27:54 | `88f90e2473` | 53 / 3 / 2 |
| [#4489](https://github.com/onetimesecret/onetimesecret/pull/4489) | Sep 27 21:45:47 | `464188f7b6` | 52 / 3 / 0 |
| [#4490](https://github.com/onetimesecret/onetimesecret/pull/4490) | Sep 28 02:50:42 | `f0874083b2` | 51 / 2 / 0 |
| [#4491](https://github.com/onetimesecret/onetimesecret/pull/4491) | Sep 28 06:50:07 | `c8ae2b33d7` | 45 / 4 / 0 |
| [#4486](https://github.com/onetimesecret/onetimesecret/pull/4486) | Sep 28 15:05:26 | `68bc6c431e` | 52 / 2 / 0 |

| Evidence ID | Observation and disposition |
| --- | --- |
| S1 | Final review completion is not fully established. #4487 has a [no-defects review comment](https://github.com/onetimesecret/onetimesecret/pull/4487#issuecomment-5738749046). #4488's [mixed-family finding](https://github.com/onetimesecret/onetimesecret/pull/4488#issuecomment-5738750275) has correction `1a505284c8` in its merge, but no explicit closing review/disposition comment was found on that PR. #4486's [no-new-blocker assessment](https://github.com/onetimesecret/onetimesecret/pull/4486#issuecomment-5850412409) predates final head `6733c1a1e8`; a [subsequent P1 disposition](https://github.com/onetimesecret/onetimesecret/pull/4486#issuecomment-5865523919) cites that fix. Its final green review job skipped actual review with “No trigger found, skipping remaining steps”. Retain a review-evidence qualification; do not declare blanket sign-off. |
| S2 | All 19 review threads are resolved: #4485 8, #4489 2, #4490 6, #4491 3. The other PRs have no review threads or formal review records. Thread closure is not final review approval; no new review performed here. |
| S3 | Final [combined CI run](https://github.com/onetimesecret/onetimesecret/actions/runs/36392622522) at `6733c1a1e8` passes Ruby/TypeScript unit tests and the integration matrix; Ruby 4 checks also pass. Historical Ruby failures on #4487 and Ruby/TypeScript failures on #4488 are not relabeled as passes, and their causes were not investigated here. Combined CI validation is established. |
| S4 | Ordered ancestry and propagation of `b3adf11750` through all dependent merges are verified. Merge sequencing is complete. |

## Current/local validation attempts

The `.test-mode` sentinel exists. Tests were invoked only through the lane runner, with 120-second limits:

```text
tests/lanes/run --only try/unit/operations/verify_domain/confirmation_window_try.rb
  exit 69: test services unavailable; container socket unreachable

tests/lanes/run --only spec/integration/all/domains/caddy_on_demand_certificate_gate_spec.rb
  exit 64: multiple lanes; explicit lane required

tests/lanes/run simple --only spec/integration/all/domains/caddy_on_demand_certificate_gate_spec.rb
  exit 69: test services unavailable; container socket unreachable
```

No assertions executed. The lane-selection error was corrected; the unavailable container backend remains the blocker.

## Step 3 — separate design, no implementation

Tracked in [#4607](https://github.com/onetimesecret/onetimesecret/issues/4607).

The [operator-managed specification](../specs/domain-validation/operator-managed-domains.md) defines proposed authorization, independent health, aliases, and cutover semantics. The [operator-managed cutover runbook](../specs/domain-validation/operator-managed-cutover-runbook.md) defines the future operational barrier, evidence classification, target dry run, activation, first-request checks, and rollback contract. Both documents are specification-only. All V1–V6 and S1–S4 observations are dispositioned above; V5 is intentionally deferred to that tracked change, and S1/V6 remain explicit verification limitations.

**Deployment clarification:** The maintainer reports that no one uses passthrough, including the project's own deployments, because it has not worked properly until now. The proposal does not require migration of existing passthrough users or a staged passthrough rollout. V5 describes a code-path risk for future strategy changes, not evidence of an affected production deployment. The aliases remain part of the requested naming contract.

**Operational boundary for future use:** #4489 corrects false confirmation metadata, not the trust carried by stored `verified` flags. A configuration-only switch is not ownership revalidation. Until a cutover barrier exists, a deployment needs an explicit procedure that isolates affected serving/certificate authorization, revalidates every assignment under the target strategy, resolves uncertain legacy evidence or retains a deliberate override, and restores access only after inspecting results. `bin/ots domains verify --all` is the existing bulk check, not by itself an atomic cutover barrier or a guarantee that indeterminate legacy flags are withdrawn under every strategy. The specification-only [target-specific runbook](../specs/domain-validation/operator-managed-cutover-runbook.md) is an implementation prerequisite; no production state was changed here.
