---
id: 039
status: proposed
title: "ADR-039: Issue and Pull Request References in Change Metadata"
---

## Status

Proposed

## Date

2026-08-15

## Context

Issue and pull request references provide useful traceability, but their
placement determines whether they remain useful as code evolves. Bare ticket
numbers in source comments require access to the tracker, can become detached
from the code they originally described, and do not explain the local reason
for a non-obvious behavior.

Conversely, commit messages and pull request descriptions are durable,
searchable change metadata. They can carry the full root cause, alternatives,
and links to related work without making source comments depend on external
context.

## Decision

Record issue and pull request references in commit messages and pull request
descriptions. Use `Fixes #N`, `Closes #N`, or `Refs #N` where the repository's
workflow supports those trailers. Branch names may include an issue number for
additional traceability.

Source comments must explain the local, enduring reason for code that is not
self-evident. They must be understandable without access to an issue tracker.
A comment may add an issue or pull request reference only when it points to
necessary deeper context, such as a temporary upstream workaround, and only
after stating the reason directly. Do not use bare references such as `#4231`
or comments that merely say a change was made by a pull request.

Use an ADR or other maintained documentation for long-lived architectural
decisions rather than encoding them in either change metadata or inline
comments.

This keeps repository history as the source of change traceability while
keeping source code self-explanatory at the point of use.

## Consequences

### Positive

- `git log --grep` and repository tooling can find changes associated with an
  issue without searching source comments.
- Commit and pull request metadata can retain detailed rationale without
  bloating code.
- Comments remain useful to readers who cannot access the issue tracker.

### Negative

- Authors must provide meaningful issue references when writing commits and
  pull requests rather than relying on a later code comment.
- Temporary workarounds require a self-contained comment and, when applicable,
  a tracked follow-up reference.
