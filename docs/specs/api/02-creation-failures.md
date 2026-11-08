# 2. Creation failure handling

Status: Direction approved by the user in conversation; not evidence of implementation or release approval. Requirements below paraphrase those decisions.

## Purpose and scope

Creation failures are logged with effective, safe diagnostics and return an error when a response can be delivered. Internal persistence evidence is separate from the user-facing result and from reliable delivery of creation handles.

## Requirements

| Condition | Behavior |
| --- | --- |
| Creation fails or runtime validation rejects its response | The consumer receives an error, not partial success, retained partial handles or a third “uncertain” state. |
| Persistence acknowledgment is lost | Internal evidence records what is known; missing acknowledgment does not prove rollback or justify blind deletion of a complete pair. |
| A complete pair is committed but its response is lost | The pair retains its original expiration; a fully lost response cannot deliver an error to the client. |
| Incomplete persistence is confirmed | Safe cleanup targets only the unfinished incomplete creation under the [cleanup requirements](03-consumption-cleanup.md). |
| Optional nonessential follow-up fails after commit | The failure is logged without failing committed creation under the [commit boundary](01-creation-commit.md). |

Diagnostics identify the failing operation, stage and available persistence evidence without secret content, passphrases or capability handles. An error does not promise that no writes occurred. A deliberate new creation request can duplicate an earlier creation whose result was not received; neither server nor frontend automatically retries creation or mutation failures.

## Acceptance

- Lost acknowledgments and client validation failures are not treated as proof of no writes.
- Error handling and cleanup do not blindly delete complete pairs or repeat unrelated accounting.
- Failures remain diagnosable without exposing sensitive values or promising duplicate-free retries.
- User-facing success or error behavior remains simple even when internal persistence evidence is inconclusive.

## Exclusions and unresolved implementation details

No operation-token API, plaintext cache, automatic resubmission, result-recovery service or exactly-once delivery guarantee is introduced. Persistence evidence and safe partial-write discovery require implementation inspection; neither an error response nor an in-memory exception establishes rollback. [Runtime validation](04-runtime-validation.md) uses the same failure behavior.
