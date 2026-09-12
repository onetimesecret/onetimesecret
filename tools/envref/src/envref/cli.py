"""The `envref` command surface.

One domain, one command, subcommands underneath (ADR-042). Every operation
here used to be its own file in `scripts/`, invoked by path; the paths are now
package-private and `bin/envref` is the only supported way in.

Cyclopts is the only parser in this package. The Python subcommands are
registered straight off their modules' `run()` functions, so their parameters
and help text have exactly one definition — the signature and docstring of the
function that does the work. Re-declaring those flags here would recreate, in
the CLI layer, precisely the duplicate-definition failure this tooling keeps
finding in its own YAML walkers.

The three shell subcommands keep their implementations in `sh/`. Porting 950
lines of verified awk to Python is a rewrite, not a migration, and ADR-042
asks for the latter; a tool package is allowed to be polyglot behind a single
entry point.
"""

import os
import subprocess
import sys

from cyclopts import App

from . import UsageError
from . import annotate as _annotate
from . import docsgen as _docsgen
from . import versionmap as _versionmap
from .paths import RootNotFound, repo_root, sh_script

app = App(
    name="envref",
    help=(
        "Release-version annotations for .env.reference and etc/defaults/*.yaml.\n\n"
        "The marker contract is docs/development/config-version-annotations.md."
    ),
    version_flags=[],
)


def _run_sh(script: str, argv: list[str]) -> int:
    """Run a bundled shell implementation against the resolved checkout.

    ENVREF_REPO_ROOT is exported rather than passed as an argument so that the
    script, anything it shells out to, and this process all mean the same tree.
    """
    try:
        root = repo_root()
    except RootNotFound as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 2
    env = dict(os.environ, ENVREF_REPO_ROOT=str(root))
    proc = subprocess.run(["bash", str(sh_script(script)), *argv], cwd=root, env=env, check=False)
    return proc.returncode


@app.command(name="check")
def check() -> int:
    """Run the CI ratchet over the annotated config files.

    New keys need a marker, shipped markers are frozen, markers are
    well-formed, and the lines declaring one YAML path agree. Exit 1 on drift.

    Reads CONFIG_VERSION_BASE_REF, CONFIG_VERSION_REQUIRE_BASE and
    GITHUB_BASE_REF from the environment; see the script header for the order.
    """
    return _run_sh("check-config-versions.sh", [])


@app.command(name="archaeology")
def archaeology(*keys: str) -> int:
    """Derive first-release versions by scanning the stable release trees.

    Backfill and audit only — not a build step. With no keys, answers for every
    env var in .env.reference.

    Parameters
    ----------
    keys
        Env var names to date. Omit for all of them.
    """
    return _run_sh("config-version-archaeology.sh", list(keys))


@app.command(name="resolve")
def resolve(version: str) -> int:
    """Rewrite every "Since unreleased" marker to the version being cut.

    Run it before tagging, so the tagged tree already carries the real number.
    Refuses to run if the tag already exists.

    Parameters
    ----------
    version
        The release being cut, e.g. v0.26.4.
    """
    return _run_sh("resolve-unreleased-versions.sh", [version])


app.command(_annotate.run, name="annotate")
app.command(_versionmap.run, name="map")
app.command(_docsgen.run, name="docs")


def main(argv: list[str] | None = None) -> int:
    try:
        return app(argv)
    except UsageError as exc:
        # argparse's parser.error exited 2; the documented contract says 2 is
        # "bad input", and CI distinguishes it from 1 ("drift"), so it stays 2.
        print(f"FAIL: {exc}", file=sys.stderr)
        return 2
