"""Rule 2 freezes a marker only once its version has a stable release tag.

A concrete `# Since vX.Y.Z` on the base branch used to be frozen whether or
not vX.Y.Z was ever released. A guessed future version that reached the base
could then not be corrected: the release that really shipped the key failed
the check when it re-dated the marker.

The rule uses origin's full tag advertisement plus known local tags. These
cases pin partial checkouts, genuinely untagged guesses, and conservative
fallback when the advertisement cannot be read. The fixture origin is a local
bare repository: these tests never contact an external service.
"""

import os
import shlex
import shutil
import signal
import subprocess
import time
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


def fixture(
    root: Path,
    tags: tuple[str, ...],
    remote_tags: tuple[str, ...] | None = None,
    origin_available: bool = True,
) -> None:
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

    origin = root / "origin.git"
    git(root, "remote", "add", "origin", str(origin))
    if origin_available:
        git(root, "init", "-q", "--bare", str(origin))
        git(root, "push", "-q", "origin", "main")
        for tag in tags if remote_tags is None else remote_tags:
            git(origin, "-c", "tag.gpgsign=false", "tag", tag, "main")


def edit(root: Path, relpath: str, old: str, new: str) -> None:
    path = root / relpath
    text = path.read_text(encoding="utf-8")
    assert old in text, f"{old!r} not in {relpath}"
    path.write_text(text.replace(old, new), encoding="utf-8")


def run_check(
    root: Path,
    require_base: bool = False,
    print_sites: bool = False,
    extra_env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess:
    env = {
        **GIT_ENV,
        "HOME": str(root),
        "ENVREF_REPO_ROOT": str(root),
        "CONFIG_VERSION_BASE_REF": "main",
        **(extra_env or {}),
    }
    if require_base:
        env["CONFIG_VERSION_REQUIRE_BASE"] = "1"
    return subprocess.run(
        ["bash", str(sh_script("check-config-versions.sh"))]
        + (["--print-sites"] if print_sites else []),
        cwd=root,
        env=env,
        capture_output=True,
        text=True,
        timeout=10,
    )


def query_shim(
    root: Path, body: str, watchdog_sleep: str | None = None
) -> dict[str, str]:
    """Intercept only ls-remote; all repository operations use real Git."""
    real_git = shutil.which("git", path=GIT_ENV["PATH"])
    real_sleep = shutil.which("sleep", path=GIT_ENV["PATH"])
    assert real_git and real_sleep
    bindir = root / "query-bin"
    bindir.mkdir()
    shim = bindir / "git"
    shim.write_text(
        '#!/bin/sh\nif [ "$1" = ls-remote ]; then\n'
        '  printf "query\\n" >> "$ENVREF_REPO_ROOT/query.calls"\n'
        '  printf "%s\\n" "$$" > "$ENVREF_REPO_ROOT/query.pid"\n'
        + body
        + "\nfi\nexec "
        + shlex.quote(real_git)
        + ' "$@"\n',
        encoding="utf-8",
    )
    shim.chmod(0o755)
    if watchdog_sleep is not None:
        shim = bindir / "sleep"
        shim.write_text(
            '#!/bin/sh\nif [ "$1" = 15 ]; then\n'
            '  printf "%s\\n" "$$" > "$ENVREF_REPO_ROOT/watchdog-sleep.pid"\n'
            + "  exec "
            + shlex.quote(real_sleep)
            + " "
            + shlex.quote(watchdog_sleep)
            + "\nfi\nexec "
            + shlex.quote(real_sleep)
            + ' "$@"\n',
            encoding="utf-8",
        )
        shim.chmod(0o755)
    return {"PATH": str(bindir) + ":" + GIT_ENV["PATH"]}


class UntaggedMarkerTest(unittest.TestCase):
    def check(
        self,
        edits,
        tags=("v0.24.0",),
        require_base=True,
        remote_tags=None,
        origin_available=True,
    ):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            fixture(root, tags, remote_tags, origin_available)
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
        proc = self.check(
            [(ENV_FILE, "KEY_SHIPPED=a  # Since v0.24.0", "KEY_SHIPPED=a")]
        )
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
        self.assertIn("frozen conservatively", proc.stderr)
        self.assertIn("git fetch --tags origin", proc.stderr)
        self.assertNotIn("is not frozen", proc.stderr)
        self.assertIn("NOTE: no stable release tags", proc.stdout)

    def test_no_visible_tags_locally_is_reported_on_a_passing_run(self):
        proc = self.check([], tags=(), require_base=False)
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertIn("no stable release tags", proc.stdout)
        self.assertIn("frozen conservatively", proc.stdout)
        self.assertIn("git fetch --tags origin", proc.stdout)

    def test_partial_local_tags_do_not_unfreeze_a_shipped_marker(self):
        for relpath in (ENV_FILE, YAML_FILE):
            for require_base in (False, True):
                with self.subTest(relpath=relpath, require_base=require_base):
                    proc = self.check(
                        [(relpath, "# Since v0.24.0", "# Since unreleased")],
                        tags=("v0.25.0",),
                        remote_tags=("v0.24.0", "v0.25.0"),
                        require_base=require_base,
                    )
                    self.assertEqual(
                        proc.returncode, 1, proc.stdout + proc.stderr
                    )
                    self.assertIn("Shipped markers are immutable", proc.stderr)
                    self.assertIn(
                        "KEY_SHIPPED"
                        if relpath == ENV_FILE
                        else "site.shipped",
                        proc.stderr,
                    )
                    self.assertNotIn(
                        "frozen conservatively", proc.stdout + proc.stderr
                    )

    def test_partial_local_tags_still_allow_a_genuinely_untagged_guess(self):
        proc = self.check(
            [
                (ENV_FILE, "# Since v0.27.0", "# Since unreleased"),
                (YAML_FILE, "# Since v0.27.0", "# Since v0.26.14"),
            ],
            tags=("v0.25.0",),
            remote_tags=("v0.24.0", "v0.25.0"),
        )
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)

    def test_remote_tags_are_sufficient_without_local_tags(self):
        proc = self.check(
            [(ENV_FILE, "# Since v0.27.0", "# Since v0.26.14")],
            tags=(),
            remote_tags=("v0.24.0",),
        )
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        proc = self.check(
            [(ENV_FILE, "# Since v0.24.0", "# Since unreleased")],
            tags=(),
            remote_tags=("v0.24.0",),
        )
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        self.assertIn("KEY_SHIPPED", proc.stderr)

    def test_a_tag_visible_only_on_origin_freezes_a_guessed_marker(self):
        proc = self.check(
            [(YAML_FILE, "# Since v0.27.0", "# Since v0.26.14")],
            remote_tags=("v0.24.0", "v0.27.0"),
        )
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        self.assertIn("site.guessed", proc.stderr)

    def test_an_unpushed_local_tag_still_freezes_its_marker(self):
        proc = self.check(
            [(ENV_FILE, "# Since v0.27.0", "# Since v0.26.14")],
            tags=("v0.24.0", "v0.27.0"),
            remote_tags=("v0.24.0",),
        )
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        self.assertIn("KEY_GUESSED", proc.stderr)

    def test_remote_prerelease_and_archive_tags_do_not_freeze_a_guess(self):
        proc = self.check(
            [(ENV_FILE, "# Since v0.27.0", "# Since v0.26.14")],
            remote_tags=("v0.24.0", "v0.27.0-rc1", "archive/v0.27.0"),
        )
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)

    def test_unavailable_origin_fails_strict_mode_even_with_local_tags(self):
        proc = self.check([], origin_available=False)
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        self.assertIn(
            "cannot list stable release tags from origin", proc.stderr
        )
        self.assertIn("CONFIG_VERSION_REQUIRE_BASE", proc.stderr)
        self.assertIn("git ls-remote --tags --refs origin", proc.stderr)
        self.assertNotIn("PASS:", proc.stdout)

    def test_unavailable_origin_locally_freezes_guesses_and_reports_fallback(
        self,
    ):
        for tags in ((), ("v0.24.0",)):
            with self.subTest(tags=tags):
                proc = self.check(
                    [(ENV_FILE, "# Since v0.27.0", "# Since v0.26.14")],
                    tags=tags,
                    origin_available=False,
                    require_base=False,
                )
                self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
                self.assertIn("KEY_GUESSED", proc.stderr)
                self.assertIn("frozen conservatively", proc.stderr)
                self.assertIn("git fetch --tags origin", proc.stderr)
                self.assertNotIn("is not frozen", proc.stderr)
                self.assertNotIn("Shipped markers are immutable", proc.stderr)
                self.assertIn(
                    "NOTE: cannot list stable release tags from origin",
                    proc.stdout,
                )

    def test_unavailable_origin_locally_reports_fallback_on_an_unchanged_tree(
        self,
    ):
        proc = self.check([], origin_available=False, require_base=False)
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertIn(
            "NOTE: cannot list stable release tags from origin", proc.stdout
        )
        self.assertIn("frozen conservatively", proc.stdout)
        self.assertIn("git fetch --tags origin", proc.stdout)

    def test_print_sites_does_not_require_tag_evidence(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            fixture(root, tags=(), origin_available=False)
            env = query_shim(root, "exit 99")
            proc = run_check(
                root, require_base=True, print_sites=True, extra_env=env
            )
            self.assertFalse(
                (root / "query.calls").exists(), "--print-sites queried tags"
            )
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertIn("KEY_GUESSED v0.27.0", proc.stdout)
        self.assertNotIn("NOTE:", proc.stdout)
        self.assertEqual(proc.stderr, "")


class TagQueryTest(unittest.TestCase):
    def assert_process_stopped(self, pid_file: Path):
        pid = int(pid_file.read_text())
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            proc = subprocess.run(
                ["ps", "-o", "stat=", "-p", str(pid)],
                capture_output=True,
                text=True,
                timeout=2,
            )
            state = proc.stdout.strip()
            # An orphan may briefly remain as a zombie until init reaps it.
            if not state or state.startswith("Z"):
                return
            time.sleep(0.01)
        self.fail(
            f"process {pid} from {pid_file.name} is still running: {state}"
        )

    def cleanup_processes(self, root: Path):
        # Bound even a regression against an implementation with no deadline.
        for name in ("query.pid", "transport.pid", "watchdog-sleep.pid"):
            path = root / name
            if path.exists():
                try:
                    os.kill(int(path.read_text()), signal.SIGKILL)
                except ProcessLookupError:
                    pass

    def test_stalled_query_is_bounded_and_its_transport_is_killed(self):
        for require_base in (False, True):
            with (
                self.subTest(require_base=require_base),
                TemporaryDirectory() as tmp,
            ):
                root = Path(tmp)
                fixture(root, tags=("v0.24.0",))
                edit(root, ENV_FILE, "# Since v0.27.0", "# Since unreleased")
                env = query_shim(
                    root,
                    'printf "%040d\\trefs/tags/v0.24.0\\n" 0\n'
                    "trap '' TERM\n"
                    'sleep 60 &\nprintf "%s\\n" "$!" > "$ENVREF_REPO_ROOT/transport.pid"\n'
                    "wait",
                    watchdog_sleep="1",
                )
                try:
                    start = time.monotonic()
                    proc = run_check(
                        root, require_base=require_base, extra_env=env
                    )
                    self.assertLess(time.monotonic() - start, 5)
                    self.assertEqual(
                        proc.returncode, 1, proc.stdout + proc.stderr
                    )
                    self.assertIn(
                        "15-second deadline", proc.stdout + proc.stderr
                    )
                    if require_base:
                        self.assertIn(
                            "CONFIG_VERSION_REQUIRE_BASE", proc.stderr
                        )
                    else:
                        self.assertIn("KEY_GUESSED", proc.stderr)
                        self.assertIn("frozen conservatively", proc.stderr)
                        self.assertIn("NOTE:", proc.stdout)
                    self.assert_process_stopped(root / "query.pid")
                    self.assert_process_stopped(root / "transport.pid")
                finally:
                    self.cleanup_processes(root)

    def test_successful_query_cleans_up_the_watchdog_sleep(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            fixture(root, tags=("v0.24.0",))
            env = query_shim(
                root,
                'while ! test -s "$ENVREF_REPO_ROOT/watchdog-sleep.pid"; do sleep 0.01; done\n'
                'printf "%040d\\trefs/tags/v0.24.0\\n" 0\nexit 0',
                watchdog_sleep="60",
            )
            try:
                proc = run_check(root, require_base=True, extra_env=env)
                self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
                self.assert_process_stopped(root / "watchdog-sleep.pid")
            finally:
                self.cleanup_processes(root)

    def test_failed_query_discards_partial_stdout(self):
        for require_base in (False, True):
            with (
                self.subTest(require_base=require_base),
                TemporaryDirectory() as tmp,
            ):
                root = Path(tmp)
                fixture(root, tags=("v0.24.0",))
                edit(root, ENV_FILE, "# Since v0.27.0", "# Since unreleased")
                env = query_shim(
                    root, 'printf "%040d\\trefs/tags/v0.24.0\\n" 0\nexit 1'
                )
                proc = run_check(root, require_base=require_base, extra_env=env)
                self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
                self.assertIn(
                    "cannot list stable release tags from origin",
                    proc.stdout + proc.stderr,
                )
                if not require_base:
                    self.assertIn("KEY_GUESSED", proc.stderr)
                    self.assertIn("frozen conservatively", proc.stderr)

    def test_credential_prompts_are_disabled_without_replacing_ssh_commands(
        self,
    ):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            fixture(root, tags=("v0.24.0",))
            env = query_shim(
                root,
                'printf "%s\\n" "$GIT_TERMINAL_PROMPT" "$GIT_ASKPASS" '
                '"$SSH_ASKPASS" "$SSH_ASKPASS_REQUIRE" "$GIT_SSH_COMMAND" "$GIT_SSH" '
                '> "$ENVREF_REPO_ROOT/query.env"\nexit 1',
            )
            env.update(
                {
                    "GIT_SSH_COMMAND": "configured-ssh -o ProxyCommand=proxy",
                    "GIT_SSH": "configured-wrapper",
                }
            )
            proc = run_check(root, require_base=True, extra_env=env)
            self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
            self.assertEqual(
                (root / "query.env").read_text().splitlines(),
                [
                    "0",
                    "/usr/bin/false",
                    "/usr/bin/false",
                    "force",
                    env["GIT_SSH_COMMAND"],
                    env["GIT_SSH"],
                ],
            )

    def test_an_annotated_remote_tag_freezes_its_marker(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            fixture(root, tags=("v0.24.0",))
            git(
                root / "origin.git",
                "-c",
                "user.name=t",
                "-c",
                "user.email=t@example.com",
                "-c",
                "tag.gpgsign=false",
                "tag",
                "-a",
                "-m",
                "release",
                "v0.27.0",
                "main",
            )
            edit(root, YAML_FILE, "# Since v0.27.0", "# Since unreleased")
            proc = run_check(root, require_base=True)
            self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
            self.assertIn("site.guessed", proc.stderr)
            self.assertIn("Shipped markers are immutable", proc.stderr)


if __name__ == "__main__":
    unittest.main()
