"""The marker recognizer is spelled five times. This asserts they are one.

docs/development/config-version-annotations.md is normative — it says so, and
it calls its pattern "the only pattern any tool may use". The pattern is then
restated in two Python modules, one shell variable and two awk literals,
because each of those has to work in its own language. Restating is not the
bug; restating and drifting is, and drift here does not crash — it silently
stops recognising markers that are really there, or starts recognising ones
that are not.

So the document is parsed, not paraphrased: every copy is compared against the
text in the fenced block under "The marker".
"""

import re
import unittest
from pathlib import Path

from envref import annotate, docsgen
from envref.paths import repo_root, sh_script

CONTRACT = repo_root() / "docs" / "development" / "config-version-annotations.md"


def documented_recognizer() -> str:
    """The single fenced line under the "The recognizer" sentence."""
    text = CONTRACT.read_text(encoding="utf-8")
    marker = text.index("The recognizer")
    fence = text.index("```", marker)
    end = text.index("```", fence + 3)
    body = text[fence + 3 : end].strip("\n").strip()
    assert body and "\n" not in body, f"expected one line, got {body!r}"
    return body


class DocumentedPatternTest(unittest.TestCase):
    def setUp(self):
        self.documented = documented_recognizer()

    def test_contract_document_is_where_we_think_it_is(self):
        self.assertTrue(CONTRACT.is_file(), f"{CONTRACT} is missing")
        self.assertEqual(
            self.documented,
            r"[ \t]+# Since (v[0-9]+\.[0-9]+\.[0-9]+|unreleased)[ \t]*$",
        )

    def test_annotator_uses_the_documented_pattern(self):
        self.assertEqual(annotate.MARKER_RE.pattern, self.documented)

    def test_docs_generator_uses_the_documented_pattern(self):
        self.assertEqual(docsgen.SINCE_MARKER_RE.pattern, self.documented)

    def test_the_two_python_copies_are_the_same_copy(self):
        self.assertEqual(annotate.MARKER_RE.pattern, docsgen.SINCE_MARKER_RE.pattern)

    def test_awk_literals_use_the_documented_pattern(self):
        """The ratchet's awk walk embeds the pattern twice, verbatim."""
        script = sh_script("check-config-versions.sh").read_text(encoding="utf-8")
        occurrences = script.count(self.documented)
        self.assertGreaterEqual(
            occurrences,
            2,
            f"expected the documented recognizer verbatim in the awk walk, found {occurrences}",
        )

    def test_shell_variable_is_the_documented_pattern_in_posix_classes(self):
        """MARKER_RE is the same pattern with [ \\t] written as [[:blank:]].

        grep -E has no \\t, so the class is the sanctioned substitution. Nothing
        else about the pattern may differ.
        """
        script = sh_script("check-config-versions.sh").read_text(encoding="utf-8")
        m = re.search(r"^MARKER_RE='(?P<pat>.*)'$", script, re.MULTILINE)
        self.assertIsNotNone(m, "MARKER_RE assignment not found")
        self.assertEqual(m.group("pat"), self.documented.replace(r"[ \t]", "[[:blank:]]"))


class RecognizerBehaviourTest(unittest.TestCase):
    """Cases that cost real debugging, kept so they cannot come back."""

    def matches(self, line: str) -> bool:
        return bool(annotate.MARKER_RE.search(line))

    def test_accepts_the_writer_output(self):
        self.assertTrue(self.matches("KEY=value  # Since v0.24.0"))
        self.assertTrue(self.matches("KEY=value  # Since unreleased"))
        self.assertTrue(self.matches("  key: value  # Since v0.26.11"))

    def test_requires_the_leading_blank(self):
        self.assertFalse(self.matches("KEY=value# Since v0.24.0"))

    def test_requires_full_patch_precision(self):
        self.assertFalse(self.matches("KEY=value  # Since v0.24"))

    def test_rejects_trailing_text(self):
        self.assertFalse(self.matches("KEY=value  # Since v0.24.0 (new)"))

    def test_url_fragment_in_a_value_is_not_a_marker_attempt(self):
        """The near-miss recognizer needs the blank too.

        Without it, a value containing `#since` reads as a second marker and
        the one-marker rule rejects a perfectly well-formed line.
        """
        line = "CHANGELOG_URL=https://example.com/changelog#since  # Since v0.24.0"
        self.assertTrue(self.matches(line))
        body = annotate.MARKER_RE.sub("", line)
        self.assertFalse(
            annotate.LOOSE_SINCE_RE.search(body),
            "the URL fragment was mistaken for a near-miss marker",
        )
