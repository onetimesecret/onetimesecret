# AGENTS.md

Guidance for coding agents and AI reviewers working in this repo.

## Working

Default to executing the next obvious step instead of asking permission each
turn; ask only when irreversible.

| Situation                  | Action                                                    |
| -------------------------- | --------------------------------------------------------- |
| Technical approach unclear | Choose based on known best practices and convention       |
| Two valid implementations  | Choose based on the longterm health of the codebase       |
| Error after 3 attempts     | Document in BLOCKED.md, switch to next available task     |
| Ambiguous requirement      | Apply most reasonable interpretation, document assumption |

### Large Tasks

When context gets large: write current state to tasks/mission.md. Include: what's done, what's next, what's blocked, any open questions. The next session should be able to continue from tasks/mission.md without reading the full history.

### Responses

Use short responses. Write in plain language.

## Pull Request Reviews

### Repo conventions (not defects; do not flag in review)

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

These exemptions describe the _current_ mechanisms. A PR that modifies the
mechanism enforcing an invariant (e.g. the omniauth-oauth2 version or state
slot handling, SessionSidecar TTL/delete-on-read behavior, the issuerless
refusal path) puts that invariant in scope: review the change against the
invariant rather than exempting it.

### Non-blocking observations

Findings without a concrete failure scenario are not defects, but structural
or architectural observations (extraction candidates, complexity hotspots,
missing abstractions) may be raised as explicitly non-blocking follow-up
suggestions.

### Running tests

Run Ruby tests ONLY through the lane runner — never invoke `rspec`,
`rake spec:*`, `rake try:*`, or `try` directly. Only `tests/lanes/run`
clears the dev shell's environment (REDIS_URL, AUTH_DATABASE_URL, ...)
and loads the lane env pointing at the dockerized test services on
127.0.0.1 21xx ports. A raw invocation inherits ambient env and can
reach dev data.

```console
$ tests/lanes/run --list     # all lanes and overlays
$ tests/lanes/run unit       # try:unit + spec:fast (most changes)
$ tests/lanes/run full-pg    # Postgres-backed auth integration
```

The runner starts the backing services itself if they aren't up
(`docker compose -f compose.test.yml up --wait -d`). Vitest, lint, and
type-check need no services or lane: run them via pnpm directly.
Details: `tests/lanes/README.md`.

## Replying to review comments

- Every P1 gets a binary disposition before merge: fixed (cite the commit),
  refuted (one short reply citing the relevant invariant), or ticketed.
- Refutations are one paragraph max.
