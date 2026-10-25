# 3. Consumption cleanup

Status: Proposed cleanup behavior; the existing at-most-once boundary remains authoritative.

## Purpose and scope

Recipient reveal and burn leave no unfinished destruction hidden by a successful response. Receipt repair is distinct from plaintext delivery.

Accepted [ADR-019](../../adr/adr-019-at-most-once-secret-reveal.md) states: “a lost response forfeits the reveal rather than risking a second.”

## Requirements

- Ambiguous consumption never permits another plaintext delivery.
- Cleanup failure remains visible and unfinished work is discoverable after request-process death.
- Repeated cleanup neither repeats accounting nor recreates deleted records or extends expiry.
- Receipt repair preserves unrelated fields and reports conflicting terminal states.
- Any background cleanup is coordinated with the existing definite pre-plaintext decryption-error rollback; neither can modify another operation.

## Acceptance

Lost acknowledgments, process death, duplicate cleanup and rollback races produce no second reveal. Persisted ciphertext removal and receipt repair are checked independently. In-memory clearing and request-local `ensure` are not proof of durable deletion.

## Exclusions and open decisions

No plaintext replay, worker decryption or creator-preview redesign. Cleanup discovery, execution, deadline and datastore durability assumptions remain explicit design decisions. A queue or multi-phase state machine is not prescribed without demonstrating its necessity.
