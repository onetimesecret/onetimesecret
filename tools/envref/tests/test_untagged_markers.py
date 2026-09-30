"""Rule 2 freezes a marker only once its version has a stable release tag.

A concrete `# Since vX.Y.Z` on the base branch used to be frozen whether or
not vX.Y.Z was ever released. A guessed future version that reached the base
could then not be corrected: the release that really shipped the key failed
the check when it re-dated the marker.

The rule now reads the tags. These cases pin the three outcomes: a marker
naming an untagged version can change, a marker naming a tagged version
cannot, and a run that sees no stable tags fails under
CONFIG_VERSION_REQUIRE_BASE instead of treating every marker as editable.
"""

import subprocess
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from envref.paths import sh_script

ENV_FILE = ".env.reference"
YAML_FILE = "etc/defaults/config.defaults.yaml"

# v0.24.0 is tagged in the fixture; v0.27.0 never is.
BASE = {
    ENV_FILE: "KEY_SHIPPED=a  # Since v0.24.0\nKEY_GUESSED=b  # Since v0.27.0\nKEY_OLD=c\n",
    YAML_FILE: "site:\n  shipped: x  # Since v0.24.0\n  guessed: y  # Since v0.27.0\n  old: z\n",
}

GIT_ENV = {"PATH": "/usr/bin:/bin:/usr/local/bin", "GIT_CONFIG_NOSYSTEM": "1"}


def git(root: Path, *args: str) -> None:
    subprocess.run(
        ["git", *args],
        cwd=root,
        env={**GIT_ENV, "HOME": str(root)},
        check=True,
        capture_output=True,
    )


def fixture(root: Path, tags: tuple[str, ...]) -> None:
    for relpath, text in BASE.items():
        path = root / relpath
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
    git(root, "init", "-q", "-b", "main", ".")
    git(root, "config", "user.email", "t@example.com")
    git(root, "config", "user.name", "t")
    git(root, "config", "commit.gpgsign", "false")
    git(root, "config", "tag.gpgsign", "false")
    git(root, "add", "-A")
    git(root, "commit", "-qm", "fixture")
    for tag in tags:
        git(root, "tag", tag)


def edit(root: Path, relpath: str, old: str, new: str) -> None:
    path = root / relpath
    text = path.read_text(encoding="utf-8")
    assert old in text, f"{old!r} not in {relpath}"
    path.write_text(text.replace(old, new), encoding="utf-8")


def run_check(root: Path, require_base: bool = False) -> subprocess.CompletedProcess:
    env = {
        **GIT_ENV,
        "HOME": str(root),
        "ENVREF_REPO_ROOT": str(root),
        "CONFIG_VERSION_BASE_REF": "main",
    }
    if require_base:
        env["CONFIG_VERSION_REQUIRE_BASE"] = "1"
    return subprocess.run(
        ["bash", str(sh_script("check-config-versions.sh"))],
        cwd=root,
        env=env,
        capture_output=True,
        text=True,
    )


class UntaggedMarkerTest(unittest.TestCase):
    def check(self, edits, tags=("v0.24.0",), require_base=True):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            fixture(root, tags)
            for relpath, old, new in edits:
                edit(root, relpath, old, new)
            return run_check(root, require_base=require_base)

    def test_an_unchanged_tree_passes(self):
        proc = self.check([])
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)

    def test_an_untagged_env_marker_can_be_redated(self):
        proc = self.check([(ENV_FILE, "# Since v0.27.0", "# Since v0.26.14")])
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)

    def test_an_untagged_yaml_marker_can_be_redated(self):
        proc = self.check([(YAML_FILE, "# Since v0.27.0", "# Since v0.26.14")])
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)

    def test_an_untagged_marker_can_return_to_unreleased(self):
        proc = self.check(
            [
                (ENV_FILE, "# Since v0.27.0", "# Since unreleased"),
                (YAML_FILE, "# Since v0.27.0", "# Since unreleased"),
            ]
        )
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)

    def test_a_tagged_env_marker_cannot_change(self):
        proc = self.check([(ENV_FILE, "# Since v0.24.0", "# Since v0.24.1")])
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        self.assertIn("KEY_SHIPPED", proc.stderr)
        self.assertNotIn("KEY_GUESSED", proc.stderr)

    def test_a_tagged_yaml_marker_cannot_change(self):
        proc = self.check([(YAML_FILE, "# Since v0.24.0", "# Since v0.24.1")])
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        self.assertIn("site.shipped", proc.stderr)
        self.assertNotIn("site.guessed", proc.stderr)

    def test_a_tagged_marker_cannot_be_removed(self):
        proc = self.check([(ENV_FILE, "KEY_SHIPPED=a  # Since v0.24.0", "KEY_SHIPPED=a")])
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        self.assertIn("KEY_SHIPPED", proc.stderr)

    def test_a_marker_is_frozen_once_its_tag_exists(self):
        proc = self.check(
            [(ENV_FILE, "# Since v0.27.0", "# Since v0.26.14")],
            tags=("v0.24.0", "v0.27.0"),
        )
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        self.assertIn("KEY_GUESSED", proc.stderr)

    def test_a_prerelease_tag_does_not_freeze_the_marker(self):
        proc = self.check(
            [(ENV_FILE, "# Since v0.27.0", "# Since v0.26.14")],
            tags=("v0.24.0", "v0.27.0-rc1"),
        )
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)

    def test_no_visible_tags_fails_when_the_base_is_required(self):
        proc = self.check([], tags=())
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        self.assertIn("no stable release tags", proc.stderr)

    def test_only_prerelease_tags_counts_as_no_visible_tags(self):
        proc = self.check([], tags=("v0.27.0-rc1",))
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        self.assertIn("no stable release tags", proc.stderr)

    def test_no_visible_tags_locally_freezes_every_concrete_marker(self):
        """Without tags the rule cannot tell a release from a guess, so the
        local fallback keeps the earlier behaviour rather than freeing all."""
        proc = self.check(
            [(ENV_FILE, "# Since v0.27.0", "# Since v0.26.14")],
            tags=(),
            require_base=False,
        )
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        self.assertIn("KEY_GUESSED", proc.stderr)

    def test_no_visible_tags_locally_is_reported_on_a_passing_run(self):
        proc = self.check([], tags=(), require_base=False)
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertIn("no stable release tags", proc.stdout)


if __name__ == "__main__":
    unittest.main()
