"""The two Python YAML walks must resolve the same dotted paths.

`docs/development/config-version-annotations.md` records, under Known limits,
that three tools walk these files independently and nothing asserts they agree
— and that a divergence "shows up not as a crash but as a wrong shipped
version". Reviewers asked twice for the cheap pin. Before ADR-042 the two
Python walks lived in separate top-level scripts that could not import each
other, so the pin had nowhere to live; now they are two modules of one
package, and this is it.

It covers all three. The awk walk inside check-config-versions.sh had no way
to say what it saw, which is why it stayed unpinned through four divergences
that were all on its side; `--print-sites` is that way, and it runs no rules
and consults no base ref, so it cannot change a verdict.
"""

import subprocess
import unittest
from collections import defaultdict
from pathlib import Path
from tempfile import TemporaryDirectory

from envref import annotate, versionmap
from envref.paths import repo_root, sh_script
from envref.textio import read_text

ROOT = repo_root()


def walk_both(text: str, relpath: str = "etc/defaults/probe.yaml"):
    """Return (paths annotate resolves, paths versionmap resolves)."""
    bodies = text.split("\n")
    from_annotate = set(annotate.yaml_path_index(bodies))
    from_versionmap = {r.path for r in versionmap.parse_yaml_keys(relpath, text)}
    return from_annotate, from_versionmap


def awk_sites():
    """{relpath: {dotted path}} as the ratchet's own walk sees it."""
    proc = subprocess.run(
        ["bash", str(sh_script("check-config-versions.sh")), "--print-sites"],
        cwd=ROOT,
        env={"PATH": "/usr/bin:/bin:/usr/local/bin", "ENVREF_REPO_ROOT": str(ROOT)},
        capture_output=True,
        text=True,
        check=True,
    )
    sites = defaultdict(dict)
    for line in proc.stdout.splitlines():
        relpath, path, _marker, annot = line.split(" ")
        sites[relpath][path] = annot
    return sites


# The one place the awk walk and the map generator classify a key differently,
# recorded in Known limits: a valueless key whose only children are commented
# out. The guard calls it an annotation site (annot=1) because its lookahead
# finds nothing nested; KeyRecord.is_leaf() calls it a parent (0). The guard
# errs loud on purpose — see the comment above extract_yaml_sites — so this is
# pinned rather than fixed. A second entry appearing here is a new divergence.
KNOWN_ANNOT_DIVERGENCE = {("etc/defaults/auth.defaults.yaml", "simple")}


class ThreeWalkersAgreeTest(unittest.TestCase):
    """The cross-check three review passes asked for, finally three-way."""

    def test_all_three_resolve_the_same_paths(self):
        awk = awk_sites()
        self.assertTrue(versionmap.TARGET_FILES, "no target files discovered")
        for relpath in versionmap.TARGET_FILES:
            with self.subTest(relpath=relpath):
                path = ROOT / relpath
                bodies, _ = annotate.read_lines(path)
                from_annotate = set(annotate.yaml_path_index(bodies))
                from_versionmap = {
                    r.path
                    for r in versionmap.parse_yaml_keys(
                        relpath, path.read_text(encoding="utf-8")
                    )
                }
                from_awk = set(awk[relpath])
                self.assertTrue(from_awk, f"the awk walk saw nothing in {relpath}")
                self.assertEqual(
                    from_awk - from_annotate,
                    set(),
                    "the ratchet demands a marker on a path the annotator cannot address",
                )
                self.assertEqual(
                    from_annotate - from_awk,
                    set(),
                    "the annotator can mark a path the ratchet never freezes",
                )
                self.assertEqual(from_awk, from_versionmap)

    def test_all_three_classify_the_same_paths_as_annotation_sites(self):
        """Paths agreeing is not enough: `annot` is what rule 1 acts on.

        Raised in review, and correct — the divergences this suite exists to
        pin were mostly classification divergences, where the path sets were
        identical and only `annot` differed. `annot` decides whether the
        ratchet demands a marker and whether the generator emits a row, so a
        repeat of exactly those bugs passed the path-set comparison alone.
        """
        awk = awk_sites()
        divergences = set()
        for relpath in versionmap.TARGET_FILES:
            path = ROOT / relpath
            by_path = {
                r.path: ("1" if r.is_leaf() else "0")
                for r in versionmap.parse_yaml_keys(
                    relpath, read_text(path)
                )
            }
            for dotted, annot in awk[relpath].items():
                if dotted in by_path and by_path[dotted] != annot:
                    divergences.add((relpath, dotted))
        self.assertEqual(
            divergences,
            KNOWN_ANNOT_DIVERGENCE,
            "the awk walk and the map generator disagree about which keys are "
            "annotation sites, beyond the one case Known limits records",
        )


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


def three_walks(yaml_text: str):
    """(awk, annotate, versionmap) dotted-path sets for one synthetic file.

    The real files cannot cover every shape — `---` after the first key is the
    case that prompted this — so the suite needs a way to ask all three walks
    about a file that does not exist in the repo. The awk walk answers through
    --print-sites in a throwaway root; the other two are imported.
    """
    relpath = "etc/defaults/config.defaults.yaml"
    with TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "etc" / "defaults").mkdir(parents=True)
        (root / relpath).write_text(yaml_text, encoding="utf-8")
        (root / ".env.reference").write_text("KEY=v\n", encoding="utf-8")
        proc = subprocess.run(
            ["bash", str(sh_script("check-config-versions.sh")), "--print-sites"],
            cwd=root,
            env={"PATH": "/usr/bin:/bin:/usr/local/bin", "ENVREF_REPO_ROOT": str(root)},
            capture_output=True,
            text=True,
            check=True,
        )
    from_awk = {
        line.split(" ")[1]
        for line in proc.stdout.splitlines()
        if line.startswith(relpath)
    }
    from_annotate = set(annotate.yaml_path_index(yaml_text.split("\n")))
    from_versionmap = {r.path for r in versionmap.parse_yaml_keys(relpath, yaml_text)}
    return from_awk, from_annotate, from_versionmap


class SyntheticShapeTest(unittest.TestCase):
    """Shapes etc/defaults/ does not happen to contain."""

    def assertAgree(self, yaml_text, expected):
        awk, ann, vmap = three_walks(yaml_text)
        self.assertEqual(awk, ann, "the awk walk and the annotator disagree")
        self.assertEqual(awk, vmap, "the awk walk and the map generator disagree")
        self.assertEqual(awk, expected)

    def test_a_document_marker_after_keys_resets_the_stack(self):
        """A new document does not inherit the open mapping.

        All three files put `---` before their first key, so the walks agreed
        on the real files while the awk one carried `depth` across a mid-file
        marker: an indented key after it resolved as site.nested where both
        Python walks said nested. A wrong dotted path is a wrong shipped
        version, not a crash.
        """
        self.assertAgree(
            "site:\n  mode: a\n---\n  nested: b\n",
            {"site", "site.mode", "nested"},
        )

    def test_a_leading_document_marker_is_still_harmless(self):
        self.assertAgree("---\nsite:\n  mode: a\n", {"site", "site.mode"})

    def test_an_end_of_document_marker_resets_too(self):
        self.assertAgree(
            "site:\n  mode: a\n...\n  other: b\n",
            {"site", "site.mode", "other"},
        )
