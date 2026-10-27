# 3. Consumption cleanup

Status: Direction approved by the user in conversation; not evidence of implementation or release approval. Requirements below paraphrase those decisions and preserve the existing at-most-once boundary.

## Purpose and scope

Scheduled jobs clean up unfinished incomplete creations and terminal secrets. Cleanup is distinct from plaintext delivery and remains discoverable after request-process death.

Accepted [ADR-019](../../adr/adr-019-at-most-once-secret-reveal.md) states: “a lost response forfeits the reveal rather than risking a second.”

## Requirements

- Scheduled cleanup uses tunable settings; no fixed completion deadline, SLA or five-minute alert policy is prescribed.
- Cleanup failures are logged effectively with safe diagnostics. Unfinished work remains discoverable independently of request-local memory.
- Incomplete-creation cleanup uses persistence evidence under [creation failure handling](02-creation-failures.md), not response loss as proof of incompleteness; complete committed pairs are not blindly deleted.
- Ambiguous consumption never permits another plaintext delivery.
- Repeated cleanup neither repeats accounting nor recreates deleted records or extends expiration.
- Receipt repair preserves unrelated fields and reports conflicting terminal states.
- Cleanup coordinates with the existing definite pre-plaintext decryption-error rollback; neither modifies another operation or defeats rollback safety.
- Failed passphrase submissions on explicit reveal count toward passphrase-attempt counters whether empty or nonempty. Metadata-only requests do not affect those counters; metadata requests and empty-passphrase submissions still count toward general rate limits.

## Acceptance

- Unfinished incomplete creations and terminal secrets remain discoverable for scheduled cleanup after process death.
- Lost acknowledgments, duplicate cleanup and rollback races produce no second reveal or deletion of another operation's data.
- Persisted ciphertext removal and receipt repair are checked independently; in-memory clearing and request-local `ensure` are not proof of durable deletion.
- Explicit reveal and metadata-only access apply the distinct passphrase-attempt and general rate-limit rules above.

## Exclusions and unresolved implementation details

No plaintext replay, worker decryption, automatic request retry or recovery service is introduced. Cleanup discovery, settings and datastore durability assumptions require implementation inspection; no new complex framework, queue or multi-phase state machine is prescribed. Destructive GET removal, including creator one-time display migration impact, follows [release validation](05-release-validation.md).
