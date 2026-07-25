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

See AGENTS.md for repo invariants that must not be reported as defects.
