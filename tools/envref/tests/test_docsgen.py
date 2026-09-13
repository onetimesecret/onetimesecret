"""The header of .env.reference, and what reaches the published page.

The generated page is assembled from two halves of one decision: the marker
legend is *lifted* out of the header and rendered as prose, and that same
paragraph is *dropped* from the fenced preamble so it is not said twice. When
those were two separate substring tests they differed in arity — the lift took
the first paragraph mentioning `# Since`, the drop removed every one — and any
later paragraph that merely mentioned the marker was emitted by neither.

It vanished from the page with nothing able to notice: `--check` compares
generated output against the committed page, so once regenerated the two
agree, and the ratchet never reads the header at all. The only signal would
have been a person missing a paragraph they wrote.
"""

import unittest

from envref.docsgen import clean_preamble, legend_index, marker_legend, header_paragraphs

LEGEND = [
    "# A trailing `# Since vX.Y.Z` records the release a variable first shipped",
    "# in. A variable with no marker predates v0.24.0.",
]
LATER = [
    "# Do not reorder or reflow declarations: the `# Since` markers are anchored",
    "# to the end of the key's own line.",
]
UNRELATED = ["# For quick-start configuration, see .env.example instead."]


def preamble(*paragraphs):
    out = []
    for index, para in enumerate(paragraphs):
        if index:
            out.append("#")
        out += para
    return out


class LegendTest(unittest.TestCase):
    def test_the_legend_is_lifted_as_prose(self):
        legend = marker_legend(preamble(LEGEND, UNRELATED))
        self.assertIsNotNone(legend)
        self.assertEqual(legend[0], LEGEND[0].lstrip("# "))
        self.assertFalse(any(line.startswith("#") for line in legend))

    def test_the_lifted_paragraph_is_not_repeated_in_the_preamble(self):
        kept = "\n".join(clean_preamble(preamble(LEGEND, UNRELATED)))
        self.assertNotIn("A trailing", kept)
        self.assertIn(".env.example", kept)

    def test_a_second_paragraph_mentioning_the_marker_survives(self):
        """The bug: only the lifted paragraph may be dropped, not every match."""
        source = preamble(LEGEND, LATER, UNRELATED)
        legend = marker_legend(source)
        kept = "\n".join(clean_preamble(source))

        self.assertIn("A trailing", "\n".join(legend), "the legend is still lifted")
        self.assertIn(
            "Do not reorder",
            kept,
            "a later paragraph mentioning `# Since` was dropped from the page "
            "as well as not being lifted — it reaches the reader nowhere",
        )
        self.assertNotIn("A trailing", kept, "the legend must not be said twice")

    def test_lift_and_drop_agree_about_which_paragraph_they_mean(self):
        """The property, not the instance: one index, used by both."""
        source = preamble(LEGEND, LATER, UNRELATED)
        paragraphs = header_paragraphs(source)
        index = legend_index(paragraphs)
        self.assertEqual(index, 0)
        kept = clean_preamble(source)
        for other in paragraphs[index + 1 :]:
            with self.subTest(paragraph=other[0]):
                self.assertIn(other[0], kept)

    def test_a_header_with_no_legend_paragraph_reports_none(self):
        self.assertIsNone(marker_legend(preamble(UNRELATED)))
