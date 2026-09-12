"""The two Python YAML walks must resolve the same dotted paths.

`docs/development/config-version-annotations.md` records, under Known limits,
that three tools walk these files independently and nothing asserts they agree
— and that a divergence "shows up not as a crash but as a wrong shipped
version". Reviewers asked twice for the cheap pin. Before ADR-042 the two
Python walks lived in separate top-level scripts that could not import each
other, so the pin had nowhere to live; now they are two modules of one
package, and this is it.

It covers two of the three walkers. The awk walk inside
check-config-versions.sh is still unpinned: it has no entry point that emits
its site list, and adding one means editing a reviewed script. That remains in
the Known limits.
"""

import unittest
from pathlib import Path

from envref import annotate, versionmap
from envref.paths import repo_root

ROOT = repo_root()


def walk_both(text: str, relpath: str = "etc/defaults/probe.yaml"):
    """Return (paths annotate resolves, paths versionmap resolves)."""
    bodies = text.split("\n")
    from_annotate = set(annotate.yaml_path_index(bodies))
    from_versionmap = {r.path for r in versionmap.parse_yaml_keys(relpath, text)}
    return from_annotate, from_versionmap


class RealFilesAgreeTest(unittest.TestCase):
    """The files the ratchet actually guards, walked both ways."""

    def test_every_target_file_resolves_identically(self):
        self.assertTrue(versionmap.TARGET_FILES, "no target files discovered")
        for relpath in versionmap.TARGET_FILES:
            with self.subTest(relpath=relpath):
                path = ROOT / relpath
                self.assertTrue(path.is_file(), f"{path} is missing")
                bodies, _ = annotate.read_lines(path)
                from_annotate = set(annotate.yaml_path_index(bodies))
                from_versionmap = {
                    r.path
                    for r in versionmap.parse_yaml_keys(
                        relpath, path.read_text(encoding="utf-8")
                    )
                }
                self.assertEqual(
                    from_annotate - from_versionmap,
                    set(),
                    "paths the annotator can address but the map generator never emits: "
                    "the ratchet would demand a marker no tool here writes",
                )
                self.assertEqual(
                    from_versionmap - from_annotate,
                    set(),
                    "paths the map generator emits but the annotator cannot address: "
                    "those rows would be dropped or written to the wrong line",
                )


class SeparatorTest(unittest.TestCase):
    """A tab between a key and its colon. Fixed in review; kept fixed here.

    YAML forbids tabs in indentation but allows them as separation space, and
    Psych — which is what actually loads these files — accepts `key<TAB>:`.
    Both Python walks once matched spaces only, which made such a key a site to
    the ratchet, invisible to the map, and re-parented its children onto the
    preceding sibling, dating them from that sibling's env var.
    """

    def test_tab_before_the_colon_is_a_key_to_both(self):
        a, v = walk_both("alpha\t: 1\nbeta: 2\n")
        self.assertIn("alpha", a)
        self.assertIn("alpha", v)
        self.assertEqual(a, v)

    def test_tab_before_the_colon_still_parents_its_children(self):
        a, v = walk_both("sibling: 1\nparent\t:\n  child: 2\n")
        self.assertIn("parent.child", a, "child was re-parented onto the sibling")
        self.assertIn("parent.child", v, "child was re-parented onto the sibling")
        self.assertNotIn("sibling.child", a)
        self.assertNotIn("sibling.child", v)

    def test_tab_indentation_is_not_a_key_line(self):
        """YAML really does forbid tabs here, so neither walk may accept it."""
        a, v = walk_both("parent:\n\tchild: 2\n")
        self.assertNotIn("parent.child", a)
        self.assertNotIn("parent.child", v)
        self.assertEqual(a, v)


class ErbTest(unittest.TestCase):
    """ERB control lines are not YAML structure, to either walk."""

    def test_control_lines_do_not_become_paths(self):
        text = "site:\n  <% if defined?(x) %>\n  secure: true\n  <% end %>\n"
        a, v = walk_both(text)
        self.assertIn("site.secure", a)
        self.assertIn("site.secure", v)
        self.assertEqual(a, v)

    def test_output_tags_are_left_alone_as_values(self):
        a, v = walk_both("mode: <%= ENV['MODE'] || 'warn' %>\n")
        self.assertIn("mode", a)
        self.assertIn("mode", v)
        self.assertEqual(a, v)
