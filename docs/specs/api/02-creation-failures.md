# 2. Creation failure handling

Status: Proposed. No client result-recovery service is introduced.

## Purpose and scope

Creation errors report what is known without implying rollback. Internal consistency is separate from reliable delivery of creation handles.

## Requirements

| Outcome | Behavior |
| --- | --- |
| Definitely not committed | The request fails without a success result. |
| Commit uncertain | The request reports uncertainty; no automatic retry or blind deletion follows. |
| Committed, response lost | The pair retains its original expiry; delivery is not guaranteed. |
| Incomplete persistence confirmed | Internal cleanup targets only the proven incomplete creation. |

A deliberate new POST creates a new secret and can duplicate an earlier uncertain creation. Diagnostics exclude secret content, passphrases and capability handles.

## Acceptance

- A write followed by a lost acknowledgment is not mistaken for a definite no-write failure.
- Cleanup cannot delete a committed pair or repeat unrelated accounting.
- User-facing errors do not promise that retrying is duplicate-free.

## Exclusions and open decisions

No operation-token API, plaintext cache, automatic resubmission or exactly-once delivery. The [commit boundary](01-creation-commit.md), partial-write detection and cleanup deadline require explicit resolution; expiry of complete unreturned pairs does not excuse incomplete writes.
