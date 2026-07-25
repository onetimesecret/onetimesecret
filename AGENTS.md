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

## Replying to review comments

- Every P1 gets a binary disposition before merge: fixed (cite the commit),
  refuted (one short reply citing the relevant invariant), or ticketed.
- Refutations are one paragraph max.
