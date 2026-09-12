"""The command surface, and the wiring behind each name.

ADR-042 makes `bin/envref <subcommand>` the supported way to run any of this,
so the subcommand set is now an interface: dropping or renaming one breaks
callers in CI and in another repository. These tests fail on a rename, which
is the point — a rename should be a deliberate edit here too.
"""

import unittest

from envref import annotate, docsgen, versionmap
from envref.cli import app
from envref.paths import sh_script

EXPECTED = {"annotate", "archaeology", "check", "docs", "map", "resolve"}


class CommandSurfaceTest(unittest.TestCase):
    def test_exactly_the_documented_subcommands_are_registered(self):
        registered = {name for name in app if not name.startswith("-")}
        self.assertEqual(registered, EXPECTED)

    def test_every_subcommand_resolves(self):
        for name in sorted(EXPECTED):
            with self.subTest(name=name):
                self.assertIsNotNone(app[name])

    def test_python_subcommands_are_the_modules_own_entry_points(self):
        """Registered straight off `run`, so the flags have one definition."""
        self.assertIs(app["annotate"].default_command, annotate.run)
        self.assertIs(app["map"].default_command, versionmap.run)
        self.assertIs(app["docs"].default_command, docsgen.run)

    def test_shell_subcommands_have_their_implementations_bundled(self):
        for script in (
            "check-config-versions.sh",
            "config-version-archaeology.sh",
            "resolve-unreleased-versions.sh",
        ):
            with self.subTest(script=script):
                self.assertTrue(sh_script(script).is_file())

    def test_help_text_exists_for_every_subcommand(self):
        """A subcommand with no help is undiscoverable through the one door."""
        for name in sorted(EXPECTED):
            with self.subTest(name=name):
                self.assertTrue((app[name].help or "").strip(), f"{name} has no help")
