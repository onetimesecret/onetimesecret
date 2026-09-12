"""Locating the repository these tools read and rewrite.

Every subcommand operates on files in the onetimesecret checkout, so "which
repo" belongs to the tool rather than to any one command. Before ADR-042 each
of the six scripts answered it alone, as `<its own directory>/..`, which is
exactly why moving them into a package would otherwise have broken all six at
once, and silently: a wrong root does not crash, it reads the wrong files.

Resolution order, most explicit first:

1. ``ENVREF_REPO_ROOT``. ``bin/envref`` finds the root once and exports it, so
   the Python modules and the bundled shell scripts agree by construction
   instead of by three more copies of the same walk.
2. ``git rev-parse --show-toplevel``. Every subcommand derives versions from
   git history, so a real checkout is already a hard requirement here; this is
   never the weaker answer.
3. This file's own location. Correct only for the supported arrangement — the
   package living inside the repo it documents — and it is the last resort
   because it is the one that can be quietly wrong.
"""

import os
import subprocess
from pathlib import Path

# src/envref/paths.py -> src/envref -> src -> envref -> tools -> repo root
_PARENTS_TO_ROOT = 5


class RootNotFound(RuntimeError):
    """No candidate resolved to a directory that looks like the repo."""


def _looks_like_repo(path: Path) -> bool:
    # .env.reference is the artifact this tool exists to maintain, and
    # etc/defaults/ is the other half of its subject. Requiring both keeps a
    # stray parent directory from passing as the repo.
    return (path / ".env.reference").is_file() and (path / "etc" / "defaults").is_dir()


def _from_git() -> Path | None:
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return None
    return Path(out) if out else None


def repo_root(explicit: str | os.PathLike | None = None) -> Path:
    """Return the repository root, or raise RootNotFound.

    `explicit` wins outright when given: a caller passing --root has said
    which tree it means, and second-guessing that would make --root advisory.
    """
    if explicit is not None:
        root = Path(explicit).resolve()
        if not root.is_dir():
            raise RootNotFound(f"{root} is not a directory")
        return root

    candidates = []
    env = os.environ.get("ENVREF_REPO_ROOT")
    if env:
        candidates.append(Path(env))
    from_git = _from_git()
    if from_git is not None:
        candidates.append(from_git)
    candidates.append(Path(__file__).resolve().parents[_PARENTS_TO_ROOT])

    for candidate in candidates:
        resolved = candidate.resolve()
        if _looks_like_repo(resolved):
            return resolved

    tried = ", ".join(str(c) for c in candidates) or "(nothing)"
    raise RootNotFound(
        "cannot locate the onetimesecret checkout. Tried: "
        f"{tried}. Set ENVREF_REPO_ROOT, or run bin/envref from inside the repo."
    )


def sh_script(name: str) -> Path:
    """Absolute path to a bundled shell implementation."""
    path = Path(__file__).resolve().parent / "sh" / name
    if not path.is_file():
        raise RootNotFound(f"bundled script {name} is missing from {path.parent}")
    return path
