"""Release classification is a deterministic transform, not a Git operation."""

import os
import subprocess
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from envref.paths import sh_script


class ReleaseEvidenceTest(unittest.TestCase):
    def classify(self, local="", remote="", local_status=0, remote_status=0):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "local.tags").write_text(local)
            (root / "remote.refs").write_text(remote)
            # Tripwire: classification must never acquire its own evidence.
            (root / "git").write_text(
                "#!/bin/sh\necho git-called >&2\nexit 99\n"
            )
            (root / "git").chmod(0o755)
            return subprocess.run(
                [
                    "bash",
                    "-c",
                    'source "$1"; classify_release_tags "$2" "$3" "$4" "$5"',
                    "classify",
                    str(sh_script("release-tag-evidence.sh")),
                    str(local_status),
                    str(remote_status),
                    str(root / "local.tags"),
                    str(root / "remote.refs"),
                ],
                env={"PATH": str(root) + os.pathsep + "/usr/bin:/bin"},
                cwd=root,
                capture_output=True,
                text=True,
                timeout=5,
            )

    def test_unions_and_deduplicates_only_exact_stable_tags(self):
        proc = self.classify(
            local="v0.24.0\nv0.27.0\nv0.27.0-rc1\narchive/v0.28.0\n",
            remote=(
                "abc\trefs/tags/v0.24.0\n"
                "abc\trefs/tags/v0.25.0\n"
                "abc\trefs/tags/v0.25.0^{}\n"
                "abc\trefs/tags/v0.26.0-rc1\n"
                "abc\trefs/heads/v0.29.0\n"
                "abc\trefs/tags/archive/v0.30.0\n"
            ),
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(proc.stdout, "v0.24.0\nv0.25.0\nv0.27.0\n")
        self.assertEqual(proc.stderr, "")

    def test_failed_acquisition_never_turns_partial_output_into_evidence(self):
        for local_status, remote_status in ((1, 0), (0, 1), (0, 124), (1, 1)):
            with self.subTest(local=local_status, remote=remote_status):
                proc = self.classify(
                    "v0.24.0\n",
                    "abc\trefs/tags/v0.25.0\n",
                    local_status,
                    remote_status,
                )
                self.assertEqual(proc.returncode, 1, proc.stderr)
                self.assertEqual(proc.stdout, "")
                self.assertEqual(proc.stderr, "")

    def test_successful_empty_advertisement_does_not_invent_tags(self):
        proc = self.classify()
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(proc.stdout, "")

    def test_local_only_evidence_is_retained_after_successful_query(self):
        proc = self.classify("v0.24.0\n")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(proc.stdout, "v0.24.0\n")

    def test_remote_only_evidence_is_retained_after_successful_query(self):
        proc = self.classify(remote="abc\trefs/tags/v0.24.0\n")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(proc.stdout, "v0.24.0\n")

    def test_malformed_ref_lines_do_not_supply_stable_tags(self):
        proc = self.classify(
            remote="refs/tags/v0.24.0\nabc refs/tags/v0.25.0 extra\n"
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(proc.stdout, "")


if __name__ == "__main__":
    unittest.main()
