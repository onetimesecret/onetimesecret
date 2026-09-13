# envref

Release-version annotations for `.env.reference` and `etc/defaults/*.yaml` —
the `# Since vX.Y.Z` markers that let a self-hoster tell, from the config file
alone, whether a setting exists in the version they are running.

The marker contract is
[`docs/development/config-version-annotations.md`](../../docs/development/config-version-annotations.md).
That document is normative. This package is one of its readers, and
`tests/test_marker_contract.py` parses the document and asserts that every
copy of the recognizer — two Python modules, one shell variable, two awk
literals — still matches what it says.

## Running it

```bash
bin/envref --help
bin/envref check                       # CI ratchet; exit 1 on drift
bin/envref archaeology SECRET_MODE     # when did this key first ship?
bin/envref map --env-versions env-versions.tsv > yaml-versions.tsv
bin/envref annotate --check MAP.tsv    # verify markers without writing
bin/envref docs ../docs.onetimesecret.com --check
bin/envref resolve v0.26.4             # release step, before tagging
```

`bin/envref` is the only supported entry point (ADR-042). It finds the
checkout, exports `ENVREF_REPO_ROOT`, and starts this package through
`uv run --locked` — so CI and a laptop run the same versions. The `--locked`
is what makes that a guarantee rather than a habit: plain `uv run` silently
re-resolves and rewrites `uv.lock` when `pyproject.toml` has moved on, so a
dependency edit without a re-lock would quietly change what everyone runs.
With it, that divergence is an error naming the fix. There is no
bare-`python3` fallback on purpose either: a shim that bypasses its managed
environment is the drift ADR-042 exists to prevent.

If `bin/envref` fails with "The lockfile at `uv.lock` needs to be updated",
run `uv lock --project tools/envref` and commit the result.

## Layout

```text
tools/envref/
├── pyproject.toml       cyclopts; console script -> envref.cli:main
├── uv.lock              the reproducible half of the runtime
├── src/envref/
│   ├── cli.py           the only parser in this package
│   ├── paths.py         repo-root resolution, shared by Python and shell
│   ├── annotate.py      writes and verifies markers
│   ├── versionmap.py    resolves YAML settings to versions
│   ├── docsgen.py       generates the docs-site page from .env.reference
│   └── sh/              check / archaeology / resolve, unchanged bash + awk
└── tests/
```

The Python subcommands are registered straight off their modules' `run()`
functions, so each flag has exactly one definition — the signature and
docstring of the function that does the work. Re-declaring them in `cli.py`
would recreate, in the CLI layer, the duplicate-definition failure this
tooling keeps finding in its own YAML walkers.

`sh/` is bash and awk because porting 950 verified lines to Python would be a
rewrite, and ADR-042 asks for behaviour-preserving migration. A tool package
is allowed to be polyglot behind one entry point.

## Tests

```bash
uv run --locked --project tools/envref python -m unittest discover -s tools/envref/tests
```

They run on every PR inside `drift-guards.yml`, in the environment that job
already builds for `bin/envref check`. `pytest` is an optional convenience
(`uv sync --extra test`); the suite itself is stdlib, matching
`locales/scripts/tests`.

The suite's centrepiece is `test_yaml_walkers.py`, which asserts that all
three YAML walks — `annotate.py`, `versionmap.py` and the awk inside
`sh/check-config-versions.sh` — resolve identical dotted-path sets for every
file in `etc/defaults/`. Reviewers asked for that cross-check three times
while this tooling lived in `scripts/`, where it could not be written: two
top-level scripts cannot import each other. Making them modules of one package
is what made it possible, and it is the clearest practical argument for
ADR-042 in this repository. The awk walk answers through
`bin/envref check --print-sites`, which runs no rules and reads no base ref.

## Two places this reads ADR-042 rather than following it literally

**The marker spelling.** ADR-042 gives `envref` ownership of "the reference's
release annotation format, including `As of x.y.z` notes". The markers here
say `# Since vX.Y.Z`. That spelling predates the ADR by five weeks, is already
written on 605 lines, and is frozen by the ratchet once it ships — a marker is
a statement to everyone running that release, so re-spelling it later is not a
refactor. The contract document remains the authority on the grammar; if the
ADR's spelling is meant literally, changing it is a deliberate migration of
its own, not a rename.

**The scope.** ADR-042 scopes `envref` to `.env.reference`. This package also
covers `etc/defaults/*.yaml`, because the YAML resolver is the larger half of
the tooling and the ADR gives it no other home. Splitting them would put one
marker contract behind two commands.

## Runtime version

`requires-python = ">=3.11"` is this package's statement of what it runs on.
There is deliberately no `.python-version`: that file pins one exact
interpreter, and pinning 3.14 (what CI uses) would make every contributor on
3.11 or 3.12 download a second Python to run a guard that works fine on
theirs. CI pins the concrete version the same way every other Python job in
this repo does — `actions/setup-python` with an explicit `python-version` —
and `uv.lock` pins what actually varies, which is the dependencies.
