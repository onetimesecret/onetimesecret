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
import subprocess
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


class NearMissRecognizerTest(unittest.TestCase):
    """The two near-miss hunters must agree, at both ends of the pattern.

    The contract document requires it, and they have now diverged once at each
    end. The leading blank was the first (a URL fragment read as a marker
    attempt); the trailing boundary was the second, and worse: the shell
    required a blank or end-of-line where the annotator used Python's \b, so
    `# Since:` was a near-miss to one tool and invisible to the other. A
    marker is hand-written wherever the contract says to write one, so a stray
    colon shipped two contradictory version claims on one line past the whole
    ratchet.

    The shell pattern is exercised through grep rather than translated, so
    this compares behaviour rather than two readings of a regex dialect.
    """

    CASES = (
        ("KEY=value  # Since v0.24.0", True, "the well-formed marker"),
        ("KEY=value  # Since: v0.24.0", True, "colon — the reported gap"),
        ("KEY=value  # Since= v0.24.0", True, "other punctuation"),
        ("KEY=value  # since v0.24.0", True, "lowercase typo, the point of the hunt"),
        ("KEY=value  # Since", True, "end of line"),
        ("KEY=value  # Sincerely, the author", False, "a word that starts with Since"),
        ("KEY=value  #since2020", False, "a digit continues the word"),
        (
            "CHANGELOG=https://example.com/c#since  # Since v0.24.0",
            True,
            "URL fragment plus a real marker: matches once, not twice",
        ),
    )

    def setUp(self):
        script = sh_script("check-config-versions.sh").read_text(encoding="utf-8")
        m = re.search(r"^MARKER_LOOSE_RE='(?P<pat>.*)'$", script, re.MULTILINE)
        self.assertIsNotNone(m, "MARKER_LOOSE_RE assignment not found")
        self.shell_pattern = m.group("pat")

    def shell_matches(self, line: str) -> bool:
        return (
            subprocess.run(
                ["grep", "-qE", self.shell_pattern], input=line, text=True
            ).returncode
            == 0
        )

    def test_both_spellings_agree_on_every_case(self):
        for line, expected, why in self.CASES:
            with self.subTest(case=why):
                shell = self.shell_matches(line)
                python = bool(annotate.LOOSE_SINCE_RE.search(line))
                self.assertEqual(shell, python, f"the two hunters disagree: {why}")
                self.assertEqual(shell, expected, why)

    def test_a_url_fragment_still_counts_once(self):
        """The leading-blank fix must survive the trailing-boundary widening.

        Counting, not matching: the one-marker rule rejects a line whose
        recognizer fires twice, so a fragment that merely *matches* somewhere
        is not the failure — a second count is.
        """
        line = "CHANGELOG=https://example.com/c#since  # Since v0.24.0"
        out = subprocess.run(
            ["grep", "-oE", self.shell_pattern], input=line, text=True, capture_output=True
        ).stdout
        self.assertEqual(len(out.splitlines()), 1)
        self.assertEqual(len(annotate.LOOSE_SINCE_RE.findall(line)), 1)

    def test_two_claims_on_one_line_count_twice(self):
        line = "    secure: true  # Since: v0.24.0  # Since v0.26.0"
        out = subprocess.run(
            ["grep", "-oE", self.shell_pattern], input=line, text=True, capture_output=True
        ).stdout
        self.assertEqual(len(out.splitlines()), 2, "the one-marker rule would not fire")
        self.assertEqual(len(annotate.LOOSE_SINCE_RE.findall(line)), 2)


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
