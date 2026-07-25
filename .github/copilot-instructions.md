# Code review instructions

## Do not comment on

- Locale `content_hash` values (missing, stale, or mismatched). CI gates these
  and `pnpm locales:hashes:apply` regenerates them.
- Anything rubocop, eslint, or prettier enforces: layout, alignment, quoting,
  whitespace, argument wrapping. These run in pre-commit and CI.
- Missing stdlib `require` lines, unless you can name the exact command that
  fails without them.
- Typos in comments or docs, unless they invert the meaning.
- Test file organization or helper placement.
- Pre-existing code not changed in this PR.

Do not summarize the PR, restate what the diff does, or add praise.

## Threshold

Skip any finding you cannot state as a concrete failure scenario: a specific
input or state leading to wrong output, data loss, or a security consequence.
No scenario, no comment. Finding nothing that meets this bar is an acceptable
review outcome.

## Non-blocking observations

Structural or architectural observations that lack a failure scenario may be
raised as explicitly non-blocking follow-up suggestions — at most two per
review, clearly marked non-blocking.

## Invariants

See AGENTS.md for repo invariants that must not be reported as defects. Those
exemptions apply to the current mechanisms only: a PR that modifies the
mechanism enforcing an invariant puts that invariant in scope for review.
