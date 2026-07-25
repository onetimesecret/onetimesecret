# AGENTS.md

Guidance for coding agents and AI reviewers working in this repo.

## Repo invariants (not defects; do not flag in review)

- Session data is stored under string keys, never symbols. Reads and writes
  agree on string keys by design.
- Times are stored in UTC and converted only at the display edge.
- OAuth connect-intent binding is enforced transitively via the single
  `session['omniauth.state']` slot (omniauth-oauth2 >= 1.9 rejects mismatched
  callbacks). Explicit per-intent transaction binding is not required.
- SessionSidecar stores per-value Redis keys with individual TTLs. Single-use
  semantics come from short-TTL delete-on-read keys; expiry is not data loss.
- Issuerless SSO providers (GitHub, Google) are refused on tenant surfaces
  (`refuse_issuerless_on_tenant?`); identity lookups never match across
  surfaces on the `(provider, '', uid)` key.

These exemptions describe the *current* mechanisms. A PR that modifies the
mechanism enforcing an invariant (e.g. the omniauth-oauth2 version or state
slot handling, SessionSidecar TTL/delete-on-read behavior, the issuerless
refusal path) puts that invariant in scope: review the change against the
invariant rather than exempting it.

## Non-blocking observations

Findings without a concrete failure scenario are not defects, but structural
or architectural observations (extraction candidates, complexity hotspots,
missing abstractions) may be raised as explicitly non-blocking follow-up
suggestions — at most two per review, clearly marked non-blocking. The author
either opens an issue or declines; neither blocks merge.

## Replying to review comments

- Every P1 gets a binary disposition before merge: fixed (cite the commit),
  refuted (one short reply citing the relevant invariant), or ticketed.
- Refutations are one paragraph max.
