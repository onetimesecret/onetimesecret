"""A CRLF worktree must not change any verdict.

Nothing in `.gitattributes` forces LF on `.env.reference` or
`etc/defaults/*.yaml`, so a checkout made with Git's `core.autocrlf=true` —
the Windows default — puts CRLF in the working tree. That is a supported
state, and the two tools that read markers have to agree about those bytes.

They did not. `annotate.py` handles it deliberately: `read_lines()` splits the
CR off each body before the recognizer is applied and `join_lines()` puts it
back, so a rewrite is a byte no-op. The ratchet's recognizers all anchor on
`[[:blank:]]*$`, and CR is not blank, so every marker became invisible to it:
603 correct markers reported malformed, every key reported unmarked, and a
remediation message telling the author to write the form they had written.

The guard normalises the trailing CR once, on read, so this asserts the whole
script end to end rather than one regex.
"""

import subprocess
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from envref import annotate
from envref.paths import sh_script

FIXTURE = {
    ".env.reference": "KEY_ONE=a  # Since v0.24.0\nKEY_TWO=b  # Since unreleased\nKEY_OLD=c\n",
    "etc/defaults/config.defaults.yaml": "site:\n  mode: x  # Since v0.24.0\n  old: y\n",
}


def build(root: Path, crlf: bool) -> None:
    for relpath, text in FIXTURE.items():
        path = root / relpath
        path.parent.mkdir(parents=True, exist_ok=True)
        data = text.encode("utf-8")
        path.write_bytes(data.replace(b"\n", b"\r\n") if crlf else data)


def run_guard(root: Path) -> subprocess.CompletedProcess:
    # No base ref on a bare fixture, so this exercises the well-formedness and
    # site-extraction rules — which is exactly where the CR broke things.
    return subprocess.run(
        ["bash", str(sh_script("check-config-versions.sh"))],
        cwd=root,
        env={"PATH": "/usr/bin:/bin:/usr/local/bin", "ENVREF_REPO_ROOT": str(root)},
        capture_output=True,
        text=True,
    )


class GuardTest(unittest.TestCase):
    def verdict(self, crlf: bool):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            build(root, crlf=crlf)
            proc = run_guard(root)
        summary = [
            line.strip()
            for line in (proc.stdout + proc.stderr).splitlines()
            if "annotation site" in line or line.startswith(("PASS", "FAIL"))
        ]
        return proc.returncode, summary

    def test_crlf_and_lf_reach_the_same_verdict(self):
        lf_code, lf_summary = self.verdict(crlf=False)
        crlf_code, crlf_summary = self.verdict(crlf=True)
        self.assertEqual(lf_code, 0, f"the LF fixture should pass: {lf_summary}")
        self.assertEqual(
            crlf_code,
            0,
            "a CRLF worktree failed a guard the identical LF worktree passed: "
            f"{crlf_summary}",
        )
        self.assertEqual(crlf_summary, lf_summary)

    def test_the_markers_are_actually_counted_under_crlf(self):
        """`0 marked` is the tell, so passing is not enough on its own.

        Stripping the CR too eagerly, or not extracting at all, would also
        produce a green run over a file the guard had stopped reading.
        """
        _, summary = self.verdict(crlf=True)
        # Three marked lines in FIXTURE, six sites: the three unmarked keys
        # are sites too, which is what makes "marked" the meaningful count.
        self.assertTrue(
            any("3 marked" in line for line in summary),
            f"expected the three markers to be counted, got {summary}",
        )


class AnnotatorTest(unittest.TestCase):
    """The other half of the asymmetry, pinned so it stays symmetric."""

    def test_read_lines_splits_the_cr_off_and_join_restores_it(self):
        with TemporaryDirectory() as tmp:
            path = Path(tmp) / "config.yaml"
            path.write_bytes(b"mode: x  # Since v0.24.0\r\nold: y\r\n")
            bodies, crs = annotate.read_lines(path)
            self.assertTrue(all(not b.endswith("\r") for b in bodies))
            self.assertTrue(annotate.MARKER_RE.search(bodies[0]))
            self.assertEqual(
                annotate.join_lines(bodies, crs).encode("utf-8"),
                path.read_bytes(),
                "join_lines must be a byte no-op",
            )

    def test_a_bare_cr_is_refused_rather_than_silently_stripped(self):
        with TemporaryDirectory() as tmp:
            path = Path(tmp) / "config.yaml"
            path.write_bytes(b"mode: x\rold: y\n")
            with self.assertRaises(annotate.HardError):
                annotate.read_lines(path)
