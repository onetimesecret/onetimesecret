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
from unittest import mock

from envref import paths
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


class PackageLocationFallbackTest(unittest.TestCase):
    """The third tier, with the first two taken away.

    Caught in review as an off-by-one: the constant counted hops from this
    file rather than indexing `parents`, so it named the repo's parent. Every
    test and every real invocation had either ENVREF_REPO_ROOT or a git
    checkout to answer first, so the tier that was broken was the only one
    nothing exercised. It is exercised now.
    """

    def setUp(self):
        self.saved = os.environ.pop("ENVREF_REPO_ROOT", None)

    def tearDown(self):
        if self.saved is not None:
            os.environ["ENVREF_REPO_ROOT"] = self.saved

    def test_resolves_from_the_package_location_alone(self):
        with mock.patch.object(paths, "_from_git", return_value=None):
            resolved = paths.repo_root()
        self.assertTrue((resolved / ".env.reference").is_file())
        self.assertTrue((resolved / "etc" / "defaults").is_dir())

    def test_the_constant_indexes_parents_rather_than_counting_hops(self):
        """Pin the arithmetic directly, not just its effect.

        The fallback test above would also pass if the constant were wrong and
        some ancestor happened to look like a checkout. This asserts the index
        lands on the directory that owns this package.
        """
        root = Path(paths.__file__).resolve().parents[paths._PARENTS_TO_ROOT]
        self.assertTrue((root / "tools" / "envref" / "pyproject.toml").is_file())
        self.assertTrue((root / "bin" / "envref").is_file())


class BundledScriptTest(unittest.TestCase):
    def test_unknown_script_is_an_error_not_a_silent_path(self):
        with self.assertRaises(RootNotFound):
            sh_script("no-such-script.sh")
