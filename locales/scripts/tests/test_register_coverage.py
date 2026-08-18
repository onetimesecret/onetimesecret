# locales/scripts/tests/test_register_coverage.py

"""Contract tests for register-coverage.py (the empty-ruleset warning).

The gap this freezes: ``lint_content.py`` scans content for
``register.forbidden_tokens``; when that list is empty it skips every string and
exits 0 with "0 string(s) scanned" -- a pass indistinguishable from a real clean
scan. de (informal/du, 0 tokens, while sibling de_AT has 10) and ar shipped a
whole round with no automated register enforcement and nothing said so.

These checks pin the two properties that make the difference visible:
  1. an empty (or absent) register produces a WARNING, on stderr / as a
     ``::warning::`` annotation;
  2. it does NOT change the exit code -- an empty list is sometimes the correct
     authoring answer (ar), so this must never turn into a surprise red build.
Plus the opt-in ``--fail-on-empty`` escape hatch, so a future burndown gate is a
deliberate flag flip rather than a rewrite.

Zero third-party dependency; no derive, no network, no repo content is read.
Runs two ways:

    python3 -m unittest discover -s locales/scripts/tests
    pytest locales/scripts/tests          # if pytest is installed
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any

# locales/scripts/tests/ -> repo root is three parents up.
ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "locales" / "scripts" / "register-coverage.py"


def _model(register: Any, locale: str = "xx") -> dict[str, Any]:
    return {"_meta": {"locale": locale, "schema_version": "1"}, "register": register}


def _run(model: dict[str, Any], *args: str) -> subprocess.CompletedProcess[str]:
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / f"{model['_meta']['locale']}.json"
        path.write_text(json.dumps(model, ensure_ascii=False), encoding="utf-8")
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--resolved", str(path), *args],
            capture_output=True,
            text=True,
        )


ENFORCING = _model(
    {
        "form": "formal",
        "pronoun": "Sie",
        "forbidden_tokens": [
            {"token": "du", "context": "standalone_word", "severity": "error"},
            {"token": "dein", "context": "standalone_word", "severity": "error"},
        ],
        "exceptions": [],
    },
    locale="de_AT",
)
# The de shape: a real register lock (form/pronoun) with nothing to match on.
EMPTY = _model(
    {"form": "informal", "pronoun": "du", "forbidden_tokens": [], "exceptions": []},
    locale="de",
)


class RegisterCoverage(unittest.TestCase):
    def test_script_present(self) -> None:
        self.assertTrue(SCRIPT.is_file(), f"missing {SCRIPT}")

    def test_enforcing_locale_reports_token_count(self) -> None:
        proc = _run(ENFORCING)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("2 forbidden token(s) enforced", proc.stdout)
        self.assertNotIn("WARNING", proc.stdout + proc.stderr)

    def test_empty_forbidden_tokens_warns(self) -> None:
        proc = _run(EMPTY)
        self.assertIn("WARNING", proc.stderr)
        self.assertIn("EMPTY", proc.stderr)
        # The warning must say what a green lint actually proves.
        self.assertIn("0 strings", proc.stderr)

    def test_empty_forbidden_tokens_does_not_change_exit_code(self) -> None:
        # The whole point of the warning is that it is NOT a gate: an empty
        # register is correct for ar, so this must stay exit 0 by default.
        self.assertEqual(_run(EMPTY).returncode, 0)

    def test_missing_register_block_warns(self) -> None:
        proc = _run(_model(None, locale="en"))
        self.assertEqual(proc.returncode, 0)
        self.assertIn("NO register block", proc.stderr)

    def test_fail_on_empty_is_opt_in(self) -> None:
        self.assertEqual(_run(EMPTY, "--fail-on-empty").returncode, 1)
        self.assertEqual(_run(ENFORCING, "--fail-on-empty").returncode, 0)

    def test_github_format_emits_annotations(self) -> None:
        empty = _run(EMPTY, "--format", "github")
        self.assertIn("::warning::", empty.stdout)
        ok = _run(ENFORCING, "--format", "github")
        self.assertIn("::notice::", ok.stdout)
        self.assertNotIn("::warning::", ok.stdout)

    def test_json_verdict_shape(self) -> None:
        proc = _run(EMPTY, "--json")
        verdict = json.loads(proc.stdout)
        self.assertEqual(verdict["locale"], "de")
        self.assertFalse(verdict["enforcing"])
        self.assertEqual(verdict["forbidden_token_count"], 0)

    def test_unreadable_model_is_a_config_error(self) -> None:
        # Mirrors lint_content.py: usage/config errors exit 2, never a traceback.
        proc = subprocess.run(
            [sys.executable, str(SCRIPT), "--resolved", str(ROOT / "no-such.json")],
            capture_output=True,
            text=True,
        )
        self.assertEqual(proc.returncode, 2)
        self.assertIn("resolved model not found", proc.stderr)

    def test_pronoun_possessive_casing_conflict_warns(self) -> None:
        """The ru shape: `pronoun` is lowercase "вы" while `possessive` is the
        capitalized ["Ваш", ...] family, and rule.ru-register-formal requires
        capitalization in direct address. Nothing in the model encodes that, and
        the lint engine casefolds -- 61 lowercase occurrences shipped past a
        green gate. Warn rather than let the artifact contradict itself."""
        model = _model(
            {
                "form": "formal",
                "pronoun": "вы",
                "possessive": ["Ваш", "Ваша", "Ваше"],
                "forbidden_tokens": [
                    {"token": "ты", "context": "standalone_word", "severity": "error"}
                ],
                "exceptions": [],
            },
            locale="ru",
        )
        proc = _run(model)
        # Still enforcing (the ты-family tokens work); the warning is additive.
        self.assertEqual(proc.returncode, 0)
        self.assertIn("1 forbidden token(s) enforced", proc.stdout)
        self.assertIn("disagree about capitalization", proc.stderr)
        self.assertTrue(json.loads(_run(model, "--json").stdout)["casing_conflict"])

    def test_consistent_casing_does_not_warn(self) -> None:
        model = _model(
            {
                "form": "informal",
                "pronoun": "du",
                "possessive": ["dein", "deine"],
                "forbidden_tokens": [
                    {"token": "Sie", "context": "standalone_word", "severity": "error"}
                ],
                "exceptions": [],
            },
            locale="de",
        )
        proc = _run(model)
        self.assertNotIn("capitalization", proc.stderr)
        self.assertFalse(json.loads(_run(model, "--json").stdout)["casing_conflict"])

    def test_register_spec_prohibitions_counted_as_unenforced(self) -> None:
        """Forward-compatible with the upstream fix. translation-rules v0.1.1
        drops `register_spec` from the emitted model (lib/resolver/model.py
        `_build_register` allowlists fields), so vi's kinship pronouns
        anh/co/chu/bac and ar's dialect markers are invisible to every consumer.
        When that lands, these must read as UNENFORCED policy, not coverage."""
        model = _model(
            {
                "form": "other",
                "pronoun": "bạn",
                "forbidden_tokens": [
                    {"token": "em", "context": "standalone_word", "severity": "error"}
                ],
                "exceptions": [],
                "register_spec": {
                    "forbidden_pronouns": {
                        "tokenized": ["em"],
                        "not_tokenized": ["anh", "cô", "chú", "bác"],
                    }
                },
            },
            locale="vi",
        )
        verdict = json.loads(_run(model, "--json").stdout)
        self.assertEqual(verdict["forbidden_token_count"], 1)
        self.assertEqual(
            sorted(verdict["policy_only_terms"]),
            sorted(["em", "anh", "cô", "chú", "bác"]),
        )
        proc = _run(model)
        self.assertIn("WARNING", proc.stderr)
        self.assertIn("NOT lint-enforced", proc.stderr)


if __name__ == "__main__":
    unittest.main()
