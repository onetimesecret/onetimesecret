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
       *invoking* scripts/config-version-archaeology.sh with the key names, so
       they are answered by the same code that produced env-versions.tsv
       rather than by a second implementation that could disagree with it.
    2. YAML keys with no ENV read at all (`expire_after: 86400`). These get a
       key-line pickaxe modelled on the same method: a definition-site regex
       with word boundaries, then the earliest STABLE tag (vX.Y.Z, no suffix)
       that contains the introducing commit and is `--merged HEAD`.

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
  - Anything that cannot be answered confidently is dropped with a reason on
    stderr. Silence is correct here; a wrong version is worse than none.

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

This is a ONE-TIME BACKFILL tool, like the archaeology script. Once the marker
is in the file, the comment is the source of truth and this script is only
used to re-derive/audit it. It is idempotent and read-only: it writes nothing
but stdout and stderr, and running it twice produces byte-identical output.

Requires full history — a shallow clone silently reports everything as
introduced at the graft point. The script refuses to run on one.

Usage:
  scripts/config-yaml-version-map.py --env-versions env-versions.tsv
  scripts/config-yaml-version-map.py --env-versions ... > yaml-versions.tsv
  scripts/config-yaml-version-map.py --env-versions ... --root /tmp/copy
  PARALLEL=8 scripts/config-yaml-version-map.py --env-versions ...

Output: the frozen version-map TSV on stdout (spec §4), progress on stderr.

    <relative_file_path> <TAB> <dotted_path> <TAB> <version_or_unreleased>

    etc/defaults/config.defaults.yaml	site.secret_verifier_mode	v0.26.0

Exit codes:
  0  map emitted (possibly with skips, which are reported on stderr)
  1  unusable input: shallow clone, missing env-versions.tsv, missing target
"""

import argparse
import os
import re
import subprocess
import sys
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

# --- Frozen policy. Not knobs; do not add flags. ---
# See docs/development/config-version-annotations.md, "Policy".
BASELINE = (0, 24, 0)
UNRELEASED = "unreleased"

TARGET_FILES = [
    "etc/defaults/config.defaults.yaml",
    "etc/defaults/auth.defaults.yaml",
    "etc/defaults/logging.defaults.yaml",
]

# --- YAML shapes -----------------------------------------------------------
# Deliberately identical to the annotator's: the dotted path this script emits
# has to be the one the annotator resolves, so both walk the file the same way.
# Indentation is spaces only — YAML forbids tabs there.
YAML_KEY_RE = re.compile(
    r"^(?P<indent> *)(?P<key>[A-Za-z0-9_][A-Za-z0-9_.\-]*) *:(?P<rest>[ \t].*|)$"
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


class Git:
    def __init__(self, repo_root):
        self.root = repo_root

    def run(self, *args):
        proc = subprocess.run(
            ["git", *args],
            cwd=self.root,
            capture_output=True,
            text=True,
            check=False,
        )
        return proc.stdout

    def is_shallow(self):
        return self.run("rev-parse", "--is-shallow-repository").strip() == "true"

    def stable_tags(self):
        """Stable releases reachable from HEAD, oldest first (archaeology §2)."""
        out = self.run("tag", "--merged", "HEAD", "--sort=creatordate")
        return [t for t in out.splitlines() if STABLE_TAG_RE.match(t)]

    def first_stable_tag_containing(self, commit):
        """Earliest stable tag containing the commit, or None (= unreleased)."""
        out = self.run(
            "tag", "--contains", commit, "--merged", "HEAD", "--sort=creatordate"
        )
        for tag in out.splitlines():
            if STABLE_TAG_RE.match(tag):
                return tag
        return None

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
    script = repo_root / "scripts" / "config-version-archaeology.sh"
    if not script.is_file():
        log(f"WARN: {script} not found; {len(keys)} env var(s) unresolved")
        return {}

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
        log(f"WARN: archaeology script exited {proc.returncode}; results may be partial")

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
         adds a definition site for the key — `\\bleaf:`, word-bounded so
         `ttl:` is not found inside `default_ttl:`;
      2. earliest stable tag containing that commit, reachable from HEAD.
    """
    regex = r"\b" + ere_escape(leaf) + r":"
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

    Two halves, both required:
      - the path IS declared in the file shipped at `version`;
      - the path is NOT declared at the stable tag immediately before it.
    UNRELEASED is the same test against the newest stable tag: nothing yet.

    A failure means the proposed version is off in one direction or the other
    — usually a key that inherited its version from an env var that shipped
    earlier than the YAML key that reads it. The row is dropped, not adjusted.
    """
    relpath, path = record.relpath, record.path

    if version == UNRELEASED:
        latest = stable[-1]
        shipped = index.paths_at(relpath, latest)
        if shipped is not None and path in shipped:
            return False, f"claimed unreleased but already shipped in {latest}"
        return True, None

    if version not in stable:
        return False, f"{version} is not a stable tag reachable from HEAD"

    at = index.paths_at(relpath, version)
    if at is None:
        return False, f"the file does not exist at {version}"
    if path not in at:
        return False, f"not declared in the file shipped at {version} — first release is later"

    position = stable.index(version)
    if position == 0:
        return True, None
    previous = stable[position - 1]
    before = index.paths_at(relpath, previous)
    if before is not None and path in before:
        return False, f"already declared at {previous} — first release is earlier"
    return True, None


# --- main ------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(
        description="Derive the etc/defaults/*.yaml rows of the config version map.",
    )
    parser.add_argument(
        "--env-versions",
        default="env-versions.tsv",
        help="archaeology TSV for env vars (default: env-versions.tsv)",
    )
    parser.add_argument(
        "--root",
        default=None,
        help="read the YAML files from this directory instead of the repo "
        "(git history still comes from the repo)",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    read_root = Path(args.root).resolve() if args.root else repo_root
    git = Git(repo_root)

    if git.is_shallow():
        log("FAIL: shallow clone — history is truncated and every result would be wrong.")
        log("      Run: git fetch --unshallow && git fetch --tags")
        return 1

    stable = git.stable_tags()
    if not stable:
        log("FAIL: no stable release tags reachable from HEAD. Run: git fetch --tags")
        return 1
    log(f"info: {len(stable)} stable tags, {stable[0]} .. {stable[-1]}")

    env_path = Path(args.env_versions)
    if not env_path.is_file():
        log(f"FAIL: {env_path} not found — this map is derived from it, not from git.")
        log("      Produce it first: scripts/config-version-archaeology.sh > env-versions.tsv")
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
        text = target.read_text(encoding="utf-8")
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
            f"delegating to scripts/config-version-archaeology.sh: "
            f"{' '.join(sorted(missing_env))}"
        )
        env_versions.update(resolve_via_archaeology_script(repo_root, missing_env))

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


if __name__ == "__main__":
    sys.exit(main())
