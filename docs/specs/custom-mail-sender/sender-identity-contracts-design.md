# Sender identity lookup and deletion contracts

Status: Proposed design, not an implemented or accepted guarantee.

Companion: [Test coverage specification](sender-identity-contracts-test-coverage.md).

## Objective and scope

Provider adapters distinguish evidence about an identity from the outcome of deleting it. Failed, malformed, or incomplete lookups never establish absence. Deletion failures never become successful no-ops through missing result fields.

Scope includes SES, SendGrid, Lettermint, SMTP2GO, SMTP, `DeleteSenderDomain`, and consumers of the affected lookup helpers, including collision sender preservation and provisioning. The design preserves local-removal policy, identity sharing checks, installation credential selection, and locking.

Out of scope: durable retries, reconciliation queues, new provider support, changing public deletion API success semantics, Redis preflight optimization, persistent inventory caching, and account-wide transactional snapshots. This proposal does not establish new project security or persistence guarantees.

## Baseline and source map

The pre-fix implementations below are historical evidence of behavior, not an accepted specification. See the [validation report](sender-identity-validation-report.md) for implemented fixes and remaining limits:

- [DeleteSenderDomain](../../../lib/onetime/operations/delete_sender_domain.rb) infers failure from `result[:error]`; a hash without that field can become success regardless of whether deletion failed.
- [Sender strategies](../../../lib/onetime/mail/sender_strategies/) return deletion hashes. SendGrid supplies errors on failure; SES, Lettermint, and SMTP2GO have failure branches without them. The latter three report confirmed absence as `deleted: true`.
- Lettermint `list_domains` reads only `client.domains.list['data']`. Missing data becomes nil; pagination is not implemented.
- SMTP2GO `extract_domain_entry` tolerates missing or malformed collections as no match.
- SendGrid paginates by limit/offset and rejects non-array pages. Its individual matcher can still return nil for a matching entry without an ID.
- [CollisionSenderPreservation](../../../lib/onetime/operations/domains/collision_sender_preservation.rb) caches successful provider lists within one apply and does not cache failures. Its comment states: “A complete list without the sender domain returns nil”. Consequently, the quoted scenario in which every missing identity causes refusal is not the inspected baseline. Incomplete Lettermint enumeration can instead be mistaken for confirmed absence.
- [DeleteSenderConfig](../../../apps/api/domains/logic/sender_config/delete_sender_config.rb) removes local configuration before provider cleanup and records `provider_cleanup` from the operation result. Provider failure does not normally reverse local removal or change the successful API response.

## Responsibility split

| Boundary | Responsibility | Does not decide |
|---|---|---|
| Lookup | Establish a valid identity, confirmed absence, or inability to establish either | Whether to create, delete, skip a collision group, or return API success |
| Deletion | Report acknowledged deletion, established absence, deliberate skip, or failure | Whether local configuration removal is rolled back or retried |
| Consumer | Apply its existing policy to explicit results | Reinterpret malformed or incomplete evidence as absence |

## Contract L: identity lookup

### Individual result

Proposed value shape: `LookupResult(status, identity, error)`.

| Status | Identity | Error | Meaning |
|---|---|---|---|
| `found` | Valid provider-specific identity | nil | The target identity was established |
| `absent` | nil | nil | A valid complete search or authoritative target-specific response established absence |
| `failed` | nil | Required | Evidence is unavailable, invalid, ambiguous, or incomplete |

`failed` describes the lookup outcome; it does not assert that the identity exists or is absent. Identity contains the provider's actual deletion target, not merely stored provisioning metadata. Required IDs cannot be nil, blank, or invalid for that provider. Domain-name comparison is case-insensitive at every provider boundary and remains consistent between provisioning, preflight, and deletion, including domain-name target sharing checks. Provider identity IDs remain opaque and are not case-folded. This changes comparison, not stored names, request targets, or domain canonicalization; other normalization changes remain out of scope.

A valid match may terminate an individual search early. A no-match result requires successful exhaustion. A matching domain with an invalid identity is a malformed response, not absence.

### Complete inventory form

Bulk preflight uses the same lookup boundary in its inventory form: `InventoryResult(status, identities, error)` with statuses `complete` and `failed`. This is not a third consumer policy contract.

- `complete`: all pages and required entry fields validated; identities may be empty.
- `failed`: nonempty safe error detail; partial entries are unavailable to consumers as usable evidence.
- Searching a complete inventory yields `found` or `absent`. Searching a failed inventory propagates failure.
- A complete inventory is a successfully exhausted enumeration, not an atomic snapshot of the provider account.

Use one provider-owned pagination primitive for inventory enumeration and individual lookup. Avoid parallel implementations with different validation or matching rules. Existing helper names can remain as compatibility wrappers during migration, but nil must not encode both failure and absence at any migrated boundary.

### Provider responsibilities

**SendGrid:** retain limit/offset paging. Validate array pages and required entry fields, not only the outer array. Individual lookup may stop on a valid match; inventory enumeration cannot. Advance offset by the number of entries actually returned and stop only on an empty page; a nonempty short page does not establish exhaustion. Reject a page larger than the requested limit as malformed. This avoids false absence if the server caps pages below the requested limit; the inspected reference specifies no numeric default or maximum. With 50 entries returned per page, exactly 1,000 entries require 21 requests, including the terminal empty page. Preserve an explicit installation `domain_id` override as the actual deletion target; an override is configuration, not evidence of remote existence.

**Lettermint:** traverse every cursor page using the installed SDK's supported arguments and response metadata. Require a valid `data` collection and valid entries. Do not infer completion merely from a short page unless the provider contract permits it. Repeated/cyclic cursors, malformed continuation metadata, or a later-page failure produce `failed`. Missing data is not an empty list. The installed SDK's `page_cursor` argument, its mapping to `page[cursor]`, the 30-entry default, and the required top-level `next_cursor` are verified; see the [validation report's Lettermint evidence](sender-identity-validation-report.md#lettermint).

**SMTP2GO:** validate the filtered view response before interpreting no match. Preserve documented supported entry shapes rather than narrowing them incidentally. A provider-specific missing-domain response may establish absence; a generic HTTP failure or unrelated not-found response may not. For `/domain/remove`, accept the official v3.0.0 HTTP 200 acknowledgement containing a nonempty string `request_id` without `data`; absence of a domain collection alone is not a removal failure. Also accept the archived v3.0.2 acknowledgement with valid `data.domains` and no retained target. Keep error envelopes and malformed provided data as failures; do not generalize this endpoint-specific exception to lookup responses, arbitrary 2xx bodies, or an unqualified empty hash. The client boundary must preserve enough status/envelope evidence to distinguish these cases. See the [validation report's SMTP2GO evidence](sender-identity-validation-report.md#smtp2go).

**SES:** preserve direct deletion by domain name; do not add a list request merely for parity. Any existing lookup consumer translates its provider response into the same evidence states where needed.

**SMTP:** has no remote inventory or identity lookup requirement.

### Inventory lifecycle

Collision preflight performs one successful logical enumeration per provider and credential scope per apply, not one HTTP request. The existing installation-level credential model permits the existing provider-scoped cache; it must not be broadened to mix accounts or endpoints. A completed inventory can be indexed in memory using the same matching semantics as individual lookup.

Failed enumeration is not cached as an empty inventory. Preserve the existing ability for a subsequent group's preflight to retry. Dry run and apply use fresh caches. No inventory is authority to bypass deletion-time errors or existing locks. An individual lookup finding an early match must not shortcut complete-inventory collection in collision preflight.

## Contract D: deletion outcome

Proposed value shape: `DeletionResult(outcome, message, error)` with derived `deleted` and `success?` values.

| Outcome | success? | deleted | Error | Operation log meaning |
|---|---|---|---|---|
| `deleted` | true | true | nil | Provider acknowledged deletion |
| `absent` | true | false | nil | Identity already absent |
| `skipped` | true | false | nil | Deliberately not applicable, with reason |
| `failed` | false | false | Required | Cleanup did not establish success |

Use small shared validated result constructors, following repository Ruby conventions. A value object or validated hash is acceptable; the semantic states and boundary validation are mandatory. If the legacy `deleted` field remains, derive it rather than maintaining an independent boolean. Unknown outcomes, missing required fields, and contradictory results fail at the operation boundary; `{}` is not success.

A failure includes invalid required configuration, unavailable credentials, rejected requests, transport failures, malformed responses, and indeterminate lookup. A timeout after a deletion request is `failed` even if the provider might have acted: the client lacks confirmation. Error detail is safe and nonempty; it does not depend on an exception having a nonempty message.

Absence handling is scoped to the relevant provider operation:

- SES identity-deletion `NotFoundException` maps to `absent`.
- A complete lookup with no match maps to `absent` without a delete request.
- A deletion-time missing-identity response maps to `absent` only when the provider's documented endpoint/error semantics establish that meaning.
- List endpoint 404, authentication failure, or an ambiguous proxy response does not establish identity absence. Narrow method-wide rescues accordingly.
- SMTP returns `skipped` and makes no remote request.

## Consumer integration

`DeleteSenderDomain` switches on validated outcomes, preserves `Result(success, message, error)` and its `success?` interface, and maps unexpected exceptions to failure as before. A failed result emits an operation error, never a deleted/no-op success log. Distinguish absence from deliberate skip in structured context or message. Do not assert one log across the entire stack: adapters may already emit diagnostic logs.

Collision sender preservation retains its existing policy: confirmed absence means no remote target; failed evidence refuses the affected preflight. Shared targets remain protected, including targets referenced by unselected records or other removal candidates. SES/SMTP2GO domain-name target resolution and SendGrid ID overrides remain intact.

Provisioning may create after confirmed absence. It does not infer absence from lookup failure. Existing provider duplicate-creation recovery remains provider-specific.

Local deletion callers retain their removal and lease behavior. Corrected failures change cleanup reporting from completed to failed; they do not imply rollback. Public exposure of detailed outcomes, automatic retry, and persisted reconciliation require separate design work.

## Error boundaries and compatibility

Provider error classification stays in adapters. Consumers do not parse message text to discover outcome. Stable failure categories may accompany safe messages, but a cross-provider exhaustive error taxonomy is unnecessary.

Collision audit refusals preserve their existing sanitized record reference and fixed reason; do not persist raw SDK exceptions, credentials, response bodies, or sender addresses there. This is a proposed preservation requirement, not authorization to broaden existing logging elsewhere.

Changing shared lookup helpers affects provisioning, verification, and preflight as well as deletion. Inventory every caller before changing return types. Update callers and their tests in the same implementation series. Do not quietly retain a permissive helper for deletion while fixing only bulk preflight.

## Alternatives and decisions

- Adding missing `error` fields alone addresses known branches but leaves malformed results and incomplete evidence indistinguishable from success. It is insufficient as the final design.
- Treating every `deleted: false` as failure breaks SMTP and idempotent absence.
- Implementing pagination only in collision code leaves individual provisioning/deletion inconsistent.
- Requiring full enumeration for every individual lookup wastes requests after a valid match; complete enumeration is mandatory only for absence and inventory consumers.
- New retry systems or local rollback would alter lifecycle policy and are excluded.

## Execution gates

Before selecting fixtures or implementing provider mappings, verify installed SDK versions, Lettermint cursor arguments/termination metadata, provider-specific missing-identity errors, and successful delete response semantics. Record the evidence in test descriptions or implementation notes. Ambiguous responses remain failures pending verification; do not guess a permissive mapping.

Completion requires the companion coverage matrix, migration of affected call sites, and an explicit validation report. Neither this document nor earlier passing test counts establish implemented parity.
