"""Repo-root resolution.

Six scripts each answered "which repo" as `<my own directory>/..`. Moving them
into a package changed that answer for all six at once, and a wrong root does
not crash — it reads and rewrites the wrong files. So the resolver is the one
piece of this migration with no prior behaviour to fall back on, and it gets
the most direct tests.
"""

import os
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from envref.paths import RootNotFound, repo_root, sh_script


def make_fake_repo(base: Path) -> Path:
    (base / "etc" / "defaults").mkdir(parents=True)
    (base / ".env.reference").write_text("# fake\n", encoding="utf-8")
    return base


class ExplicitRootTest(unittest.TestCase):
    def test_explicit_root_wins_outright(self):
        """--root is a statement, not a hint: it is not re-validated by shape.

        A caller annotating a copied tree (the annotator supports exactly that)
        would otherwise be overruled by whatever the environment said.
        """
        with TemporaryDirectory() as tmp:
            plain = Path(tmp) / "not-a-repo"
            plain.mkdir()
            os.environ["ENVREF_REPO_ROOT"] = "/nonexistent/elsewhere"
            try:
                self.assertEqual(repo_root(plain), plain.resolve())
            finally:
                del os.environ["ENVREF_REPO_ROOT"]

    def test_explicit_root_that_is_not_a_directory_is_an_error(self):
        with TemporaryDirectory() as tmp:
            missing = Path(tmp) / "nope"
            with self.assertRaises(RootNotFound):
                repo_root(missing)


class EnvironmentRootTest(unittest.TestCase):
    def setUp(self):
        self.saved = os.environ.get("ENVREF_REPO_ROOT")

    def tearDown(self):
        if self.saved is None:
            os.environ.pop("ENVREF_REPO_ROOT", None)
        else:
            os.environ["ENVREF_REPO_ROOT"] = self.saved

    def test_environment_root_is_used_when_it_looks_like_the_repo(self):
        with TemporaryDirectory() as tmp:
            fake = make_fake_repo(Path(tmp) / "repo")
            os.environ["ENVREF_REPO_ROOT"] = str(fake)
            self.assertEqual(repo_root(), fake.resolve())

    def test_environment_root_that_is_not_a_repo_falls_through(self):
        """A stale export must not win over a real checkout.

        It is validated by shape rather than trusted, so `cd` into the repo
        with a leftover ENVREF_REPO_ROOT still resolves correctly.
        """
        with TemporaryDirectory() as tmp:
            empty = Path(tmp) / "empty"
            empty.mkdir()
            os.environ["ENVREF_REPO_ROOT"] = str(empty)
            resolved = repo_root()
            self.assertNotEqual(resolved, empty.resolve())
            self.assertTrue((resolved / ".env.reference").is_file())


class BundledScriptTest(unittest.TestCase):
    def test_unknown_script_is_an_error_not_a_silent_path(self):
        with self.assertRaises(RootNotFound):
            sh_script("no-such-script.sh")
