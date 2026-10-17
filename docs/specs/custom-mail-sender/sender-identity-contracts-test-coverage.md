# Sender identity contracts: test coverage specification

Status: Proposed acceptance coverage; not a report of passing tests.

Design authority for this proposal: [Lookup and deletion contracts](sender-identity-contracts-design.md). The design is proposed, not an accepted project-wide guarantee.

## Purpose

Tests demonstrate that provider evidence and deletion outcomes remain distinct through real strategy adapters, the operation layer, and affected consumers. Passing isolated adapter tests or a historical suite count does not establish cross-provider parity.

An executor can choose test organization and helpers. The scenarios, negative assertions, and consumer policies below are the acceptance criteria. Provider-specific mechanics must reflect the installed SDK/API contract rather than invented uniform behavior.

## Existing test surfaces

Extend or reuse these locations; new shared examples or support fixtures can follow repository conventions:

- [Strategy specs](../../../spec/unit/onetime/mail/sender_strategies/): `ses_sender_strategy_spec.rb`, `sendgrid_sender_strategy_spec.rb`, `lettermint_sender_strategy_spec.rb`, `smtp2go_sender_strategy_spec.rb`, and `smtp_sender_strategy_spec.rb`.
- [Operation specs](../../../spec/unit/onetime/operations/delete_sender_domain_spec.rb).
- [Collision preservation specs](../../../spec/unit/onetime/operations/domains/collision_sender_preservation_spec.rb).
- [Sender-config API integration specs](../../../apps/api/domains/spec/integration/simple/domain_sender_config_spec.rb).

Before implementation, discover all other callers and tests of the changed helpers, including provisioning, verification, and domain removal. These paths are starting points, not an exhaustive coverage claim.

Inspected baseline tests include SendGrid operation lookup-failure/absence cases and complete-list failure cases. Lettermint tests explicitly accept nil for missing `data`, and absence tests expect `deleted: true`. Those expectations must change, not be worked around. Existing provider dispatch tests largely stub final strategy results and cannot prove adapter-to-operation parity.

## Test layers

| Layer | Uses real | Stubs/fakes | Proves |
|---|---|---|---|
| Result contract | Constructors and validators | Nothing | Legal states and invalid combinations |
| Adapter | Strategy, matching, pagination, response translation | HTTP or SDK transport | Provider evidence classification |
| Operation parity | `DeleteSenderDomain` and real selected strategy | Credential/config dependencies and provider boundary | Failure propagation and operation logging |
| Consumer integration | Consumer control flow and outcome mapping | Provider boundary; datastore only as required by suite | Cleanup audit, preflight decisions, lifecycle preservation |

Shared examples assert outcomes; provider-specific fixtures establish how those outcomes arise. Do not stub `delete_sender_identity` in parity tests or `list_domains` in pagination regressions. SDK doubles are suitable when response translation belongs to the SDK; include HTTP-level coverage where local code owns status/body parsing. Network access to real providers is disabled.

## L: lookup and inventory coverage

| ID | Scenario | Required result and negative assertions |
|---|---|---|
| L01 | Valid target in first page | Individual lookup is `found` with correct deletion target; no unnecessary later-page request |
| L02 | Target on a later page | Individual lookup and inventory-based matching find the same identity; exact continuation arguments are asserted |
| L03 | Valid exhausted search without target | `absent`; no deletion attempted after lookup absence |
| L04 | Valid empty inventory | `complete` with empty identities; matching yields `absent`, not failure |
| L05 | First-page authentication, permission, rate-limit, or server error | `failed`; no absence, creation fallback, or deletion inferred |
| L06 | Later-page HTTP error or timeout | Inventory is `failed`; partial entries are not exposed as usable inventory and not cached as success |
| L07 | Missing/null/wrong-type collection or invalid JSON where locally parsed | `failed`, not an empty collection |
| L08 | Invalid entry shape, missing domain, or matching entry without a valid required ID | `failed`; no nil/blank-target delete request; include SendGrid and Lettermint |
| L09 | Malformed continuation metadata or repeated/cyclic cursor | Bounded termination with failure; no hang or false completion |
| L10 | Nonempty final page, full or short, followed by terminal empty page | Exhaustion requires the terminal request for limit/offset APIs; a short page is not completion |
| L11 | Unrelated domains and supported alternate response shapes | Matching remains provider-correct; no unrelated deletion target is selected |
| L12 | A valid early target followed by a failing page | Individual lookup may succeed without visiting the failing page; full inventory must fail |
| L13 | List endpoint 404 versus target-specific not-found | Generic list failure is `failed`; only verified target-specific semantics can yield `absent` |
| L14 | Repeated target entries with conflicting identities, if provider permits duplicates | Preserve established provider selection semantics or explicitly fail ambiguity; never introduce a new silent first-match policy |
| L15 | SendGrid and Lettermint domain names differ only in case | Individual lookup and inventory matching select the same original provider ID; exercise provisioning recovery, deletion, and collision protection; unrelated names do not match and IDs are not case-folded |
| L16 | SendGrid returns fewer entries than requested on every nonempty page | Advance offset by actual returned count; find a later target and exhaust through an empty page for inventory/absence; never stop on a nonempty short page |
| L17 | SendGrid returns more entries than requested | `failed`; oversized pages do not authorize absence, creation fallback, or deletion |

Apply pagination cases to SendGrid and Lettermint, not to SES solely to make the matrix rectangular. Apply filtered-lookup shape cases to SMTP2GO. Document non-applicable rows and their reason.

### Lettermint regression fixtures

Installed `lettermint` 0.2.1 accepts `page_cursor:` and maps it to `page[cursor]`; its source documents a 30-entry default. The official Team API OpenAPI schema independently documents `page[size]` default 30, `page[cursor]`, and required top-level `next_cursor` (string or null, with null terminating). Use these verified facts as fixture authority; see the [validation report's Lettermint evidence and schema link](sender-identity-validation-report.md#lettermint). For D03 and D11, use the release repository's tagged `spec/fixtures/errors/` evidence (not included in the installed gem): structured `code: 'RESOURCE_NOT_FOUND'` for the captured missing-domain response, and no code for the captured message-only router response. String-error and proxy-HTML examples are synthetic, not live captures. Exercise actual SDK error translation as well as strategy classification. A generic `HttpRequestError` with a 404 status is not what the SDK raises. Recheck the installed SDK, including exception fields, if its version changes.

Minimum regression: page one omits the sender domain, page two contains it, and the terminating response follows actual API semantics. Exercise both individual lookup and collision preflight with the real pagination path. Include malformed second-page data and a cursor cycle. A target on the first page does not excuse incomplete bulk inventory enumeration.

### SendGrid boundary fixtures

For requested page size 50, cover empty, 49, 50, 51, and a generated 1,000-entry inventory. When the server honors the requested page size, empty-page termination requires 1, 2, 2, 3, and 21 requests respectively. Individual lookup request counts depend on the target's page. Preserve explicit configured `domain_id` bypass of lookup and use that exact target in deletion and collision comparisons.

Add a simulated server cap below 50: for five entries returned as 2, 2, 1, then 0, assert requests with `limit=50` and offsets 0, 2, 4, and 5. Exercise later-target lookup, complete inventory, and exhausted absence through the real paginator. A target on page three must not be missed; a later-page failure must not expose the earlier entries as a complete inventory. Include a page with 51 entries to prove oversized responses fail validation.

## D: deletion outcome coverage

Run shared outcome assertions against all four remote providers with provider-appropriate fixtures.

| ID | Scenario | Required outcome |
|---|---|---|
| D01 | Provider confirms deletion | `deleted`, success true, deleted true, error nil |
| D02 | Valid lookup establishes absence | `absent`, success true, deleted false, error nil; zero delete requests |
| D03 | Target disappears before deletion | Verified missing-identity response gives `absent`, not `deleted`; one attempted delete |
| D04 | Provider rejects deletion | `failed`, success false, deleted false, nonempty safe error |
| D05 | Timeout/connection failure before or after request dispatch | `failed`; no assertion that the remote identity necessarily remains |
| D06 | Lookup fails or is malformed | `failed`; no delete request |
| D07 | Invalid sender address | `failed`; no remote request |
| D08 | Missing required credentials | `failed`; no false success; account for valid SDK credential-chain behavior where supported |
| D09 | Unexpected exception with blank message | `failed` with usable fallback error detail |
| D10 | SMTP | `skipped`, success true, deleted false; no remote request |
| D11 | Error resembles not-found but is not authoritative for the target | `failed`; no broad HTTP/message-based absence classification |
| D12 | Invalid deletion response under actual endpoint semantics | `failed`; do not require a JSON body for endpoints whose valid success response is empty |
| D13 | SMTP2GO `/domain/remove` HTTP 200 returns only a string `request_id`, without `data`, as documented in v3.0.0 | `deleted` through the real HTTP client, strategy, and operation; no extra confirmation lookup. Also retain v3.0.2 `data.domains` acknowledgement coverage. Reject error envelopes, invalid JSON, missing/blank/non-string request ID in the no-data variant, malformed provided collections, and a retained target; do not accept arbitrary empty hashes or relax `/domain/view` validation |

SES absence can be established directly by delete-time `NotFoundException`; it does not require an artificial lookup fixture. Current SES constructors supply explicit two-part credentials and do not enable default-chain fallback or pass session tokens. D08 must test the current explicit-key path; role/profile/session-token support would require a separate behavior change. See the [preparation record](sender-identity-contracts-preparation.md) for credential precedence, duplicate-selection decisions, and unexecuted deployment checks. Lettermint list 404 and delete missing-identity responses are separate tests. SMTP2GO uses verified provider error codes/response semantics, not assumed equivalence to other providers. SendGrid covers both resolved and configured IDs.

## O: operation boundary and logging

| ID | Scenario | Assertions |
|---|---|---|
| O01 | Every real remote strategy, D01–D09 as applicable | Operation success/failure agrees with validated strategy outcome |
| O02 | Failed outcome | Error log emitted; no operation deleted/absent/skipped success log |
| O03 | Absent outcome | Successful result; absence log/context, never a deletion event |
| O04 | Skipped outcome | Successful result with reason; no deletion event |
| O05 | nil, empty hash, unknown outcome, missing required error, contradictory fields | Operation failure; malformed result never defaults to success |
| O06 | Unexpected strategy exception | Existing operation exception-to-failure behavior preserved |
| O07 | No config, no effective provider, unsupported provider | Existing deliberate skip policy preserved; no strategy/remote call |
| O08 | Successful preflight followed by fresh lookup/deletion failure | Operation reports failure despite earlier evidence; include at least one later-request regression |

Use exact operation log assertions, not a global count of all stack logs. Do not make tests depend on incidental prose where structured outcome and error assertions suffice.

## C: consumer and lifecycle coverage

| ID | Consumer scenario | Required observations |
|---|---|---|
| C01 | Collision preflight finds Lettermint identity beyond page one | Same target as individual deletion lookup; shared identity protected if referenced elsewhere |
| C02 | Complete inventory has no matching identity | Existing preflight policy preserved: no remote target, not an automatic refusal |
| C03 | Inventory malformed, unavailable, or incomplete | Preflight refuses before destructive work for the affected group; no partial-inventory authorization |
| C04 | Early shared match but unreadable later reference | Existing all-reference check still refuses; no short-circuit hiding unreadable evidence |
| C05 | Unselected record or another removal candidate shares identity | Remote identity remains protected, including after earlier local removals in the same apply |
| C06 | Successful inventory used by many records/groups | One complete enumeration per provider/scope/apply, not one walk per record |
| C07 | First enumeration fails, later group retries successfully | Failure not cached as empty or complete; successful retry can populate cache |
| C08 | Dry run then apply | Fresh provider enumeration; dry run makes no mutation; no stale cross-run cache |
| C09 | Provider cleanup fails after sender config removal | Local removal remains committed, normal API success policy preserved, audit reports `provider_cleanup: failed` |
| C10 | Deleted/absent/skipped cleanup | Existing operation success mapping preserved; no incidental public response/schema changes |
| C11 | Lease loss, contention, or provisioning concurrency paths | Existing lock/lease and refusal tests still pass; no bypass introduced by cached evidence |
| C12 | Provisioning target on later page | Existing identity reused through shared lookup rather than treated as absent |
| C13 | Provisioning lookup fails | Failure is not interpreted as absence or used to justify create-after-lookup; established duplicate recovery preserved |
| C14 | Sanitized collision refusal | Contains permitted record reference and reason; excludes credentials, raw SDK body/message, and sender address |
| C15 | Other consumers of changed helper return types | Verification and domain-removal behavior remains intentional; every discovered caller is migrated or explicitly unaffected |

C02 corrects the quoted preflight description: the inspected `CollisionSenderPreservation` accepts confirmed absence. Tests must preserve that policy rather than implement the earlier hypothetical refusal behavior.

## Request budgets and scale

Use generated fixtures and deterministic request counts, not wall-clock expectations based on speculative Redis latency. A 1,000-record bulk test proves provider enumeration is reused across records; separate pagination fixtures prove request count depends on provider inventory size. Include multiple groups to expose cache scope errors.

A failed enumeration may be retried by subsequent groups, so “one enumeration per apply” is a successful-cache bound, not an unconditional request ceiling. Do not assert exactly one request for a paginated provider. These tests do not claim that the existing Redis preflight read count or overall maintenance-window duration has been optimized.

## Implementation and validation sequence

1. Reproduce the existing SES/Lettermint/SMTP2GO false-success paths through real strategies and `DeleteSenderDomain`. Capture failing assertions before fixes where executable.
2. Add result validation and shared outcome coverage; update all producers and consumers together.
3. Add provider pagination/shape regressions, then collision/provisioning integration cases exercising those paths.
4. Update obsolete expectations deliberately: absent is no longer deleted, missing data is no longer acceptable absence, invalid results no longer imply success.
5. Run focused suites, then the appropriate broader lanes. Record failures unrelated to this work separately without altering unrelated code.

Ruby tests run only through `tests/lanes/run`, and only when the checkout already contains `.test-mode`, as required by [AGENTS.md](../../../AGENTS.md). Do not create the sentinel merely to bypass this condition. Use `--which <path>` to identify lanes and `--only <path>` for targeted runs; use the lane's integration services for API tests. No raw rspec/rake/try invocation or real-provider cleanup is part of validation.

## Completion evidence

The executor's report includes:

- A mapping of L/D/O/C IDs to test examples, with provider applicability and any unresolved cases.
- Verified SDK/API details used for pagination and not-found classification.
- Exact executed commands and results, distinguishing new regressions from pre-existing coverage.
- Any blocked or unexecuted tests and the reason; no inferred passes from code inspection.
- Confirmation that all affected call sites were reviewed and local-removal/locking policy remains unchanged.

Coverage is complete when applicable rows are demonstrated, not when a target test count is reached. A historical report of 437 passing tests is neither a baseline rerun nor evidence that these scenarios pass.
