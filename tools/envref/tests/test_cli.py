"""The command surface, and the wiring behind each name.

ADR-042 makes `bin/envref <subcommand>` the supported way to run any of this,
so the subcommand set is now an interface: dropping or renaming one breaks
callers in CI and in another repository. These tests fail on a rename, which
is the point — a rename should be a deliberate edit here too.
"""

import contextlib
import io
import unittest
from tempfile import TemporaryDirectory
from unittest import mock

from envref import annotate, docsgen, versionmap
from envref import cli
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

    def test_a_malformed_invocation_is_bad_input_not_drift(self):
        """Exit 2, not 1, when the command line itself is wrong.

        Caught in review. Cyclopts handles parse errors before main sees them
        and exits 1 by default, and 1 is "drift" to every caller in this
        family. CI runs `bin/envref check`, so a typo in a workflow flag would
        have been reported as config version drift — a wrong answer from the
        one guard whose whole value is that its failures mean what they say.
        """
        cases = (
            (["resolve"], "required argument missing"),
            (["check", "--nonsense"], "unknown option"),
            (["annotate"], "required argument missing"),
            (["nosuchcommand"], "unknown subcommand"),
        )
        for argv, why in cases:
            with self.subTest(case=why):
                buf = io.StringIO()
                # Cyclopts renders its own error panel; this is about the code.
                with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(buf):
                    result = cli.main(argv)
                self.assertEqual(result, 2, f"{why} reported as drift")

    def test_docs_reports_a_bad_invocation_as_bad_input(self):
        """die() is "cannot run", never "the page drifted".

        Caught in review, one commit after the parse-error fix established the
        same rule: docsgen exited 1 from die(), so a mistyped docs-repo path
        and mutually exclusive flags both claimed the page had drifted. The
        single `return 1` in that module is the only drift it has.
        """
        with TemporaryDirectory() as tmp:
            cases = (
                ([tmp], "docs repo path with no page in it"),
                ([tmp, "--check", "--init"], "mutually exclusive flags"),
            )
            for extra, why in cases:
                with self.subTest(case=why):
                    buf = io.StringIO()
                    with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(buf):
                        with self.assertRaises(SystemExit) as caught:
                            cli.main(["docs", *extra])
                    self.assertEqual(caught.exception.code, 2, f"{why} reported as drift")

    def test_help_still_succeeds(self):
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(buf):
            with self.assertRaises(SystemExit) as caught:
                cli.main(["--help"])
        self.assertEqual(caught.exception.code, 0)

    def test_help_text_exists_for_every_subcommand(self):
        """A subcommand with no help is undiscoverable through the one door."""
        for name in sorted(EXPECTED):
            with self.subTest(name=name):
                self.assertTrue((app[name].help or "").strip(), f"{name} has no help")
