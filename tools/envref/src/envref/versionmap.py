#!/usr/bin/env python3
"""
config-yaml-version-map.py

Emits the version-map rows for etc/defaults/*.yaml — the input the annotator
consumes to write `# Since vX.Y.Z` markers into those files.

WHY this is a separate tool from config-version-archaeology.sh, and why it
does almost no git work:

  The archaeology of "when did this env var first ship?" has already been done
  once, for all 348 env vars, and lives in env-versions.tsv. 217 of the 320
  addressable YAML keys are nothing more than an ERB read of one of those env
  vars — `secret_verifier_mode: <%= ENV['SECRET_VERIFIER_MODE'] || 'warn' %>`
  ships exactly when SECRET_VERIFIER_MODE ships. Re-deriving that from git,
  per key, would be several hundred redundant `git log -G` + `git tag
  --contains` walks whose answers are already sitting in a TSV, and any drift
  between the two runs would show up as a YAML file and a .env.reference file
  disagreeing about the same key. So: read the file, do not redo the walk.

  Fresh git work is limited to the two cases the TSV cannot answer:
    1. Six env vars read only from YAML, never documented in .env.reference
       (ALLOW_NIL_GLOBAL_SECRET, AUTO_DETECT_DOCKER, DEV_BASIC_AUTH,
       DEV_SESSION_AUTH, IN_DOCKER, PLAN_TTL_ANONYMOUS). These are resolved by
       *invoking* bin/envref archaeology with the key names, so
       they are answered by the same code that produced env-versions.tsv
       rather than by a second implementation that could disagree with it.
    2. YAML keys with no ENV read at all (`expire_after: 86400`). These get a
       key-line pickaxe modelled on the same method: a definition-site regex
       with word boundaries, then the earliest STABLE tag (vX.Y.Z, no suffix)
       that contains the introducing commit.

Rules that decide whether a key gets a row at all
(docs/development/config-version-annotations.md, "Policy"):

  - Baseline v0.24.0. A key whose first release predates v0.24.0 gets NO row;
    its missing marker is what says "predates v0.24". Comparison is numeric —
    v0.9.0 < v0.24.0, which a string compare gets backwards.
  - Leaves only. A key that merely introduces nested keys carries no marker;
    its children carry their own. A key whose value is a block sequence of
    plain scalars (`ignore_paths:`) is a leaf and does get one.
  - Sequence items and anything inside them are unaddressable: the spec
    defines no dotted-path syntax for them, and `groups.links.url` names six
    different lines in config.defaults.yaml. They are skipped, not guessed at.
  - Commented-out YAML lines (`#service_url: ...`) declare nothing, so they
    get no row.
  - When a value reads more than one env var, the OLDEST wins: the key existed
    as soon as its first input did.
  - Anything the cheap paths cannot answer confidently falls back to a
    release-tree scan of the dotted path itself (first_release_by_tree_scan),
    with the reason for the fallback on stderr. Dropping it instead would not
    be silence: a line with no marker is the positive claim "predates
    v0.24.0", so a dropped row publishes a different answer rather than none.
    Only a path the oldest scanned release already declared gets no row.

Every proposed row is then PROVED against the release tags before it is
emitted (see verify_row). Inheritance and the key-line pickaxe are both
inferences, and an inference that lands on the wrong release writes a marker
that the §5 ratchet then makes permanent — `Since v0.24.0` on a key that did
not exist until v0.25.9 is a promise to a self-hoster that their config
supports something it does not. So the row is only emitted if the dotted path
is actually present in the file at that tag and actually absent at the tag
before it. A row that fails is dropped with its evidence on stderr, never
silently re-dated: the frozen §4 rule still decides the version, this only
refuses to write one it can disprove.

Which method actually decides a version, since the order above no longer says
it: every version emitted is now the release-tree scan's answer. verify_row
requires equality with the scan, and the rescue pass covers every candidate
that has no row, whatever the reason it was skipped — so inheritance and the
key-line pickaxe no longer influence any emitted value. They decide only which
rows reach that answer cheaply, and a disagreement between a cheap path and
the scan shows up on stderr as a disproof rather than in the output. Read that
as: the scan is the method, the cheap paths are an optimisation that the scan
checks. The inversion is deliberate, but it means a bug in either cheap path
is invisible in the map, so do not assume they are exercised by its output.

This is a ONE-TIME BACKFILL tool, like the archaeology script. Once the marker
is in the file, the comment is the source of truth and this script is only
used to re-derive/audit it. It is idempotent and read-only: it writes nothing
but stdout and stderr, and running it twice produces byte-identical output.

Requires full history — a shallow clone silently reports everything as
introduced at the graft point. The script refuses to run on one.

Usage:
  bin/envref map --env-versions env-versions.tsv
  bin/envref map --env-versions ... > yaml-versions.tsv
  bin/envref map --env-versions ... --root /tmp/copy
  PARALLEL=8 bin/envref map --env-versions ...

Output: the frozen version-map TSV on stdout (spec §4), progress on stderr.

    <relative_file_path> <TAB> <dotted_path> <TAB> <version_or_unreleased>

    etc/defaults/config.defaults.yaml	site.secret_verifier_mode	v0.26.0

Exit codes:
  0  map emitted (possibly with skips, which are reported on stderr)
  1  unusable input: shallow clone, missing env-versions.tsv, missing target
"""

import os
import re
import subprocess
import sys
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from types import SimpleNamespace

from .paths import RootNotFound, repo_root as find_repo_root, sh_script
from .textio import read_text

# --- Frozen policy. Not knobs; do not add flags. ---
# See docs/development/config-version-annotations.md, "Policy".
BASELINE = (0, 24, 0)
UNRELEASED = "unreleased"

# Discovered, not listed. check-config-versions.sh and
# resolve-unreleased-versions.sh both glob this directory, so a hardcoded list
# here would be the last copy left to drift: a fourth defaults file would be
# demanded markers by the ratchet and get no rows from this generator. Both
# extensions, because annotate-config-versions.py treats .yml as YAML too.
# Resolved at import, as before, so TARGET_FILES stays a plain constant. The
# resolver can fail outside a checkout; the glob below already tolerates a
# missing directory, so a failure yields an empty target list rather than an
# import error, and the command reports it.
try:
    _DEFAULTS_DIR = find_repo_root() / "etc" / "defaults"
except RootNotFound:
    _DEFAULTS_DIR = Path("etc/defaults")
TARGET_FILES = sorted(
    f"etc/defaults/{path.name}"
    for pattern in ("*.yaml", "*.yml")
    for path in (_DEFAULTS_DIR.glob(pattern) if _DEFAULTS_DIR.is_dir() else ())
)

# --- YAML shapes -----------------------------------------------------------
# Deliberately identical to the annotator's: the dotted path this script emits
# has to be the one the annotator resolves, so both walk the file the same way.
# Indentation is spaces only — YAML forbids tabs there. A tab between the key
# and its colon is legal separation space and Psych accepts it, so the
# separator is [ \t]* here too; the annotator records what spaces-only cost.
YAML_KEY_RE = re.compile(
    r"^(?P<indent> *)(?P<key>[A-Za-z0-9_][A-Za-z0-9_.\-]*)[ \t]*:(?P<rest>[ \t].*|)$"
)
YAML_SEQ_RE = re.compile(r"^(?P<indent> *)-(?:[ \t](?P<item>.*)|)$")
YAML_BLOCK_SCALAR_RE = re.compile(r"^[|>][+\-]?[0-9]*[ \t]*(#.*)?$")

# ERB control lines (`<% if ... %>`, `<% end %>`) declare no key and must not
# disturb the indent stack.
ERB_CONTROL_RE = re.compile(r"^ *<%[^=]")

# ENV['X'] / ENV["X"] / ENV.fetch('X', ...) inside an ERB value.
ENV_REF_RE = re.compile(r"""ENV\s*(?:\[|\.fetch\s*\()\s*['"]([A-Z][A-Z0-9_]*)['"]""")

# Every place a `\bleaf:` pickaxe could fire in the file, comments included —
# used only to decide whether a leaf name is unique enough to pickaxe on.
LOOSE_KEY_RE = re.compile(r"(?:^|[^A-Za-z0-9_])(?P<key>[A-Za-z_][A-Za-z0-9_.\-]*) *:")

STABLE_TAG_RE = re.compile(r"^v[0-9]+\.[0-9]+\.[0-9]+$")

# Sorts after every real version, so `min()` over a key's inputs never picks
# UNRELEASED while a shipped input is available.
UNRELEASED_SORT_KEY = (10**9, 0, 0)


def log(msg):
    print(msg, file=sys.stderr)


# --- versions --------------------------------------------------------------


def version_sort_key(version):
    """Numeric sort key. v0.9.0 < v0.24.0 — a string compare says otherwise."""
    if version == UNRELEASED:
        return UNRELEASED_SORT_KEY
    m = re.match(r"^v([0-9]+)\.([0-9]+)\.([0-9]+)$", version)
    if not m:
        raise ValueError(f"not a stable version: {version!r}")
    return (int(m.group(1)), int(m.group(2)), int(m.group(3)))


def passes_baseline(version):
    """spec §2: annotate only what is new since v0.24.0. Unreleased always is."""
    return version == UNRELEASED or version_sort_key(version) >= BASELINE


# --- git -------------------------------------------------------------------


class GitFailed(RuntimeError):
    """A git command this script depends on did not succeed."""


class Git:
    def __init__(self, repo_root):
        self.root = repo_root

    def run(self, *args):
        """stdout of a git command that MUST succeed.

        Every caller here reads absence as meaning something specific — no
        such commit, no such tag, key not present at that release — so a git
        command that fails and returns "" does not produce no answer, it
        produces a wrong one, and the wrong one gets frozen into a marker by
        the §5 ratchet. `blob_at` is the one place a missing object is
        expected, and it probes with `cat-file -e` first rather than reading
        a failure as an answer.
        """
        proc = subprocess.run(
            ["git", *args],
            cwd=self.root,
            capture_output=True,
            text=True,
            check=False,
        )
        if proc.returncode != 0:
            raise GitFailed(
                f"git {' '.join(args)} exited {proc.returncode}: "
                f"{proc.stderr.strip() or '(no stderr)'}"
            )
        return proc.stdout

    def is_shallow(self):
        proc = subprocess.run(
            ["git", "rev-parse", "--is-shallow-repository"],
            cwd=self.root,
            capture_output=True,
            text=True,
            check=False,
        )
        # Not self.run(): this is the pre-flight check that reports an unusable
        # repository, so it answers rather than raising.
        return proc.returncode != 0 or proc.stdout.strip() == "true"

    def stable_tags(self):
        """Every stable release, oldest first, in SEMANTIC VERSION order.

        The same tag set and the same ordering as
        bin/envref archaeology, for the same two reasons its
        header gives — this used to differ from it on both counts, and a
        verifier that disagrees with the tool it verifies is worthless:

          - NOT filtered by `--merged HEAD`. 17 of this repo's 94 stable tags
            are not ancestors of HEAD (release branches tagged without a merge
            back). A tag that contains the key shipped the key, merged back or
            not. Dropping those 17 hides real releases from verify_row(), so
            it compares against the wrong predecessor and rejects rows whose
            version is a genuine first release.
          - NOT ordered by `creatordate`. Creation order is not version order:
            v0.19.0 was tagged before v0.18.4 and v0.18.5. verify_row() reads
            `stable[position - 1]` as "the release before this one", which is
            a statement about versions, not about dates.
        """
        out = self.run("tag")
        tags = [t for t in out.splitlines() if STABLE_TAG_RE.match(t)]
        return sorted(tags, key=version_sort_key)

    def first_stable_tag_containing(self, commit):
        """Lowest-versioned stable tag containing the commit, or None.

        Same tag set and ordering as stable_tags(), and for the same reasons:
        `--merged HEAD` would skip a release-branch tag that shipped the
        commit first, dating the key to whichever later release merged it
        back, and `--sort=creatordate` would answer with the tag cut earliest
        rather than the version released earliest.
        """
        out = self.run("tag", "--contains", commit)
        tags = [t for t in out.splitlines() if STABLE_TAG_RE.match(t)]
        return min(tags, key=version_sort_key) if tags else None

    def rename_ancestry(self, path):
        """Every historical path of `path`, so a pickaxe sees pre-rename history.

        etc/defaults/config.defaults.yaml was etc/config.example.yaml, which was
        etc/config.yaml.example, which was etc/config.example. Pickaxing only
        the current name would date every key in it to the rename commit.
        """
        out = self.run(
            "log", "--follow", "--diff-filter=R", "--format=", "--name-status", "--", path
        )
        paths = [path]
        for line in out.splitlines():
            fields = line.split("\t")
            if len(fields) == 3 and fields[0].startswith("R"):
                if fields[1] not in paths:
                    paths.append(fields[1])
        return paths

    def blob_at(self, tag, paths):
        """The file's text at `tag`, trying each historical name, or None.

        `paths` is the rename ancestry, newest name first, so a tag from before
        a rename still finds the file under the name it had back then.
        """
        for candidate in paths:
            proc = subprocess.run(
                ["git", "cat-file", "-e", f"{tag}:{candidate}"],
                cwd=self.root,
                capture_output=True,
                check=False,
            )
            if proc.returncode == 0:
                return self.run("show", f"{tag}:{candidate}")
        return None

    def first_commit_matching(self, regex, paths):
        """Earliest commit whose diff to `paths` adds or removes a matching line."""
        out = self.run(
            "log", "--format=%H", "--reverse", "-G" + regex, "--", *paths
        )
        lines = out.splitlines()
        return lines[0] if lines else None

    def commit_adds_match(self, commit, regex, paths):
        """True when the commit ADDS a matching line, rather than only removing one.

        A first hit that is a deletion means the key already existed somewhere
        this pickaxe cannot see, so the answer would be too late, not too early.
        """
        out = self.run("show", "--format=", "--unified=0", commit, "--", *paths)
        pat = re.compile(regex)
        for line in out.splitlines():
            if line.startswith("+") and not line.startswith("+++"):
                if pat.search(line[1:]):
                    return True
        return False


# --- env-versions.tsv ------------------------------------------------------


def load_env_versions(path):
    """{KEY: 'vX.Y.Z' | 'unreleased'} from the archaeology TSV.

    NOT_FOUND rows are dropped: an env var git could not place is not an answer,
    and any key inheriting from it must be skipped rather than guessed at.
    """
    table = {}
    dropped = []
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            fields = raw.rstrip("\n").split("\t")
            if len(fields) < 2 or not fields[0]:
                continue
            key, release = fields[0], fields[1]
            if release == "UNRELEASED":
                table[key] = UNRELEASED
            elif STABLE_TAG_RE.match(release):
                table[key] = release
            else:
                dropped.append(f"{key} ({release})")
    return table, dropped


def resolve_via_archaeology_script(repo_root, keys):
    """Answer missing env vars with the SAME script that produced the TSV.

    Shelling out rather than reimplementing is the point: one definition-site
    regex, one tag-selection rule, no chance of the YAML map and .env.reference
    disagreeing about DEV_BASIC_AUTH.
    """
    script = sh_script("config-version-archaeology.sh")
    if not script.is_file():
        raise GitFailed(f"{script} not found, so {len(keys)} env var(s) cannot be resolved")

    proc = subprocess.run(
        ["bash", str(script), *sorted(keys)],
        cwd=repo_root,
        capture_output=True,
        text=True,
        check=False,
    )
    for line in proc.stderr.splitlines():
        log(f"  [archaeology] {line}")
    if proc.returncode != 0:
        # Partial archaeology output is the dangerous kind of wrong: the keys it
        # did not reach look exactly like keys that have no answer, so they are
        # skipped, the map is emitted short, and the annotator writes markers
        # for a subset while reporting success. The common cause is a shallow
        # clone, which this container re-creates between sessions.
        raise GitFailed(
            f"bin/envref archaeology exited {proc.returncode} — "
            f"its output is partial and a short map would annotate only some sites"
        )

    table = {}
    for raw in proc.stdout.splitlines():
        fields = raw.split("\t")
        if len(fields) < 2:
            continue
        key, release = fields[0], fields[1]
        if release == "UNRELEASED":
            table[key] = UNRELEASED
        elif STABLE_TAG_RE.match(release):
            table[key] = release
    return table


# --- the YAML walk ---------------------------------------------------------


class KeyRecord:
    """One `key:` line, with just enough context to classify and version it."""

    __slots__ = (
        "relpath",
        "lineno",
        "path",
        "leaf",
        "value",
        "has_child_keys",
        "seq_values",
    )

    def __init__(self, relpath, lineno, path, leaf, value):
        self.relpath = relpath
        self.lineno = lineno
        self.path = path
        self.leaf = leaf
        self.value = value
        self.has_child_keys = False
        self.seq_values = []

    def is_leaf(self):
        """A key that carries a value of its own (spec §4)."""
        if self.value and not self.value.startswith("#"):
            return True
        # `ignore_paths:` / `recipients:` — a block sequence of plain scalars is
        # a value, not a nesting of keys.
        return bool(self.seq_values) and not self.has_child_keys

    def full_value(self):
        return " ".join([self.value] + self.seq_values).strip()

    def env_refs(self):
        # Order-preserving, de-duplicated: an env var read twice is read once.
        seen = []
        for name in ENV_REF_RE.findall(self.full_value()):
            if name not in seen:
                seen.append(name)
        return seen


def parse_yaml_keys(relpath, text):
    """Walk an ERB-templated YAML file line by line and return its key records.

    A real YAML parse is not an option — `<%= ENV['X'] %>` is not YAML — so
    this tracks indentation the way the annotator does, and inherits the same
    deliberate blind spots (sequence contents, block scalar bodies).
    """
    records = []
    stack = []  # [(indent, key, record)] of open parent mappings
    seq_indent = None  # innermost open sequence, or None
    seq_owner = None  # the key record that sequence belongs to
    block_indent = None  # inside a block scalar owned by a key at this indent
    block_owner = None

    for idx, body in enumerate(text.split("\n")):
        # Block scalar body (`uri: >-`): everything more-indented is value, not
        # structure. Collect it so the ERB inside is still scanned for ENV reads.
        if block_indent is not None:
            if body.strip() == "":
                continue
            if len(body) - len(body.lstrip(" ")) > block_indent:
                block_owner.seq_values.append(body.strip())
                continue
            block_indent = None
            block_owner = None

        stripped = body.strip()
        if stripped == "" or stripped.startswith("#"):
            continue
        if stripped == "---" or stripped.startswith("--- ") or stripped == "...":
            stack.clear()
            seq_indent = None
            seq_owner = None
            continue
        if ERB_CONTROL_RE.match(body):
            continue

        indent = len(body) - len(body.lstrip(" "))
        seq = YAML_SEQ_RE.match(body)

        if seq_indent is not None:
            if indent > seq_indent or (indent == seq_indent and seq):
                # Inside a sequence: not addressable by dotted path. Record only
                # whether the owner is a list of scalars or a list of mappings.
                item = seq.group("item") if seq else stripped
                item = (item or "").strip()
                if seq_owner is not None:
                    if YAML_KEY_RE.match(item):
                        seq_owner.has_child_keys = True
                    elif item:
                        seq_owner.seq_values.append(item)
                continue
            seq_indent = None
            seq_owner = None

        if seq:
            # The owning key sits either at this indent (`links:` with items in
            # the same column) or shallower (`groups:` with indented items).
            owner = None
            while stack and stack[-1][0] >= indent:
                popped = stack.pop()
                if popped[0] == indent:
                    owner = popped[2]
            if owner is None and stack:
                owner = stack[-1][2]
            seq_indent = indent
            seq_owner = owner
            item = (seq.group("item") or "").strip()
            if owner is not None:
                if YAML_KEY_RE.match(item):
                    owner.has_child_keys = True
                elif item:
                    owner.seq_values.append(item)
            continue

        m = YAML_KEY_RE.match(body)
        if not m:
            continue

        while stack and stack[-1][0] >= indent:
            stack.pop()

        key = m.group("key")
        path = ".".join([k for _, k, _ in stack] + [key])
        rest = m.group("rest").strip()
        record = KeyRecord(relpath, idx + 1, path, key, rest)
        records.append(record)

        if stack:
            stack[-1][2].has_child_keys = True

        if rest == "" or rest.startswith("#"):
            stack.append((indent, key, record))
        elif YAML_BLOCK_SCALAR_RE.match(rest):
            block_indent = indent
            block_owner = record

    return records


def loose_key_counts(text):
    """How many lines could a `\\bleaf:` pickaxe fire on, comments included.

    Over-counting is the safe direction: it only makes this script decline to
    guess.
    """
    counts = Counter()
    for line in text.split("\n"):
        for m in LOOSE_KEY_RE.finditer(line):
            counts[m.group("key")] += 1
    return counts


# --- archaeology for YAML keys with no ENV read ----------------------------


def ere_escape(leaf):
    """Escape for git's pickaxe, which is POSIX ERE — not Python's dialect.

    Leaf names are `[A-Za-z0-9_.-]+`, so `.` is the only metacharacter in play;
    `-` is literal outside a bracket expression and must NOT be backslashed.
    """
    return leaf.replace(".", r"\.")


def yaml_key_first_release(git, leaf, paths):
    """(version, note) for a YAML key line, or (None, reason) when unsure.

    Same shape as the env-var method in config-version-archaeology.sh:
      1. earliest commit whose diff to this file (and its pre-rename names)
         adds a definition site for the key, word-bounded so `ttl:` is not
         found inside `default_ttl:`;
      2. earliest stable tag containing that commit, by version.

    The boundary is spelled `(^|[^A-Za-z0-9_])` rather than `\\b`. git compiles
    a -G pattern with regcomp(REG_EXTENDED), where `\\b` is a GNU extension: on
    a BSD regcomp — macOS, which this repo supports and gates for elsewhere —
    `\\bttl:` degrades to the literal `bttl:`, which matches nothing. Every
    pickaxe would then return "no commit adds a definition site" and every key
    would route to the rescue pass. The map would be identical, because
    verify_row proves every row against the tree scan regardless, so the
    failure would be invisible in the output and visible only as provenance.
    That is precisely the unobservability this file's header warns about.
    """
    regex = r"(^|[^A-Za-z0-9_])" + ere_escape(leaf) + r":"
    commit = git.first_commit_matching(regex, paths)
    if not commit:
        return None, "no commit adds a definition site"
    if not git.commit_adds_match(commit, regex, paths):
        # First hit is a deletion: the key predates everything these paths can
        # show, so any tag we picked would be later than the truth.
        return None, f"first pickaxe hit {commit[:9]} removes rather than adds it"
    tag = git.first_stable_tag_containing(commit)
    return (tag or UNRELEASED), commit[:9]


# --- proving a proposed row against the release tags -----------------------


class TagIndex:
    """The set of dotted paths each defaults file declared at each release tag.

    Reading a tagged blob and walking it with parse_yaml_keys() is the only
    check that answers the marker's actual question — "was this key in the
    shipped defaults file?" — rather than a proxy for it. It is cheap because
    it is asked per (file, tag) pair and cached, not per key: a 185-row map
    touches well under a hundred blobs.
    """

    def __init__(self, git, ancestry):
        self.git = git
        self.ancestry = ancestry
        self.cache = {}

    def paths_at(self, relpath, tag):
        """Dotted paths declared at `tag`, or None when the file did not exist."""
        key = (relpath, tag)
        if key not in self.cache:
            text = self.git.blob_at(tag, self.ancestry[relpath])
            self.cache[key] = (
                None if text is None else {r.path for r in parse_yaml_keys(relpath, text)}
            )
        return self.cache[key]


def verify_row(index, stable, record, version):
    """(True, None) if `version` is provably this path's first release.

    Proved by the unbroken-run scan — the same method
    first_release_by_tree_scan uses, and the one
    bin/envref archaeology settled on.

    This was a two-point test: declared at `version`, absent at the stable tag
    immediately before it. That proves the path FIRST APPEARED at `version`
    and nothing more, which is failure mode 4 in the archaeology header — the
    one that dated STRIPE_WEBHOOK_SIGNING_SECRET to an abandoned first
    attempt. A path declared at V, absent from V+1 .. V+k and declared again
    through HEAD satisfies both points, and `# Since V` then tells a
    self-hoster running V+1 that they have a setting they do not have. The
    pickaxe path reaches that state by construction: yaml_key_first_release
    takes the EARLIEST commit that ever adds the leaf, which is the abandoned
    attempt itself.

    A failure means the proposed version is off in one direction or the other
    — usually a key that inherited its version from an env var that shipped
    earlier than the YAML key that reads it. The row is dropped, not adjusted;
    the rescue pass in main() then asks this same scan for the real answer.
    """
    relpath, path = record.relpath, record.path

    if version != UNRELEASED and version not in stable:
        return False, f"{version} is not a stable release tag"

    actual = first_release_by_tree_scan(index, stable, relpath, path)
    if actual == version:
        return True, None

    if actual is None:
        return False, "declared by the oldest release scanned — first release is earlier"
    if version == UNRELEASED:
        return False, f"claimed unreleased but shipped without a gap from {actual}"
    if actual == UNRELEASED:
        return False, f"claimed {version} but it is in no release yet"
    if version_sort_key(actual) < version_sort_key(version):
        return False, f"declared without a gap from {actual} — first release is earlier"
    return False, (
        f"not declared without a gap until {actual} — first release is later, "
        f"or it was removed and reintroduced"
    )


def first_release_by_tree_scan(index, stable, relpath, path):
    """The release a dotted path first shipped in, read from the release trees.

    The archaeology method (bin/envref archaeology, "METHOD"),
    asked of a dotted YAML path instead of an env var name: the answer is the
    earliest tag that begins an UNBROKEN run of releases declaring the path
    through to HEAD. A gap ends the run, so a setting that was removed and
    later reintroduced dates from the reintroduction — which is the thing a
    self-hoster needs to know.

    Returns a version, UNRELEASED (at HEAD but in no tag), or None (declared
    by the oldest tag scanned, so it predates the annotation baseline).

    A gap has two possible causes and this rule treats them the same, on
    purpose. One is removal and reintroduction. The other appeared when
    5ce8914ef stopped filtering the tag set by `--merged HEAD`: a maintenance
    release cut from an older point can lack a key that a higher-numbered
    release already shipped. Either way somebody running the release in the
    gap does not have the setting, so the first release of the unbroken run is
    the honest answer — dating it earlier would promise availability to
    exactly the person who lacks it. Worth knowing which case you are looking
    at when a version surprises you, though: all 17 non-ancestor tags sit
    below the v0.24.0 baseline today, so no marker is affected yet, but the
    first maintenance tag cut above the baseline will make this visible.

    This is strictly better than both cheap paths — it asks the tagged tree
    rather than inferring from an env var or a pickaxe — and it is only used
    as the fallback because it is the expensive one. Cost is bounded by
    (tags x files) blobs, not by keys: TagIndex caches per (file, tag), and
    the proof pass has already read most of them.
    """
    run_start = None
    for tag in reversed(stable):
        at = index.paths_at(relpath, tag)
        if at is None or path not in at:
            break
        run_start = tag
    if run_start is None:
        return UNRELEASED
    if run_start == stable[0]:
        return None
    return run_start


# --- main ------------------------------------------------------------------


def _generate(env_versions: str, root: str | None) -> int:
    args = SimpleNamespace(env_versions=env_versions, root=root)

    repo_root = find_repo_root()
    read_root = Path(args.root).resolve() if args.root else repo_root
    git = Git(repo_root)

    if git.is_shallow():
        log("FAIL: shallow clone — history is truncated and every result would be wrong.")
        log("      Run: git fetch --unshallow && git fetch --tags")
        return 1

    stable = git.stable_tags()
    if not stable:
        log("FAIL: no stable release tags found. Run: git fetch --tags")
        return 1
    log(f"info: {len(stable)} stable tags, {stable[0]} .. {stable[-1]}")

    env_path = Path(args.env_versions)
    if not env_path.is_file():
        log(f"FAIL: {env_path} not found — this map is derived from it, not from git.")
        log("      Produce it first: bin/envref archaeology > env-versions.tsv")
        return 1
    env_versions, dropped = load_env_versions(env_path)
    log(f"info: {len(env_versions)} env var version(s) loaded from {env_path}")
    for item in dropped:
        log(f"  skip: env var without a usable version: {item}")

    # --- walk the YAML files ---------------------------------------------
    parsed = {}  # relpath -> [KeyRecord]
    leaf_counts = {}  # relpath -> Counter of every `name:` a pickaxe could hit
    for relpath in TARGET_FILES:
        target = read_root / relpath
        if not target.is_file():
            log(f"FAIL: {target} not found")
            return 1
        # read_text() normalises CRLF: YAML_KEY_RE and the marker recognizer
        # both anchor to end-of-line, and a CRLF worktree cost 99 of 431 key
        # records here before this was shared.
        text = read_text(target)
        parsed[relpath] = parse_yaml_keys(relpath, text)
        leaf_counts[relpath] = loose_key_counts(text)

    skipped = []
    candidates = []  # leaf records that are addressable and want a version
    for relpath in TARGET_FILES:
        path_counts = Counter(r.path for r in parsed[relpath])
        for record in parsed[relpath]:
            if not record.is_leaf():
                skipped.append((record, "parent key — its children carry the markers"))
                continue
            if path_counts[record.path] > 1:
                skipped.append((record, "dotted path is not unique in the file"))
                continue
            candidates.append(record)
    log(
        f"info: {sum(len(r) for r in parsed.values())} key line(s) parsed, "
        f"{len(candidates)} addressable leaf/leaves"
    )

    # --- pass 1: inherit from env-versions.tsv (no git at all) ------------
    missing_env = []
    for record in candidates:
        for name in record.env_refs():
            if name not in env_versions and name not in missing_env:
                missing_env.append(name)

    if missing_env:
        log(
            f"info: {len(missing_env)} env var(s) read only from YAML — "
            f"delegating to bin/envref archaeology: "
            f"{' '.join(sorted(missing_env))}"
        )
        try:
            env_versions.update(resolve_via_archaeology_script(repo_root, missing_env))
        except GitFailed as exc:
            log(f"FAIL: {exc}")
            return 1

    # Historical names of each file, needed both by the key-line pickaxe and by
    # the tag-by-tag proof, so resolve them once for every target.
    ancestry = {}
    for relpath in TARGET_FILES:
        ancestry[relpath] = git.rename_ancestry(relpath)
        log(f"info: {relpath} history follows {' <- '.join(ancestry[relpath])}")

    # --- pass 2: git for YAML keys that read no env var -------------------
    needs_git = []
    for record in candidates:
        if record.env_refs():
            continue
        hits = leaf_counts[record.relpath].get(record.leaf, 0)
        if hits != 1:
            # `enabled:` names 39 lines in config.defaults.yaml. A pickaxe on it
            # answers a question about some other key, so decline to answer.
            skipped.append(
                (
                    record,
                    f"no ENV read and `{record.leaf}:` appears "
                    f"{hits}x in the file — cannot pickaxe it",
                )
            )
            continue
        needs_git.append(record)

    git_results = {}
    if needs_git:
        parallel = int(os.environ.get("PARALLEL", "4"))
        log(f"info: {len(needs_git)} key(s) need fresh archaeology (PARALLEL={parallel})")

        def resolve(record):
            return record, yaml_key_first_release(git, record.leaf, ancestry[record.relpath])

        with ThreadPoolExecutor(max_workers=parallel) as pool:
            for record, result in pool.map(resolve, needs_git):
                git_results[record] = result

    # --- decide, filter by baseline, emit ---------------------------------
    rows = []
    for record in candidates:
        refs = record.env_refs()
        if refs:
            versions = [env_versions.get(name) for name in refs]
            if any(v is None for v in versions):
                unknown = [n for n, v in zip(refs, versions) if v is None]
                skipped.append((record, f"no version for env var(s) {', '.join(unknown)}"))
                continue
            # Oldest input wins: the key existed as soon as its first input did.
            version = min(versions, key=version_sort_key)
            why = "ENV " + "+".join(refs)
        else:
            result = git_results.get(record)
            if result is None:
                continue  # already recorded in `skipped`
            version, note = result
            if version is None:
                skipped.append((record, f"no ENV read and {note}"))
                continue
            why = f"git {note}"

        if not passes_baseline(version):
            skipped.append((record, f"{version} predates the v0.24.0 baseline ({why})"))
            continue
        rows.append((record, version, why))

    # --- prove every proposed row against the release tags ----------------
    index = TagIndex(git, ancestry)
    proved, disproved = [], []
    for record, version, why in rows:
        ok, reason = verify_row(index, stable, record, version)
        if ok:
            proved.append((record, version, why))
        else:
            disproved.append((record, version, why, reason))
            skipped.append((record, f"{version} disproved by the tags: {reason} ({why})"))
    rows = proved
    log(f"info: {len(rows)} row(s) proved against the tags, {len(disproved)} disproved")

    # --- rescue: a dropped row is not silence, it is a claim --------------
    # "Silence is correct here" above is only true where absence means nothing.
    # It does not: the file headers and the contract both define a line with no
    # marker as the positive statement "this predates v0.24.0". So dropping a
    # row does not withhold an answer, it publishes a different one — and for
    # email_providers.ses.region, which shipped in v0.25.7, that answer is
    # false. Every candidate still without a row is therefore asked directly,
    # by release-tree scan. Nothing here can re-date an existing row: verify_row
    # now proves a row with this same scan, so a proved row already equals what
    # this loop would compute, and only candidates with NO row reach it. That
    # was NOT true while verify_row was a two-point test — it could prove V for
    # a path this scan dates to V+k+1 — which is why it no longer is one.
    have = set(record for record, _, _ in rows)
    rescued = []
    for record in candidates:
        if record in have:
            continue
        version = first_release_by_tree_scan(index, stable, record.relpath, record.path)
        if version is None or not passes_baseline(version):
            continue  # genuinely predates the baseline: a bare line is correct
        rescued.append((record, version, "tree scan"))
    if rescued:
        log(f"info: {len(rescued)} row(s) rescued by tree scan that would have shipped bare")
        for record, version, _ in sorted(rescued, key=lambda r: (r[0].relpath, r[0].lineno)):
            log(f"  rescued: {record.relpath}:{record.lineno} {record.path} = {version}")
        rows = rows + rescued
        rows.sort(key=lambda r: (TARGET_FILES.index(r[0].relpath), r[0].lineno))

    for record, reason in sorted(skipped, key=lambda s: (s[0].relpath, s[0].lineno)):
        log(f"  skip: {record.relpath}:{record.lineno} {record.path} — {reason}")

    # Rows inherited from env-versions.tsv are auditable against that file.
    # Rows this script derived itself are not, so show their commit.
    for record, version, why in rows:
        if why.startswith("git "):
            log(f"  derived: {record.relpath}:{record.lineno} {record.path} = {version} ({why})")

    for record, version, _why in rows:
        sys.stdout.write(f"{record.relpath}\t{record.path}\t{version}\n")

    by_file = Counter(record.relpath for record, _, _ in rows)
    log("")
    log(f"PASS: {len(rows)} row(s) emitted, {len(skipped)} key line(s) skipped")
    for relpath in TARGET_FILES:
        log(f"  {relpath}: {by_file.get(relpath, 0)}")
    unreleased = sum(1 for _, v, _ in rows if v == UNRELEASED)
    if unreleased:
        log(f"  ({unreleased} unreleased)")
    return 0


def run(
    *,
    env_versions: str = "env-versions.tsv",
    root: str | None = None,
) -> int:
    """Derive the etc/defaults/*.yaml rows of the config version map.

    Parameters
    ----------
    env_versions
        Archaeology TSV for env vars.
    root
        Read the YAML file CONTENTS from this directory instead of the repo.
        Which files are read, and all git history, still come from the repo: a
        defaults file that exists only under --root has no history here to date
        it from, so it is not discovered and gets no rows.
    """
    try:
        return _generate(env_versions=env_versions, root=root)
    except GitFailed as exc:
        # A half-finished map is worse than none: the annotator would write
        # markers for the sites that survived and report success.
        log(f"FAIL: {exc}")
        return 1
    except RootNotFound as exc:
        # _generate resolves the checkout before doing any work, so this is
        # reachable and was previously a traceback — the one command on the
        # surface that answered a missing checkout differently from the rest.
        # 1, not 2: this module documents 1 as "unusable input", alongside a
        # shallow clone and a missing env-versions.tsv.
        log(f"FAIL: {exc}")
        return 1
