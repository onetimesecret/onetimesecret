# locales/scripts/tests/test_derive_governance.py

"""Contract tests for on-demand governance derive (no-vendor model, ADR-005).

``derive-governance.sh`` derives translation governance locally (and for
agents) at the SAME canonical translation-rules pin the CI derive gates use.
That pin lives in the workflow files as ``TRANSLATION_RULES_REF``.

This suite freezes the contract between the gates and the script so the failure
that motivated it cannot silently recur: the script once read a retired
``PINNED_RULES_REF`` field, and when the gate renamed it to
``TRANSLATION_RULES_REF`` nothing caught the break -- every invocation aborted,
and no test exercised the script. These checks turn a future rename/move/drift
of the pin into a red test instead of a runtime failure.

Zero third-party dependency (the resolver toolchain is not needed -- nothing
here clones translation-rules or derives). Runs two ways:

    python3 -m unittest discover -s locales/scripts/tests
    pytest locales/scripts/tests          # if pytest is installed
"""

from __future__ import annotations

import os
import re
import subprocess
import unittest
from pathlib import Path

# locales/scripts/tests/ -> repo root is three parents up.
ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "locales" / "scripts" / "derive-governance.sh"
GATES = (
    ROOT / ".github" / "workflows" / "resolved-derive-gate.yml",
    ROOT / ".github" / "workflows" / "validate-register.yml",
)

# A 40-hex commit SHA or a vX.Y.Z release tag -- the two shapes the gates and the
# script both validate (kept in lockstep with the regex in derive-governance.sh).
REF_SHAPE = re.compile(r"^([0-9a-fA-F]{40}|v[0-9]+\.[0-9]+\.[0-9]+)$")
# Optional surrounding quotes tolerated, matching the Renovate customManager that
# bumps this field (.github/renovate.json5).
FIELD_RE = re.compile(
    r"""TRANSLATION_RULES_REF:\s*["']?(v[0-9]+\.[0-9]+\.[0-9]+|[0-9a-f]{40})"""
)


def _ref_in(path: Path) -> str:
    m = FIELD_RE.search(path.read_text(encoding="utf-8"))
    return m.group(1) if m else ""


class DeriveGovernanceContract(unittest.TestCase):
    def test_script_present(self) -> None:
        self.assertTrue(SCRIPT.is_file(), f"missing {SCRIPT}")

    def test_each_gate_declares_a_shape_valid_pin(self) -> None:
        for gate in GATES:
            self.assertTrue(gate.is_file(), f"missing gate {gate}")
            ref = _ref_in(gate)
            self.assertRegex(
                ref,
                REF_SHAPE,
                msg=(
                    f"{gate.name}: TRANSLATION_RULES_REF missing or malformed "
                    f"(got {ref!r}; want a 40-hex SHA or vX.Y.Z)"
                ),
            )

    def test_single_canonical_pin_across_gates(self) -> None:
        # ADR-004/#38: consumers carry ONE canonical pin. The two derive gates
        # must agree -- the original defect #38 fixed was two gates at two SHAs.
        refs = {g.name: _ref_in(g) for g in GATES}
        self.assertEqual(
            len(set(refs.values())),
            1,
            msg=f"derive gates must share one canonical pin (#38); got {refs}",
        )

    def test_script_reads_the_gate_pin(self) -> None:
        # Drives the REAL script, offline: --print-ref reads + shape-validates the
        # pin from the gate and exits before any clone/derive. This is the check
        # that would have failed when the pin field was renamed.
        proc = subprocess.run(
            ["bash", str(SCRIPT), "--print-ref"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=30,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(proc.stdout.strip(), _ref_in(GATES[0]))

    def test_rules_ref_override_is_honored(self) -> None:
        # RULES_REF overrides the gate default (parity with the gate's per-run
        # dispatch/variable override) and is still shape-validated.
        proc = subprocess.run(
            ["bash", str(SCRIPT), "--print-ref"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=30,
            env={**os.environ, "RULES_REF": "v9.9.9"},
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(proc.stdout.strip(), "v9.9.9")

    def test_malformed_rules_ref_is_rejected(self) -> None:
        proc = subprocess.run(
            ["bash", str(SCRIPT), "--print-ref"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=30,
            env={**os.environ, "RULES_REF": "not-a-ref"},
        )
        self.assertNotEqual(proc.returncode, 0, "malformed RULES_REF must fail")
        self.assertIn("invalid translation-rules ref", proc.stderr)


if __name__ == "__main__":
    unittest.main()
