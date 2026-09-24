"""envref — the config-version annotation tooling for onetimesecret.

The marker contract these modules implement is
`docs/development/config-version-annotations.md`. That document is normative;
this package is one of its readers, and drifting from it is a defect here
rather than a change there.
"""

__all__ = ["UsageError"]


class UsageError(Exception):
    """Arguments that cannot be reconciled, reported as exit 2.

    argparse spelled this `parser.error`, which exits 2 and prints usage. The
    exit code is part of the documented contract ("0 = in place, 1 = drift,
    2 = bad input") and CI reads it, so it survives the move to Cyclopts.
    """
