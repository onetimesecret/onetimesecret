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

The leading blank is part of the recognizer, not decoration, and the tools that
hunt for a *near-miss* marker — a typo worth reporting rather than silently
ignoring — must require it too. Without it a `#` sitting inside a value reads as
an attempt at a marker: a URL fragment such as `.../changelog#since` then makes
a perfectly well-formed line look like it carries two markers, and the
one-marker rule rejects it. A real near-miss always has a blank before its hash,
so requiring one costs no detection.

Both ends of the near-miss recognizer are load-bearing, and the two spellings
must agree at both. They once diverged at the trailing end — the shell used
`([[:blank:]]|$)` and the annotator used Python's `\b` — so `# Since:` was a
near-miss to one tool and invisible to the other. Since a marker is
hand-written wherever this document says to write one, a stray colon shipped
`secure: true  # Since: v0.24.0  # Since v0.26.0` past every rule in the
ratchet: two contradictory version claims on one line, which is exactly what
the one-marker rule exists to stop. The boundary is `[^A-Za-z0-9_]` on both
sides now, which is what `\b` means, and still excludes `# Sincerely` and
`#since2020`.

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

A new key carrying a *released* version instead is a NOTE, not a failure. It is
usually wrong — a key cannot have shipped in a version that predates it — but
not always: merging `main` into a long-lived branch brings in keys that are new
relative to the branch base and did genuinely ship, and the backfill itself is
one large instance of that. Failing on it would block those merges, so the
guard reports the keys and lets a human judge.

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
| `annotate-config-versions.py` | Applies markers. Idempotent; refuses to re-date an existing marker, and `--force` widens that only to `unreleased` -> a release. |
| `resolve-unreleased-versions.sh` | Rewrites `unreleased` to the version being cut. |
| `check-config-versions.sh` | CI ratchet: new keys need a marker, shipped markers are frozen, markers are well-formed, the lines declaring one YAML path agree, and an env key is marked on its active declaration rather than only on a commented twin. |
| `generate-env-docs.py` | Generates the docs-site page from `.env.reference`. Its `--check` guard runs from the **docs** repo (`env-reference-drift.yml`, on docs PRs and nightly), not from this repo's CI — see the script header for why the dependency points that way. |

[ADR-042](../adr/adr-042-repository-tooling-packages.md) names `tools/envref/`
behind `bin/envref` as where application-coupled tooling of this size belongs,
with `envref` owning the reference's release annotation format. These six
scripts predate that decision by five weeks, are stdlib-only, and are wired
into CI by path. Bringing them under `bin/envref` is a behaviour-preserving
migration the ADR asks to be taken one domain at a time; it is not done. Two
questions have to be answered when it is: whether the marker keeps this
document's `# Since vX.Y.Z` spelling or takes the ADR's `As of x.y.z`, and
where the `etc/defaults/*.yaml` half lives, since ADR-042 scopes `envref` to
`.env.reference` and most of the machinery here is the YAML resolver.

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

Where inheritance and the pickaxe cannot prove an answer, the YAML path is
dated by the same release-tree scan, asked of the dotted path directly. This
matters because a bare line is not "no answer" — it states that the setting
predates v0.24.0 — so dropping an uncertain row would publish a false claim
rather than withhold one. 75 settings in `etc/defaults/` were bare for exactly
that reason before this was added.

## Known limits

- **Markers not yet on the base branch are not frozen.** Immutability protects
  what the base branch carries; unmerged work stays editable, which is the
  point.
- **Keys nested inside YAML sequence entries are not annotation sites.** A
  sequence entry has no stable dotted path (two sibling `- name:` entries
  collide), so those subtrees are skipped. A new setting added inside an
  existing list entry passes unannotated.
- **A key emitted by several mutually exclusive ERB branches is hand-marked.**
  `site.session.secure` is written by three `<% if %>/<% elsif %>` branches,
  so its dotted path resolves to three lines and the map generator refuses to
  guess which one declares it (`dotted path is not unique in the file`). All
  three carry `# Since v0.24.0` — the release the *setting* first shipped in,
  not the release each branch was added — because a bare line would read as
  "predates v0.24.0", which is false. It is the one marker in the backfill no
  tool derived, so it was checked by hand against the release trees:
  `secure:` is absent at v0.23.5 and v0.23.6 and present from v0.24.0, and a
  tree scan of the dotted path agrees. The map cannot verify them — they are
  not in it — but `check-config-versions.sh` does, by a different route: its
  rule 4 requires every line declaring one YAML path to carry the same marker,
  so a branch added to that block without the marker fails the PR. The marker
  still has to be copied by hand; forgetting is now caught.
- **A valueless key with nothing nested under it is classified
  inconsistently.** `check-config-versions.sh` sets `annot = 1` whenever its
  lookahead finds nothing nested below the key, and *nothing nested* is reached
  by more shapes than commented children: a sibling at the same indentation and
  a dedent both land there too. `config-yaml-version-map.py` disagrees on all
  of them — `KeyRecord.is_leaf` returns false for any valueless key with no
  sequence under it — so it emits no row and the annotator never writes a
  marker. The ratchet then asks for a marker no tool in this family will
  generate.

  `auth.defaults.yaml`'s `simple:`, whose two child keys are both commented
  out, is one instance of this and not the boundary of it; a placeholder
  section key added ahead of its children reaches the same demand. The spec
  settles neither reading — "commented-out lines declare nothing" says such a
  key is childless, while the key plainly introduces a section. Nothing in the
  three files fails today: `simple:` is the only key of the shape and it is not
  new.

  The `annot = 1` default is deliberate, not an oversight — see the comment
  above `extract_yaml_sites`. Judging a key by its own line alone lets a new
  nil- or list-valued *setting* slip past rule 1 owing no marker at all, which
  ships it bare, which the file headers define as the positive claim "predates
  v0.24.0". Flipping the default to 0 would settle this disagreement in the
  generator's favour and reopen that hole. A demand a human has to answer by
  hand is loud and gets fixed; a silently bare key is a false claim nobody
  sees. So the guard is left erring loud. If you hit it, give the key a live
  child, or write the marker by hand.
- **"Declaration line" is spelled at two breadths, and rule 2 uses the
  narrower one.** `YAML_DECL_RE` — in `check-config-versions.sh` and copied
  into `resolve-unreleased-versions.sh` — accepts a sequence-entry line through
  its optional `(- )?`. So rule 3 will validate a marker written on
  `- text: Feedback`, and the release resolver will rewrite an `unreleased`
  there into a concrete version. But `extract_yaml_sites` drops sequence
  subtrees by design, so that line never becomes a record, and rule 2 is fed
  only from records: the concrete marker it just produced can never be frozen.
  Reaching this takes hand-writing a marker where the policy says markers do
  not go, so no shipped line is affected. It is recorded because the *site set*
  is now spelled twice at different breadths — the same root cause as the three
  walkers below. The cross-check proposed there should also assert that the
  resolver's target set equals the ratchet's site set.
- **Three tools walk the YAML independently, and nothing asserts they agree.**
  `check-config-versions.sh` (awk), `annotate-config-versions.py` and
  `config-yaml-version-map.py` each re-implement the walk, and a divergence
  shows up not as a crash but as a wrong shipped version. The ERB divergence
  found in review is now closed — all three skip `<% if %>`/`<% end %>` before
  their sequence bookkeeping, so a control line at the sequence indentation no
  longer ends the sequence for two walks out of three. So is the key/colon
  separator: a tab between a key and its `:` is legal separation space and
  Psych accepts it, but the two Python walks matched spaces only — so
  `key<TAB>:` was a site to the ratchet, invisible to the map, and re-parented
  its children onto the preceding sibling, which would have dated them from
  that sibling's env var. All three now accept `[ \t]*` there; indentation
  stays spaces-only in all three, because YAML really does forbid tabs there.
  The valueless-key disagreement above remains, as does the site-set breadth
  mismatch.
  Reviewers have proposed, more than once, a cross-check asserting the three
  emit identical `(path, is_site)` sets for the three target files; that is
  the cheap pin, and a shared walker is the real fix.
  Neither is done. If you add a fourth shape to `etc/defaults/`, check it
  against all three by hand.
- **The ratchet needs the base branch fetched.** CI sets
  `CONFIG_VERSION_REQUIRE_BASE=1` so a missing base fails loudly rather than
  silently degrading to a syntax-only check. Locally it prints a NOTE.
