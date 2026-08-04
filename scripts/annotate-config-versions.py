#!/usr/bin/env python3
"""
annotate-config-versions.py

Injects the `# Since vX.Y.Z` markers into .env.reference and
etc/defaults/*.yaml from a pre-computed version map.

WHY a separate tool from config-version-archaeology.sh: archaeology is the
expensive, one-time git walk that answers "when did this key first ship?".
This script is the cheap, repeatable half that writes those answers into the
config files and — via --check — proves in CI that they are still there and
still say the same thing. Splitting them means nobody re-runs `git tag
--contains` 253 times just to verify a comment.

Marker contract (ANNOTATION-SPEC.md §1 — frozen, do not "improve"):

    Recognizer:  [ \\t]+# Since (v[0-9]+\\.[0-9]+\\.[0-9]+|unreleased)[ \\t]*$
    Writer:      exactly two spaces, then `# Since v0.24.3` / `# Since unreleased`

The marker lives on the line that DECLARES the key, never on a preceding
comment line, so it survives copy-paste of a single line.

Markers are immutable history. A key that shipped in v0.24.0 is
"Since v0.24.0" forever, regardless of later edits to its default. So a line
whose existing marker disagrees with the map is reported as an error, never
silently re-dated. --force exists for the release step that resolves
`unreleased` to a real version; nothing else should use it.

Input: the version map, TSV, one row per annotation site (spec §4):

    <relative_file_path> <TAB> <key_or_dotted_path> <TAB> <version_or_unreleased>

    .env.reference                          SECRET_VERIFIER_MODE   v0.26.0
    etc/defaults/config.defaults.yaml       site.secret_verifier_mode   v0.26.0

Blank lines and `#` comment lines in the map are ignored. A version that is
neither `vN.N.N` nor the literal `unreleased` aborts the run before anything
is written — a malformed version in a marker is worse than no marker at all.

Site resolution:

  .env.reference — the row's KEY matches a line `^#?KEY=`. Six keys appear
    twice (an active default up top, a commented dev override in the
    DEVELOPMENT ONLY block), so: one match wins outright; several matches
    with exactly one *active* (uncommented) line means that active line is
    the declaration site; anything else is ambiguous and is reported, not
    guessed.

  YAML — the row's dotted path is resolved by tracking indentation, because a
    bare key name is hopeless here (`enabled:` occurs 44 times in
    config.defaults.yaml alone). Sequence items and their contents are not
    addressable by dotted path and are skipped rather than guessed at; block
    scalar bodies (`uri: >-`) are skipped too, so the ERB inside them never
    gets mistaken for a nested key.

Preservation: every line the map does not name is passed through byte for
byte — no reflow, no reordering, no EOF-newline change, no trailing-whitespace
cleanup. `git diff --stat` after a run must show only marker additions. The
one exception is the annotated line itself, whose trailing whitespace (if any)
is dropped so the marker gets its contractual two spaces.

Usage:
  scripts/annotate-config-versions.py MAP.tsv              # apply
  scripts/annotate-config-versions.py --check MAP.tsv      # CI: verify only
  scripts/annotate-config-versions.py --dry-run MAP.tsv    # show the diff
  scripts/annotate-config-versions.py --force MAP.tsv      # re-date markers
  scripts/annotate-config-versions.py --root DIR MAP.tsv   # annotate a copy

Exit codes:
  0  everything the map asks for is in place (or was just applied)
  1  drift: a site is missing its marker, disagrees, is ambiguous, or is gone
  2  bad input: unusable map, unreadable/missing target, bad flag combination
"""

import argparse
import difflib
import re
import sys
from pathlib import Path

# --- The frozen marker grammar (spec §1). Nothing else may parse markers. ---
MARKER_RE = re.compile(r"[ \t]+# Since (v[0-9]+\.[0-9]+\.[0-9]+|unreleased)[ \t]*$")
VERSION_RE = re.compile(r"^(v[0-9]+\.[0-9]+\.[0-9]+|unreleased)$")

# Catches a near-miss marker (`# Since v0.24`, `#Since v1.2.3`, trailing prose)
# so we report it instead of appending a second marker beside it.
LOOSE_SINCE_RE = re.compile(r"[ \t]#[ \t]*Since\b", re.IGNORECASE)

# YAML shapes. Indentation is spaces only — YAML forbids tabs there, so a
# tab-indented line simply never resolves to a path (and is reported as such).
YAML_KEY_RE = re.compile(
    r"^(?P<indent> *)(?P<key>[A-Za-z0-9_][A-Za-z0-9_.\-]*) *:(?P<rest>[ \t].*|)$"
)
YAML_SEQ_RE = re.compile(r"^(?P<indent> *)-(?:[ \t].*|)$")
YAML_BLOCK_SCALAR_RE = re.compile(r"^[|>][+\-]?[0-9]*[ \t]*(#.*)?$")


class HardError(Exception):
    """Unusable input. Nothing is written; exit 2."""


# --- marker helpers ------------------------------------------------------


def existing_marker(body):
    """Version in the line's marker, or None."""
    m = MARKER_RE.search(body)
    return m.group(1) if m else None


def has_malformed_marker(body):
    return LOOSE_SINCE_RE.search(body) is not None and not MARKER_RE.search(body)


def with_marker(body, version):
    """The line as the writer emits it: existing marker replaced, two spaces, marker."""
    stripped = MARKER_RE.sub("", body).rstrip(" \t")
    return f"{stripped}  # Since {version}"


def has_other_trailing_comment(body, is_yaml):
    """True if a YAML line already carries a non-marker trailing comment.

    logging.defaults.yaml aligns per-logger levels with `App: warn  # ...`.
    Annotating those appends after the existing comment, which still satisfies
    the recognizer, but it is worth telling a human about. Only asked of YAML:
    in .env.reference a `#` is part of the value (`BRAND_PRIMARY_COLOR='#3B82F6'`),
    not a comment.
    """
    if not is_yaml:
        return False
    m = YAML_KEY_RE.match(MARKER_RE.sub("", body))
    return m is not None and "#" in m.group("rest")


# --- file I/O that round-trips exactly -----------------------------------


def read_lines(path):
    """Split into line bodies + per-line CR flags so join_lines() is a byte no-op."""
    try:
        text = path.read_bytes().decode("utf-8")
    except OSError as exc:
        raise HardError(f"cannot read {path}: {exc}") from exc
    except UnicodeDecodeError as exc:
        raise HardError(f"{path} is not valid UTF-8: {exc}") from exc

    bodies, crs = [], []
    for part in text.split("\n"):
        if part.endswith("\r"):
            bodies.append(part[:-1])
            crs.append(True)
        else:
            bodies.append(part)
            crs.append(False)
    if any("\r" in b for b in bodies):
        raise HardError(f"{path} has bare CR line endings; refusing to rewrite it")
    return bodies, crs


def join_lines(bodies, crs):
    return "\n".join(b + ("\r" if c else "") for b, c in zip(bodies, crs))


# --- site resolution -----------------------------------------------------


def resolve_env_site(bodies, key):
    """(index, None) or (None, problem) for a `^#?KEY=` line in .env.reference."""
    pat = re.compile(r"^(?P<hash>#?)" + re.escape(key) + r"=")
    hits = [(i, bool(pat.match(b).group("hash"))) for i, b in enumerate(bodies) if pat.match(b)]

    if not hits:
        return None, "NOT FOUND: no line matches ^#?%s=" % key
    if len(hits) == 1:
        return hits[0][0], None

    active = [i for i, commented in hits if not commented]
    if len(active) == 1:
        return active[0], None

    where = ", ".join(str(i + 1) for i, _ in hits)
    return None, f"AMBIGUOUS: {len(hits)} lines match (lines {where}); no single declaration site"


def yaml_path_index(bodies):
    """Map every addressable dotted path to the line indices that declare it.

    Mapping keys only. Sequence items, everything nested inside them, and
    block scalar bodies are deliberately left unaddressable: the spec defines
    no dotted-path syntax for them, and inventing one here would let a bad map
    row silently annotate the wrong line.
    """
    index = {}
    stack = []  # [(indent, key)] of open parent mappings
    seq_indent = None  # innermost open sequence, or None
    block_indent = None  # inside a block scalar owned by a key at this indent

    for idx, body in enumerate(bodies):
        if block_indent is not None:
            if body.strip() == "":
                continue
            if len(body) - len(body.lstrip(" ")) > block_indent:
                continue
            block_indent = None

        stripped = body.strip()
        if stripped == "" or stripped.startswith("#"):
            continue
        if stripped == "---" or stripped.startswith("--- ") or stripped == "...":
            stack.clear()
            seq_indent = None
            continue

        indent = len(body) - len(body.lstrip(" "))
        seq = YAML_SEQ_RE.match(body)

        if seq_indent is not None:
            if indent > seq_indent or (indent == seq_indent and seq):
                continue  # still inside the sequence: not addressable
            seq_indent = None

        if seq:
            while stack and stack[-1][0] >= indent:
                stack.pop()
            seq_indent = indent
            continue

        m = YAML_KEY_RE.match(body)
        if not m:
            continue

        while stack and stack[-1][0] >= indent:
            stack.pop()

        key = m.group("key")
        path = ".".join([k for _, k in stack] + [key])
        index.setdefault(path, []).append(idx)

        rest = MARKER_RE.sub("", m.group("rest")).strip()
        if rest == "" or rest.startswith("#"):
            stack.append((indent, key))  # parent: children follow
        elif YAML_BLOCK_SCALAR_RE.match(rest):
            block_indent = indent

    return index


def resolve_yaml_site(index, path):
    hits = index.get(path, [])
    if not hits:
        return None, f"NOT FOUND: no key declares the path {path}"
    if len(hits) == 1:
        return hits[0], None
    where = ", ".join(str(i + 1) for i in hits)
    return None, f"AMBIGUOUS: path declared on {len(hits)} lines ({where})"


# --- the map -------------------------------------------------------------


def parse_map(map_path, root):
    """Ordered {relpath: [(key, version, map_lineno)]}. Raises HardError on junk."""
    try:
        text = map_path.read_text(encoding="utf-8")
    except OSError as exc:
        raise HardError(f"cannot read map {map_path}: {exc}") from exc

    rows, errors, seen = {}, [], {}
    for lineno, raw in enumerate(text.split("\n"), 1):
        line = raw.rstrip("\r")
        if line.strip() == "" or line.lstrip().startswith("#"):
            continue

        fields = line.split("\t")
        if len(fields) != 3:
            errors.append(f"{map_path}:{lineno}: expected 3 tab-separated fields, got {len(fields)}")
            continue
        relpath, key, version = (f.strip() for f in fields)

        if not relpath or not key:
            errors.append(f"{map_path}:{lineno}: empty file path or key")
            continue
        if not VERSION_RE.match(version):
            errors.append(
                f"{map_path}:{lineno}: version {version!r} is neither vN.N.N nor 'unreleased'"
            )
            continue
        if Path(relpath).is_absolute() or ".." in Path(relpath).parts:
            errors.append(f"{map_path}:{lineno}: path {relpath!r} escapes the repo root")
            continue

        prior = seen.get((relpath, key))
        if prior and prior[0] != version:
            errors.append(
                f"{map_path}:{lineno}: {relpath} {key} mapped to {version} "
                f"but to {prior[0]} on line {prior[1]}"
            )
            continue
        if prior:
            continue  # exact duplicate row: harmless
        seen[(relpath, key)] = (version, lineno)
        rows.setdefault(relpath, []).append((key, version, lineno))

    if errors:
        raise HardError("unusable version map:\n  " + "\n  ".join(errors))
    if not rows:
        raise HardError(f"{map_path} contains no annotation rows")

    for relpath in rows:
        target = root / relpath
        if not target.is_file():
            raise HardError(f"{relpath} (from {map_path}) does not exist under {root}")
    return rows


# --- per-file work -------------------------------------------------------


def process_file(root, relpath, entries, force):
    """Returns (new_bodies, crs, original_bodies, stats, problems, notes)."""
    path = root / relpath
    bodies, crs = read_lines(path)
    original = list(bodies)

    is_yaml = path.suffix in (".yaml", ".yml")
    index = yaml_path_index(bodies) if is_yaml else None

    stats = {"added": 0, "ok": 0, "rewritten": 0}
    problems, notes = [], []

    for key, version, map_lineno in entries:
        if is_yaml:
            idx, problem = resolve_yaml_site(index, key)
        else:
            idx, problem = resolve_env_site(bodies, key)
        if problem is not None:
            problems.append((relpath, key, map_lineno, problem))
            continue

        body = bodies[idx]

        if has_malformed_marker(body):
            problems.append(
                (
                    relpath,
                    key,
                    map_lineno,
                    f"MALFORMED: line {idx + 1} has a 'Since' comment that does not match "
                    f"the recognizer; fix it by hand: {body.strip()!r}",
                )
            )
            continue

        present = existing_marker(body)
        if present == version:
            stats["ok"] += 1
            continue  # byte-identical: idempotency lives here

        if present is not None:
            if not force:
                problems.append(
                    (
                        relpath,
                        key,
                        map_lineno,
                        f"CONFLICT: line {idx + 1} says 'Since {present}', map says "
                        f"'{version}'. Markers are immutable history — re-run with "
                        f"--force only if you are resolving a release.",
                    )
                )
                continue
            bodies[idx] = with_marker(body, version)
            stats["rewritten"] += 1
            continue

        if has_other_trailing_comment(body, is_yaml):
            notes.append(f"{relpath}:{idx + 1}: marker appended after an existing trailing comment")
        bodies[idx] = with_marker(body, version)
        stats["added"] += 1

    return bodies, crs, original, stats, problems, notes


def unified(relpath, original, new):
    return difflib.unified_diff(
        [l + "\n" for l in original],
        [l + "\n" for l in new],
        fromfile=f"a/{relpath}",
        tofile=f"b/{relpath}",
        lineterm="\n",
    )


# --- main ----------------------------------------------------------------


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Inject 'Since vX.Y.Z' markers into config files from a version map.",
        epilog="Exit 0 = in place, 1 = drift, 2 = bad input.",
    )
    parser.add_argument("map", metavar="MAP.tsv", help="version map (spec §4 TSV)")
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify only: exit 1 listing anything missing or wrong, change nothing",
    )
    parser.add_argument(
        "--dry-run", action="store_true", help="print the unified diff instead of applying it"
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="rewrite a marker whose version disagrees with the map (release step only)",
    )
    parser.add_argument(
        "--root",
        default=None,
        metavar="DIR",
        help="root the map's paths are relative to (default: this script's repo)",
    )
    parser.add_argument("-q", "--quiet", action="store_true", help="suppress per-file PASS lines")
    args = parser.parse_args(argv)

    if args.check and args.dry_run:
        parser.error("--check and --dry-run are both read-only; pick one")
    if args.check and args.force:
        parser.error("--force has no meaning with --check")

    root = Path(args.root).resolve() if args.root else Path(__file__).resolve().parent.parent
    if not root.is_dir():
        print(f"FAIL: root {root} is not a directory", file=sys.stderr)
        return 2

    try:
        rows = parse_map(Path(args.map), root)
    except HardError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 2

    total = sum(len(v) for v in rows.values())
    if not args.quiet:
        print(f"info: {total} mapped site(s) across {len(rows)} file(s), root {root}")

    all_problems, all_notes, changed_files = [], [], 0
    added = ok = rewritten = 0

    for relpath, entries in rows.items():
        try:
            new, crs, original, stats, problems, notes = process_file(
                root, relpath, entries, args.force
            )
        except HardError as exc:
            print(f"FAIL: {exc}", file=sys.stderr)
            return 2

        all_problems.extend(problems)
        all_notes.extend(notes)
        added += stats["added"]
        ok += stats["ok"]
        rewritten += stats["rewritten"]

        pending = stats["added"] + stats["rewritten"]
        if pending:
            changed_files += 1

        if args.dry_run:
            sys.stdout.writelines(unified(relpath, original, new))
        elif args.check:
            if pending and not args.quiet:
                print(f"FAIL: {relpath} — {pending} site(s) missing or wrong")
        elif pending:
            (root / relpath).write_bytes(join_lines(new, crs).encode("utf-8"))
            if not args.quiet:
                print(
                    f"PASS: {relpath} — {stats['added']} added, "
                    f"{stats['rewritten']} rewritten, {stats['ok']} already correct"
                )
        elif not args.quiet:
            print(f"PASS: {relpath} — {stats['ok']} already correct, nothing to do")

    for note in all_notes:
        print(f"NOTE: {note}")

    if all_problems:
        print(f"FAIL: {len(all_problems)} unresolved site(s):", file=sys.stderr)
        for relpath, key, map_lineno, problem in all_problems:
            print(f"  {relpath}\t{key}\t(map line {map_lineno})\t{problem}", file=sys.stderr)

    if args.check:
        missing = added + rewritten
        if missing or all_problems:
            print(
                f"FAIL: {missing} site(s) missing or wrong, "
                f"{len(all_problems)} unresolved, {ok} correct",
                file=sys.stderr,
            )
            return 1
        print(f"PASS: all {ok} mapped site(s) carry the correct marker")
        return 0

    if all_problems:
        return 1

    verb = "would change" if args.dry_run else "changed"
    print(
        f"PASS: {added} marker(s) added, {rewritten} rewritten, {ok} already correct "
        f"({verb} {changed_files} file(s))"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
