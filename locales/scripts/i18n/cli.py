"""Top-level CLI: argument parsing and dispatch.

Each command group registers its own subparser tree via ``register()``.
Handlers attach themselves with ``set_defaults(func=...)`` and return a
process exit code.
"""

from __future__ import annotations

import argparse
from typing import Optional, Sequence

from .commands import content, store, tasks, validate


def build_parser() -> argparse.ArgumentParser:
    """Build the top-level argument parser with all command groups."""
    p = argparse.ArgumentParser(
        prog="i18n",
        description="OneTimeSecret locale tooling.",
    )
    sub = p.add_subparsers(dest="group", required=True)
    content.register(sub)
    tasks.register(sub)
    store.register(sub)
    validate.register(sub)
    return p


def main(argv: Optional[Sequence[str]] = None) -> int:
    """CLI entry point. Returns a process exit code."""
    args = build_parser().parse_args(argv)
    return args.func(args) or 0
