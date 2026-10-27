# 4. Runtime response validation

Status: Direction approved by the user in conversation; not evidence of implementation or release approval. Requirements below paraphrase those decisions.

## Purpose and scope

Creation and memo consumers accept validated operation-specific data and fail fast on invalid responses. V3 and first-party frontend API surfaces share a consolidated error envelope; the first-party frontend is the only consumer, and the external API remains preview rather than a stable compatibility commitment.

## Requirements

- Creation responses are validated before success consumers, browser persistence or navigation use them.
- Invalid responses fail fast, are logged with safe diagnostics and produce an error; consumers do not retain partial handles, accept partial success or expose a third “uncertain” state.
- Malformed responses do not prove that a mutation failed or rolled back. [Creation failure handling](02-creation-failures.md) governs persistence evidence and response loss without automatic retries or a recovery service.
- Memo responses match the requested receipt and update only its validated memo. Failed refresh validation preserves the previous list and exposes an error; an unconfirmed memo write is not automatically repeated.
- Background refresh does not consume the creator's one-time generated-value display. Method redesign follows the [release constraints](05-release-validation.md).
- The consolidated error envelope covers V3 and first-party frontend API surfaces, including account, organization and domain APIs, while preserving HTTP statuses, authentication challenges, retry semantics and headers, CSRF protections and other security behavior.
- V2 and Incoming remain unchanged unless an explicit separate decision authorizes changes.

## Acceptance

- Malformed bodies, mismatched identifiers and response loss cause no unchecked updates, partial-handle retention or automatic duplicate writes.
- Diagnostics distinguish runtime validation failure from confirmed server rejection without inventing a third user-facing outcome.
- Error-envelope consolidation preserves security and protocol behavior across the included surfaces.
- One-time display and receipt-only browser persistence boundaries remain protected through the method migration.

## Exclusions and unresolved implementation details

No client recovery endpoint, plaintext persistence or new concurrency protocol is introduced. Exact error-envelope fields and mappings, operation schemas and an authorized non-revealing memo refresh path remain implementation work requiring inspection, not settled contract details. V2 and Incoming envelope changes are excluded.
