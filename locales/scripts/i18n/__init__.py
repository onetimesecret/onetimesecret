# locales/scripts/i18n/__init__.py

"""Consolidated OneTimeSecret locale tooling.

A single CLI (``i18n``) that wraps the previously separate locale scripts
under ``locales/scripts/``. Shared concerns (paths, JSON key I/O, the SQLite
task database, table rendering) live in this package's top-level modules;
each command group lives under :mod:`i18n.commands`.

Canonical invocation (zero-install, from the repo root)::

    python3 locales/scripts/i18n <group> <subcommand> [options]
"""
