# Config version annotations

`.env.reference` and `etc/defaults/*.yaml` record the release each setting first
shipped in, the way the Caddy docs mark features with "Since v2.10":

```bash
#SECRET_VERIFIER_MODE=warn  # Since v0.26.0
```

```yaml
secret_verifier_mode: <%= ENV['SECRET_VERIFIER_MODE'] || 'warn' %>  # Since v0.26.0
```

A self-hoster running v0.26.1 can then tell, from the config file alone, whether
a setting exists in their version — without cross-referencing a changelog.

This document is the contract. The annotator, the CI ratchet and the docs
generator all parse the same marker, and they break if any one of them drifts
from what is written here.

## The marker

An inline trailing comment on the key's own line, with exactly two spaces before
the `#`. It goes on the declaration line rather than a preceding comment line so
that a single copied line carries its own version.

The recognizer — the only pattern any tool may use:

```
[ \t]+# Since (v[0-9]+\.[0-9]+\.[0-9]+|unreleased)[ \t]*$
```

One marker per line, and no text after it.

## Policy

**Baseline v0.24.0.** Only keys first released in v0.24.0 or later are
annotated. Absence of a marker means "predates v0.24", which each file's header
states. Annotations mark what is new; annotating all 348 env vars would bury the
signal under 96 lines saying "this has always been here".

**Full patch precision** — `v0.24.3`, never `v0.24`. This project ships config
keys in patch releases, so rounding to the minor would promise a key to someone
on v0.26.1 that does not arrive until v0.26.3.

**Stable tags only.** Pre-releases (`-rc0`, `-PRE`) and `archive/*` tags never
appear in a marker: a self-hoster runs the stable release.

**Markers are immutable.** A shipped `Since v0.24.0` is a statement to everyone
running v0.24.0. The one sanctioned edit is `unreleased` → a real version, made
by the release process. If a key changes meaning, rename it — the old name's
marker leaves with it.

## Adding a config key

Annotate it `# Since unreleased`. You cannot know which version will ship it,
and a guess becomes a wrong number that the ratchet then freezes permanently.

```bash
NEW_ENV_VAR=default  # Since unreleased
```

`scripts/check-config-versions.sh` fails the PR if you forget.

## Cutting a release

Before tagging, resolve the placeholders:

```bash
scripts/resolve-unreleased-versions.sh v0.26.4
git add -u && git commit -m "chore(release): resolve Since annotations to v0.26.4"
git tag v0.26.4
```

Order matters — resolve, commit, then tag, so the tagged tree already says
`Since v0.26.4`. The script refuses to run if the tag already exists.

## The tools

| Script | Role |
| --- | --- |
| `config-version-archaeology.sh` | Derives first-release versions from git history. One-time backfill and audit; not a build step. |
| `config-yaml-version-map.py` | Resolves YAML settings, inheriting the version of the env var each one reads. |
| `annotate-config-versions.py` | Applies markers. Idempotent; refuses to re-date an existing marker without `--force`. |
| `resolve-unreleased-versions.sh` | Rewrites `unreleased` to the version being cut. |
| `check-config-versions.sh` | CI ratchet: new keys need a marker, shipped markers are frozen. |
| `generate-env-docs.py` | Generates the docs-site page from `.env.reference`. |

## How versions were derived

By scanning the tree of every stable release tag and taking the earliest release
that begins an unbroken run of releases consuming the key, through to HEAD.

The obvious alternative — pickaxe the introducing commit, then find the first
tag containing it — was tried first and produced wrong versions for 45 of 348
keys, in four independent ways:

1. **17 of 85 stable tags are not ancestors of HEAD** (release branches tagged
   without a merge back). Filtering containment by `--merged HEAD` skipped them
   and dated `FROM_NAME` to v0.24.0 when it shipped in v0.23.5.
2. **Prose dates keys from documentation.** `GITHUB_KEY`'s only occurrence at
   v0.24.0 is a code sample in the vendored `rodauth-reference-2.41+.md`.
3. **A Ruby-only `ENV[]` pattern misses the frontend.** `NODE_ENV` has been read
   by `src/utils/debug.ts` since v0.19.0 via `process.env`.
4. **First-match-ever mis-dates reintroductions.** `STRIPE_WEBHOOK_SIGNING_SECRET`
   is absent from all of v0.23.x and was dated to an abandoned first attempt.

Scanning release trees is immune to all four, and is also two orders of
magnitude faster: the cost is one grep per tag, not one per key per tag.

To re-derive or audit:

```bash
git fetch --unshallow && git fetch --tags   # a shallow clone reports nonsense
scripts/config-version-archaeology.sh SOME_KEY
```

## Known limits

- **Markers not yet on the base branch are not frozen.** Immutability protects
  what the base branch carries; unmerged work stays editable, which is the
  point.
- **Keys nested inside YAML sequence entries are not annotation sites.** A
  sequence entry has no stable dotted path (two sibling `- name:` entries
  collide), so those subtrees are skipped. A new setting added inside an
  existing list entry passes unannotated.
- **The ratchet needs the base branch fetched.** CI sets
  `CONFIG_VERSION_REQUIRE_BASE=1` so a missing base fails loudly rather than
  silently degrading to a syntax-only check. Locally it prints a NOTE.
