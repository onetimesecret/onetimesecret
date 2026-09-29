# Operator-managed domain cutover runbook

Status: Proposed; specification only, not implemented.

Tracking: [#4607](https://github.com/onetimesecret/onetimesecret/issues/4607).

Related specification: [Operator-managed domains](operator-managed-domains.md).

## Purpose

This runbook defines the operational contract for changing a deployment between operator-managed domain authorization and a TXT-enforced strategy. It is an implementation prerequisite: runtime support and cutover tooling must pass the acceptance cases in this document before an operator uses the procedure in production.

The procedure preserves three independent facts:

- **Authorization basis:** eligible TXT proof, explicit override, operator policy, or none.
- **Observed health:** DNS resolution and HTTPS observations, including unknown, `not_checked`, stale, and failed results.
- **Certificate management:** external management or the configured certificate provider.

A healthy domain is not necessarily authorized, and an authorized domain is not necessarily healthy.

## Tooling status and execution boundary

The repository has `bin/ots domains verify DOMAIN` and the bulk form `bin/ots domains verify --all`. Both support `--dry-run` and `--json`. The bulk form enumerates domains and checks them sequentially under the deployment's active strategy.

`bin/ots domains verify --all` is not an atomic cutover barrier. It does not freeze registration or transfer, evaluate an inactive target strategy, establish assignment lineage, coordinate web/worker/scheduler activation, prevent ACME decisions during the sweep, or invalidate every authorization cache. A successful sweep can therefore become stale before configuration activation.

This runbook requires future tooling or an equivalent maintenance control plane with the capabilities listed below. Capability names in this document are requirements, not proposed CLI command names:

- freeze and drain all assignment and authorization writers;
- enumerate a stable, complete assignment snapshot;
- classify authorization evidence and assignment lineage;
- evaluate the target strategy without changing active authorization;
- produce and retain a machine-readable exception report;
- activate one configuration and authorization generation atomically, or keep all affected decisions denied until every process acknowledges it;
- invalidate or fence stale authorization caches;
- prove first-request behavior before traffic is restored;
- roll back configuration without replaying old authorization fields or caches.

Until those capabilities exist and pass the acceptance matrix, the procedure is not executable in production. Direct datastore edits and configuration-only strategy changes do not satisfy it.

## Supported transitions

This runbook covers install-level strategy transitions. It does not define per-domain rollout.

| Source | Target | Support condition |
| --- | --- | --- |
| `operator_managed`, `passthrough`, or `external` | `caddy_on_demand` | Full cutover barrier required. Operator-policy authorization stops qualifying at activation. Each accepted assignment requires eligible TXT proof for its current lineage or an eligible explicit override. |
| `operator_managed`, `passthrough`, or `external` | `approximated` | Full cutover barrier required. Operator-policy authorization stops qualifying at activation. Each accepted assignment requires eligible TXT proof for its current lineage or an eligible explicit override. |
| `caddy_on_demand` | `operator_managed` | Full assignment inventory and coordinated activation required. Only an already-trusted current lineage or an explicit operator adoption into a new trusted lineage gains operator-policy authorization. Lineage-changing adoption makes prior TXT and override evidence ineligible; health remains separately identified. |
| `approximated` | `operator_managed` | Full assignment and provider-resource inventories plus coordinated activation are required. Only an already-trusted current lineage or an explicit operator adoption into a new trusted lineage gains operator-policy authorization. Lineage-changing adoption makes prior TXT and override evidence ineligible; health remains separately identified. Every residual provider certificate and virtual host requires an approved retain, remove, or manual disposition before activation. |
| `caddy_on_demand` | `approximated` | Target-strategy dry run and evidence eligibility review required. Source-strategy success is not automatically target-strategy proof. |
| `approximated` | `caddy_on_demand` | Target-strategy dry run and evidence eligibility review required. Source-strategy success is not automatically target-strategy proof. |
| `passthrough` or `external` | `operator_managed` | Alias normalization only. It is not a passthrough-user migration, but coordinated configuration deployment is still required so all processes agree on the canonical name and semantics. |
| Unknown or unsupported strategy | Any target | Unsupported until every assignment and process is inventoried and the effective source behavior is known. The cutover aborts rather than guessing. |

Both TXT-enforced targets use the same fail-closed rule: policy-only, legacy-flag-only, timestamp-only, unknown, and ended-lineage evidence is rejected on the first protected decision after activation.

## Cutover invariants

1. Every registered assignment appears exactly once in the frozen inventory, including orphaned, partially deleted, duplicate, and otherwise invalid records.
2. Registration, detach/delete, transfer, challenge rotation, override changes, verification persistence, scheduler refresh, and cache repopulation cannot race the inventory or activation.
3. The target strategy is evaluated against the same assignment generation that activation uses.
4. No protected decision uses operator policy after a TXT-enforced target activates.
5. No protected decision uses legacy `verified` or `resolving` booleans as ownership proof.
6. `verified_confirmed_at` or any other timestamp without assignment and proof provenance is insufficient.
7. DNS resolution, HTTPS success, certificate presence, and historical health never create authorization evidence.
8. An explicit override is distinguishable from TXT proof and operator policy.
9. A cache entry is usable only when it carries the active configuration and assignment generation. Missing or mismatched generations fail closed.
10. Rollback restores strategy behavior, not old evidence snapshots. Ineligible evidence stays ineligible, while evidence validly committed during activation remains eligible when it still satisfies the source strategy's current-lineage and evidence-specific rules.

## Roles and sign-off

Before preflight, the change record identifies:

- the operator responsible for executing the cutover;
- the person authorized to approve the exception dispositions and activation;
- the person responsible for rollback and incident coordination, who may be the executing operator;
- the source and target strategy, deployment scope, maintenance window, and evidence-retention location.

The activation approval and final outcome sign-off are explicit records. Absence of either record is an abort condition.

## Preflight freeze and isolation

The maintenance barrier applies to every process and interface that can mutate an assignment or decide whether it may be used. The operator records the freeze start time, active configuration generation, process set, queue depth, and cache generation before proceeding.

| Surface | Required state before inventory | Proof of isolation |
| --- | --- | --- |
| Domain registration and attach/detach/delete | Writes are rejected or queued outside the application with no automatic replay during the barrier. Challenge creation or rotation is also frozen. | A write probe is rejected with the maintenance reason, and the assignment count/generation remains unchanged. |
| Domain transfer | Transfers and ownership/org changes are rejected. In-flight transfers are completed or rolled back before the snapshot. | No assignment has a transfer transaction in progress; a transfer probe cannot commit. |
| Serving authorization | Affected custom-domain authorization is isolated from external traffic or returns a fail-closed maintenance denial. Canonical service traffic may remain available if it cannot use custom-domain authorization state. | Synthetic requests cannot obtain an allow decision from the source strategy after the barrier begins. |
| ACME permission decisions | New custom-domain permission decisions are denied during the barrier. Certificate retries cannot bypass application isolation. | A permission probe for an otherwise source-authorized fixture is denied with the barrier generation. |
| Provider certificate and virtual-host management (`approximated` → `operator_managed` only) | Application-initiated provider requests, renewals, replacements, imports, deletions, and orphan-cleanup work for affected domains are paused, drained, or generation-fenced before provider-resource inventory. | The provider inventory remains stable during preflight, and queued cleanup cannot delete a resource after the affected domain's effective strategy becomes `operator_managed`. |
| Domain-verification workers | Consumers that can persist verification, override, assignment, or authorization state are paused and drained. Late results from an earlier generation are rejected. | Queue depth and in-flight count are recorded as zero, or remaining messages are fenced by generation. |
| Scheduler | Domain refresh scheduling is paused and in-flight refreshes are drained. A disabled scheduler is recorded as disabled rather than treated as proof of quiescence elsewhere. | No scheduled domain job can start or persist after the freeze generation. |
| Configuration reload | Automatic reload and independent node changes are suspended. The exact source and target configurations are immutable artifacts. | Every participating process reports the same source generation before activation. |
| Authorization and domain caches | Cache fills are paused or generation-fenced. Source-generation entries cannot be served after activation. | Cache inventory records the namespaces/generations to invalidate; a stale-entry probe is available for the first-request checks. |

The freeze aborts if any writer or decision-maker cannot be identified, isolated, drained, or generation-fenced. Waiting for eventual consistency is not isolation.

## Assignment inventory

The inventory is taken after the freeze and before target evaluation. It is machine-readable, immutable for the duration of the attempt, and reconciled against the datastore's complete assignment index. Pagination, filters, active-only views, and application caches are not accepted as the sole source.

Each row contains at least:

- cutover ID and snapshot generation;
- stable assignment identity and assignment-lineage identity;
- canonical domain name and stored display form;
- organization/owner identity, including orphaned or missing-owner status;
- creation, transfer, detach/re-attach, challenge-rotation, and last-mutation generations where available;
- source effective strategy and normalized canonical name;
- TXT challenge host and a stable identifier for the expected challenge value;
- `verified`, `resolving`, `verified_by_override`, `verified_confirmed_at`, and unconfirmed-window state;
- persisted proof provenance, including strategy, exact assignment lineage, challenge identity, observed match result, and completion time;
- explicit-override provenance, scope, status, actor/audit reference, and assignment lineage;
- DNS and HTTPS health as separate observations with freshness and outcome reason;
- pending worker/scheduler work and known cache entries;
- target classification, target authorization decision, and reason code.

Inventory completeness requires all of the following:

1. The snapshot count equals the authoritative assignment-index count taken within the freeze.
2. Every inventory row has one classification and one target decision.
3. Duplicate canonical names, missing organizations, missing assignment identities, conflicting indexes, and unreadable records appear as exceptions rather than being dropped.
4. A second enumeration under the same freeze produces the same assignment identities and mutation generations.
5. The sum of all classification counts equals the total inventory count.

For each affected domain whose effective source strategy is `approximated` and target strategy is `operator_managed`, preflight also builds a provider-resource inventory directly reconciled against the provider control plane. This inventory is separate from the assignment inventory because a residual or orphaned provider resource may have no current assignment. It records every provider certificate and virtual host, provider resource identifier, associated canonical domain and assignment when known, residual/orphan status, pending cleanup work, and an explicit operator-approved disposition of retain, remove, or manual handling. Every residual resource appears exactly once and has a disposition before activation. A remove disposition is executed directly in the external provider's control plane under the operator's change process; it does not authorize application deletion after `operator_managed` activation.

## Evidence eligibility and classification

### Assignment-lineage rules

TXT proof and explicit overrides apply to an assignment, not merely to a domain string.

The current assignment lineage is continuous while the canonical domain, organization/owner assignment, and assignment identity remain unchanged. Transfer, detach and re-attach, deletion and recreation, or operator adoption of an existing untrusted registration ends the prior lineage. Challenge rotation and TXT demotion do not end the assignment lineage; they are TXT-evidence boundaries. Operator-policy promotion without an adoption boundary does not create a TXT-proof lineage.

Evidence eligibility has a shared assignment-lineage boundary and type-specific invalidation rules. Persisted provenance must establish all of the following:

- the TXT proof or override belongs to the current assignment lineage;
- TXT proof matched the current expected challenge identity and value, and no later challenge rotation, definitive TXT failure, or demotion invalidated that proof;
- an explicit override names the current assignment lineage and remains active and unrevoked; challenge rotation or TXT demotion does not invalidate it;
- a transfer, reassignment, detach and re-attach, deletion and recreation, or lineage-changing operator adoption makes both prior TXT proof and prior overrides ineligible;
- the producing strategy and outcome are known and acceptable to the target policy;
- the target evaluator can verify the evidence without inferring provenance from health or aggregate booleans.

Legacy `verified=true`, `resolving=true`, or `ready?` state is insufficient. A `verified_confirmed_at` timestamp, with or without `verified=true`, is also insufficient when it does not identify the assignment lineage, challenge, validating strategy, and successful match. Timestamps order events; they do not prove what was checked.

### Required classifications

For a TXT-enforced target, every assignment receives exactly one of these classifications, in authorization-precedence order:

| Classification | Required evidence | TXT-enforced target decision |
| --- | --- | --- |
| **Explicit override** | Active, unrevoked override whose scope and audit provenance identify the current assignment lineage. A bare legacy boolean without sufficient lineage is not enough. | Eligible for authorization as an override, never relabeled as TXT proof. |
| **Eligible TXT proof** | Complete, target-acceptable TXT provenance for the current assignment lineage, or a fresh target-strategy proof bound to the frozen assignment generation, and no active eligible override. | Eligible for authorization as TXT proof. |
| **Operator policy only** | Current registered assignment authorized by operator-managed policy, with no eligible TXT proof or override. Health and legacy booleans do not change this class. | Rejected immediately after target activation unless a fresh proof or explicit override is established before activation. |
| **Unknown/ineligible legacy state** | Missing or conflicting lineage; legacy flags only; timestamp-only evidence; ended-lineage proof; stale or mismatched override; malformed/orphaned record; unsupported source strategy; or any state that cannot be classified safely. | Rejected. Manual disposition is required; uncertainty never defaults to authorization. |

When both an active current-lineage override and eligible TXT proof exist, the effective classification and reported authorization basis are **Explicit override**. The TXT evidence remains separately recorded and is not cleared or relabeled.

A fresh target-strategy TXT pass may move an assignment without an active eligible override from policy-only or unknown into eligible TXT proof only when the result is bound to the same frozen assignment and challenge generation and is persisted as provenance during the activation transaction or revalidated inside the activation barrier.

For an `operator_managed` target, every assignment is classified, in authorization-precedence order, as active current-lineage override, eligible current-lineage TXT proof, already-trusted current lineage, approved adoption into a new trusted lineage, or denied. Eligible TXT proof and overrides retain their basis when no lineage-changing adoption occurs. An approved adoption makes prior TXT and override evidence ineligible. An untrusted lineage with no eligible proof, override, or approved adoption remains denied.

## Target-strategy dry run

The target dry run executes while the source strategy remains active but isolated. It evaluates the exact target configuration against every frozen assignment without changing active authorization, legacy booleans, overrides, challenge values, health history, or caches.

The dry run must:

1. select the target strategy explicitly rather than reading the active source strategy;
2. evaluate every inventory row exactly once and account for retries separately;
3. perform a fresh TXT check where target policy requires one;
4. distinguish pass, definitive failure, indeterminate result, override, and tooling error;
5. bind each result to the cutover ID, assignment lineage, challenge identity, target configuration digest, and observation time;
6. report the target decision for serving, link/domain use, and ACME permission separately where those consumers differ;
7. leave health observations separate from authorization outcomes;
8. produce deterministic totals that reconcile to the frozen inventory.

A dry-run pass is candidate evidence, not activation. It cannot open serving or ACME access by itself. Activation either revalidates the TXT result or consumes it through a bounded, generation-bound mechanism that prevents assignment, challenge, configuration, or result changes between check and commit. Only when activation persists that result with complete provenance does it become committed TXT evidence.

### Exception report

The machine-readable exception report includes every assignment that the target evaluator would deny. For a TXT-enforced target, that includes every assignment not accepted by eligible TXT proof or explicit override. For an `operator_managed` target, it includes every untrusted assignment without eligible proof, an active override, or approved adoption, plus every malformed or inconsistent assignment. Each item records:

- assignment and lineage identity;
- classification and reason code;
- source and target decision;
- TXT outcome and whether it was definitive or indeterminate;
- relevant legacy flags and timestamps, clearly labeled non-evidence;
- override status and why it is eligible or ineligible;
- health observations, clearly labeled non-authoritative for authorization;
- required disposition and approving operator;
- final disposition: prove, explicitly override, leave denied, repair/remove assignment, or abort the cutover.

No exception may be omitted, silently coerced to success, or resolved by setting a legacy `verified` flag. The activation manifest contains zero unresolved exceptions. “Leave denied” is a resolved disposition only when the operator explicitly accepts the resulting customer impact.

## Activation sequence

Activation uses one of two supported mechanisms:

- **Atomic generation activation:** configuration, evidence decisions, and cache generation become visible as one cutover generation, and every decision-maker rejects missing or mismatched generations.
- **Fail-closed outage activation:** all affected web, worker, scheduler, and ACME decision paths remain stopped or denied while target configuration and evidence are installed, caches are cleared, and every process is restarted and acknowledged.

A rolling configuration change without a generation barrier is unsupported.

The sequence is:

1. Reconfirm that the freeze remains active and that inventory identities and mutation generations are unchanged.
2. Reconcile the final exception report. Any unresolved, added, removed, or changed assignment aborts activation.
3. For affected `approximated` → `operator_managed` domains, reconcile the provider-resource inventory against the provider control plane and require activation approval to include the complete disposition manifest. Any unlisted residual certificate or virtual host, missing disposition, or unapproved disposition aborts activation. Retain, remove, and manual actions remain operator change-process work; target activation does not grant the application permission to delete provider resources.
4. Persist target authorization decisions with their assignment lineage and the new cutover generation. For a TXT-enforced target, persist eligible fresh proof and override decisions; policy-only and unknown/ineligible rows receive no qualifying TXT authorization. For an `operator_managed` target, retain eligible current-lineage proof and overrides, retain already-trusted lineages, and apply approved adoptions as new trusted lineages that inherit no prior proof or override.
5. Activate the target configuration and target authorization evaluator for web processes, workers, scheduler, and ACME permission decisions under the same generation.
6. Invalidate source-generation authorization and domain caches. Cache misses under the target generation are evaluated from eligible evidence; they do not fall back to source booleans.
7. Start or release processes only while external serving and ACME isolation remains in place. Every process acknowledges the target strategy, configuration digest, cutover generation, and cache generation.
8. Reject and quarantine late worker or scheduler writes from the source generation.
9. Run the first-request checks before any domain refresh, health sweep, or scheduler execution.
10. Restore ACME and serving traffic only after the first-request checks pass and activation receives explicit operator approval.
11. Resume workers, scheduler, registration, and transfer in that order, with generation enforcement still active.

At no point may source and target evaluators both return allow decisions for the same protected surface.

## First-request authorization checks

The first-request checks prove that target authorization is enforced before refresh. No verification command, domain refresh, cache warming, scheduler run, or manual state repair occurs between activation and these checks.

The fixture set includes:

| Fixture | Stored state before cutover | Expected under either TXT-enforced target |
| --- | --- | --- |
| Policy-only legacy flags | Operator-policy assignment with `verified=true` and `resolving=true`, no eligible proof or override | Denied on the first protected decision. |
| Timestamp only | Policy-only assignment with `verified_confirmed_at` but no complete lineage/proof provenance | Denied. |
| Ended lineage | Historical TXT pass for an assignment that was transferred, detached/re-attached, recreated, or replaced by lineage-changing adoption | Denied. |
| Invalidated TXT evidence | Historical TXT pass tied to a rotated challenge, definitive later TXT failure, or demotion, with no active current-lineage override | Denied; the current assignment lineage itself need not have ended. |
| Stale source cache | Cached operator-managed allow decision from the source generation | Denied; cache generation mismatch is observable. |
| Eligible TXT | Current-lineage, target-acceptable TXT proof | Allowed independently of DNS/HTTPS health. |
| Eligible override | Current-lineage explicit override | Allowed and reported as override, not TXT proof. |
| Override plus eligible TXT | Active current-lineage override and eligible current-lineage TXT proof | Allowed and reported as override; TXT evidence remains recorded. |
| Unknown legacy | Conflicting, malformed, orphaned, or unclassifiable authorization state | Denied with an actionable reason. |

For an `operator_managed` target, the fixture set also includes:

| Fixture | Stored state before cutover | Expected after activation |
| --- | --- | --- |
| Already trusted lineage | Current trusted registration | Allowed as `operator_policy` when no higher-precedence basis exists. |
| Eligible proof or override | Current-lineage evidence without adoption | Allowed with the existing evidence basis, not relabeled as `operator_policy`. |
| Approved adoption | Existing untrusted registration approved for adoption | Allowed as `operator_policy` on the new trusted lineage; prior proof and override are ineligible. |
| Untrusted and not adopted | Current registration with no eligible proof, override, or approved adoption | Denied on the first protected decision. |

Each fixture is exercised against every protected decision path, including custom-domain use/link creation, request-time serving authorization, ACME permission, and any worker path that makes an authorization decision.

The policy-only, timestamp-only, ended-lineage, invalidated-TXT-evidence, and stale-cache fixtures are repeated in these conditions:

1. a process kept warm across activation with a seeded source-generation cache entry;
2. a newly restarted process with an empty in-memory cache;
3. a full application restart after target activation;
4. the scheduler disabled before and after activation;
5. the scheduler enabled but not yet allowed to run;
6. a queued source-generation worker result delivered after activation;
7. each accepted alias normalized to the same source semantics before the TXT-enforced transition.

Every denial occurs before refresh. Any allow decision for those fixtures is a rollback condition.

## Health observation during cutover

Health collection is paused during the frozen inventory and activation unless it is implemented as a read-only, generation-bound observer that cannot persist authorization state. Paused checks report “not checked during cutover”; they do not retain a fabricated healthy status.

After first-request checks pass, health observation resumes with these rules:

- DNS resolution and HTTPS outcomes retain their own timestamps, freshness, and reason codes.
- Unknown, `not_checked`, stale, and failed health are reported honestly.
- Health success does not promote authorization, renew TXT proof, or clear an override.
- Health failure does not demote eligible TXT proof, clear an override, or alter operator policy.
- Certificate presence or a successful TLS handshake is not ownership evidence.
- Authorization dashboards and alerts never aggregate policy/proof decisions into a generic health status.

A target TXT validation is an authorization-proof operation, not a DNS/HTTPS health observation, even when both use DNS infrastructure.

## Success, abort, and rollback criteria

### Success criteria

The cutover succeeds only when:

- inventory completeness and classification totals reconcile;
- the exception report has no unresolved item;
- every process reports the same target strategy, configuration digest, cutover generation, and cache generation;
- every first-request case has the expected decision before refresh;
- source-generation cache and late-write probes fail closed;
- all expected eligible TXT and override assignments remain usable with the correct authorization basis;
- policy-only and unknown/ineligible assignments remain denied under a TXT-enforced target, and untrusted, unadopted assignments without eligible evidence remain denied under an `operator_managed` target;
- for affected `approximated` → `operator_managed` domains, the provider-control-plane inventory reconciles, every residual certificate and virtual host has an approved retain, remove, or manual disposition, queued orphan cleanup resolves the current effective strategy and skips deletion as `externally_managed`, and the application performs no provider request, renewal, replacement, import, or deletion after activation;
- health reporting remains separate from authorization;
- serving, ACME, workers, scheduler, registration, and transfer resume without generation mismatch;
- monitoring shows no unexpected authorization allows or mixed-generation decisions through the declared observation window;
- the operator records final sign-off and the evidence bundle location.

### Abort criteria

The attempt aborts before activation when any of these occurs:

- freeze or drain cannot be proven on any required surface;
- assignment counts or mutation generations change under the freeze;
- an assignment is missing, duplicated, unreadable, or unclassifiable without an approved deny disposition;
- target configuration differs across processes or cannot be rendered as an immutable artifact;
- the target dry run is incomplete, non-deterministic, or cannot separate indeterminate from failure;
- exception totals do not reconcile to inventory totals;
- required first-request fixtures or stale-cache probes are unavailable;
- rollback configuration or rollback authority is unavailable;
- activation approval is absent.

An abort leaves the source strategy active, removes the maintenance barrier only after source-generation consistency is reconfirmed, and retains the failed preflight evidence.

### Rollback criteria

Rollback begins immediately after activation when any of these occurs:

- a policy-only, timestamp-only, ended-lineage, stale-cache, or unknown fixture receives an allow decision under a TXT-enforced target, or an untrusted, unadopted fixture without eligible evidence receives an allow decision under an `operator_managed` target;
- web, worker, scheduler, or ACME processes report mixed strategy/configuration generations;
- a source-generation write or cache entry affects a target decision;
- an assignment accepted in the approved manifest is unexpectedly denied because the activation lost eligible evidence;
- an assignment absent from the approved manifest is authorized;
- the target strategy cannot sustain decision availability within the declared operational threshold;
- monitoring or evidence capture is unavailable, making the authorization result unverifiable.

## Rollback procedure

1. Re-establish serving, registration, transfer, worker, scheduler, and ACME isolation.
2. Capture the failed generation's decisions, logs, cache metadata, assignment generations, and post-activation inventory before changing configuration.
3. Stop or fence every target-generation decision-maker and drain target-generation writers.
4. Activate the immutable source configuration as a new rollback generation; do not restore a datastore or cache snapshot wholesale.
5. Recompute source authorization from the source strategy, current assignment lineage, and persisted evidence. Apply normal basis precedence: an active current-lineage override remains `explicit_override`; otherwise eligible current-lineage TXT evidence remains `txt_proof`; otherwise a trusted current lineage under an operator-managed source may receive `operator_policy`. Do not relabel TXT proof or an override as operator policy.
6. Preserve the cutover classification of legacy flags, timestamp-only state, ended-lineage proof, and ineligible overrides. Rollback does not set `verified`, `resolving`, `verified_confirmed_at`, or `verified_by_override` from the pre-cutover snapshot, and it does not discard activation-committed evidence merely because the target generation failed.
7. Invalidate both source-precutover and failed-target cache generations. Start processes under the rollback generation while traffic remains isolated.
8. Run first-request checks proving that no assignment is authorized by replayed ineligible evidence and that expected source-policy behavior is restored.
9. Resume traffic and writers only after all processes acknowledge the rollback generation and the operator signs the rollback record.

A dry-run TXT result that was not committed during activation remains a candidate observation tied to its assignment lineage and challenge; rollback does not make it eligible evidence. TXT evidence validly committed during activation remains persisted evidence and remains eligible after rollback when its assignment lineage and challenge are current, no later failure or demotion invalidated it, and the restored source policy accepts its provenance. Rollback neither rewrites nor relabels either kind of artifact. A later cutover reevaluates candidate observations and committed evidence under that cutover's target policy.

## Monitoring and evidence retention

Every authorization decision during the barrier and observation window records, without relying on health fields:

- cutover and configuration generation;
- component and process identity;
- assignment and lineage identity;
- effective strategy and normalized alias;
- decision and stable reason code;
- authorization basis: TXT proof, explicit override, operator policy, or none;
- evidence generation and cache generation;
- stale-cache, generation-mismatch, and late-write rejection indicators;
- decision time and correlation ID.

Cutover monitoring provides separate counts and alerts for:

- allows and denials by authorization basis and component;
- policy-only or unknown allows under a TXT-enforced target, which alert immediately;
- mixed configuration/evidence/cache generations;
- source-generation cache hits and late writes;
- inventory-to-decision count mismatches;
- TXT pass, failure, and indeterminate outcomes;
- DNS and HTTPS health, reported on separate panels from authorization.

The retained evidence bundle contains:

- source and target configuration artifacts and digests;
- freeze acknowledgements and process inventory;
- before, activation, and rollback inventories as applicable;
- assignment classification and provenance records;
- target dry-run results and exception dispositions;
- for `approximated` → `operator_managed` transitions, the reconciled provider certificate and virtual-host inventory, approved retain/remove/manual disposition manifest, external provider change references, and `externally_managed` skip records from queued orphan-cleanup work;
- cache invalidation and process-generation acknowledgements;
- first-request results, including restart, stale-cache, worker, and disabled-scheduler cases;
- monitoring extracts for the declared observation window;
- abort or rollback records;
- activation and final operator sign-offs.

The bundle is immutable, access-controlled, and retained for the deployment's declared security-audit period. The retention period and storage location are approved before preflight; a cutover does not proceed with ephemeral terminal output as its only evidence.

## Implementation acceptance matrix

Runtime implementation and tooling are ready for this runbook only when automated tests or an isolated operational rehearsal demonstrate all rows:

| Case | Required result |
| --- | --- |
| Operator-managed → `caddy_on_demand` | Policy-only state is denied before refresh; current-lineage TXT proof and override are accepted. |
| Operator-managed → `approximated` | Policy-only state is denied before refresh; current-lineage TXT proof and override are accepted. |
| TXT-enforced → operator-managed | Only already-trusted current lineages or registrations explicitly adopted into new trusted lineages are authorized as operator policy, without manufacturing TXT confirmation or assumed health; adoption inherits no prior TXT proof or override. |
| `approximated` → `operator_managed` provider resources | Before activation, every residual provider certificate and virtual host is inventoried and has an approved retain, remove, or manual disposition. After activation, queued orphan cleanup re-resolves the effective strategy and records `externally_managed` without deletion; the application does not request, renew, replace, import, or delete provider resources. |
| TXT-enforced → TXT-enforced | The target evaluator accepts only target-eligible current-lineage evidence or override. |
| Legacy flags/timestamp | `verified`, `resolving`, `ready?`, and timestamp-only state cannot authorize. |
| Assignment-lineage change | Transfer, detach/re-attach, recreation, and lineage-changing operator adoption make prior TXT proof and overrides ineligible. |
| TXT evidence boundary | Challenge rotation, definitive TXT failure, and demotion invalidate affected TXT proof without ending the current assignment lineage or invalidating an active current-lineage override. |
| Restart | A cold process produces the same target decision as a warm process. |
| Stale cache | A source-generation allow entry is rejected after activation. |
| Disabled scheduler | First-request enforcement is unchanged when no refresh job runs. |
| Late worker result | A source-generation result cannot change target authorization. |
| Mixed fleet | A process on the wrong generation denies rather than serving with source semantics. |
| Health independence | DNS/HTTPS success and failure do not create or revoke authorization. |
| Rollback | Source behavior returns without replaying ineligible proof, flags, timestamps, overrides, or caches; valid activation-committed current-lineage evidence is preserved with its original basis. |
| Inventory drift | Registration, transfer, or challenge mutation during preflight causes abort. |

## Out of scope

- Migration of passthrough users; the deployment context states that no active passthrough user base requires migration.
- Passthrough deprecation or a compatibility window.
- A staged old/new passthrough-client rollout.
- Per-domain strategy selection or incremental regional activation.
- Direct datastore repair as a substitute for provenance-aware tooling.
- Certificate-provider migration.
- Treating DNS or HTTPS health as authorization.
