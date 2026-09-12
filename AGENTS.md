# AGENTS.md

Guidance for coding agents and AI reviewers working in this repo.

## Project claims and source authority

### Attribution

Do not infer project terminology or guarantees from repetition. Before attributing a claim to the project, locate an authoritative primary source and provide its exact wording. Treat delivery notes, commit messages, agent output, and documents created or modified during the current task as leads, not evidence. If the wording is absent, call it an interpretation or proposal. Never place paraphrases in quotation marks.

### Authoritative sources

Authoritative sources must be identified explicitly; repository presence alone does not confer authority. Accepted specifications and ADRs may establish project claims only within their stated scope. Delivery notes, commit messages, issue discussions, summaries, and agent-authored text are non-authoritative unless an authoritative source incorporates them explicitly.

### Normative claims

For normative claims concerning security, privacy, compatibility, persistence, or data loss:

1. Cite the authoritative source and its exact wording.
2. Distinguish quotations, paraphrases, interpretations, and proposals.
3. Do not use material created or modified during the current task to validate that task’s claims.
4. If no authoritative wording exists, report the claim as unsupported.

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

### Using git

NEVER AMEND, RESTORE or REBASE unless asked.

Use `--no-pager` to avoid hanging on paging. Pipe to head or tail if you suspect a large output. For example:

```bash
git --no-pager diff
git --no-pager show abcd1234 | head -n 20
```

### Responses

Use short responses. Write in plain language.

## Pull Request Reviews

### Security-posture decisions

- Changes that widen access, including on error paths, require explicit
  operator approval.
- Verify a finding’s claimed failure on the current baseline before applying
  its prescribed fix.

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
clears the dev shell's entire exported environment except a six-name
keep-list, then loads the lane env pointing at the dockerized test
services on 127.0.0.1 21xx ports. A raw invocation inherits ambient env
and can reach dev data.

```console
$ tests/lanes/run --list     # all lanes and overlays
$ tests/lanes/run unit       # try:unit + spec:fast (most changes)
$ tests/lanes/run full-pg    # Postgres-backed auth integration
$ tests/lanes/run simple --only path/to/one_spec.rb[:LINE]
```

Use `--only <path>` (repeatable) while iterating: it runs just that file
in the lane's environment — seconds instead of minutes — with the same
env scrub. `*_try.rb` routes to tryouts, everything else to rspec. It
skips the lane's other tasks, so run the whole lane before pushing.

The runner needs bash 5+ (macOS ships 3.2: `brew install bash`) and
starts the backing services itself if they aren't up
(`docker compose -f compose.test.yml up --wait -d`). Vitest, lint, and
type-check need no services or lane: run them via pnpm directly.
Details: `tests/lanes/README.md`.

The shell scripts CI runs (`scripts/ci/`, `.github/scripts/`) are tested
outside the lane runner — they touch no datastore and no Ruby. Run
`scripts/tests/run.sh` for those, and `scripts/check-shell-lint.sh` for
shellcheck/actionlint. Both also run in the `Static analysis` workflow.

**Dev-environment worktrees**: The `.test-mode` sentinel file marks a
repo checkout that has loaded the test environment. Do not run tests
unless `.test-mode` already exists.

## Replying to review comments

- Every P1 gets a binary disposition before merge: fixed (cite the commit),
  refuted (one short reply citing the relevant invariant), or ticketed.
- Refutations are one paragraph max.
