"""The command surface, and the wiring behind each name.

ADR-042 makes `bin/envref <subcommand>` the supported way to run any of this,
so the subcommand set is now an interface: dropping or renaming one breaks
callers in CI and in another repository. These tests fail on a rename, which
is the point — a rename should be a deliberate edit here too.
"""

import unittest
from unittest import mock

from envref import annotate, docsgen, versionmap
from envref.cli import app
from envref.paths import RootNotFound, sh_script

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

    def test_no_command_turns_a_missing_checkout_into_a_traceback(self):
        """Every command answers "no checkout here" with an exit code.

        Caught in review: `map` caught only GitFailed, so it was the one
        command on the surface that ended in a traceback where the others
        returned a documented status. The codes differ on purpose — each
        module keeps the contract its own header states, 1 for `map`
        ("unusable input") and 2 for `annotate` ("bad input") — but "an int,
        not a traceback" is the same rule for all of them.
        """
        cases = (
            (versionmap, "_generate", 1),
            (annotate, "repo_root", 2),
        )
        for module, attr, expected in cases:
            with self.subTest(module=module.__name__):
                with mock.patch.object(
                    module, attr, side_effect=RootNotFound("no checkout here")
                ):
                    if module is versionmap:
                        result = module.run()
                    else:
                        result = module.run("/nonexistent/map.tsv")
                self.assertEqual(result, expected)

    def test_help_text_exists_for_every_subcommand(self):
        """A subcommand with no help is undiscoverable through the one door."""
        for name in sorted(EXPECTED):
            with self.subTest(name=name):
                self.assertTrue((app[name].help or "").strip(), f"{name} has no help")
