#!/usr/bin/env bash
#
# check-config-versions.sh
#
# The RATCHET for "# Since vX.Y.Z" config annotations, in the same idiom as
# check-env-reference.sh. Dependency-free (git plus grep/sed/awk/sort/comm/join
# only). Contract: docs/development/config-version-annotations.md
#
# The one-time backfill that annotated .env.reference and etc/defaults/*.yaml is
# worthless the moment the next PR adds an undated key, and actively harmful the
# moment someone edits a marker that already shipped — a self-hoster reading
# "Since v0.24.0" is using it to decide whether to upgrade. So this guard
# enforces, on every PR, comparing the working tree against origin/main:
#
#   1. NEW KEYS CARRY A MARKER. A key in the working tree that is not on
#      origin/main is new work and must be annotated. `unreleased` is the
#      expected value — the key is, by definition, in no release yet.
#   2. SHIPPED MARKERS ARE IMMUTABLE. A concrete `# Since vX.Y.Z` present on
#      origin/main must still be there. Removing or renaming a key is fine
#      (the marker leaves with it); silently re-dating one is not.
#      The one sanctioned change is `unreleased` -> a real version, which the
#      release process performs when it cuts that version. That transition is
#      allowed precisely because `unreleased` is not yet history.
#   3. MARKERS ARE WELL-FORMED. Every marker matches the §1 recognizer exactly,
#      so the annotator, this guard and the docs generator all agree on what a
#      marker is. Catches `# since v1.2.3`, `#Since v1.2.3`, `# Since 1.2.3`,
#      `# Since v1.2`, and trailing text after the version.
#
# Deliberately NOT enforced: an *absent* marker on a pre-existing key. Per §2,
# absence means "predates v0.24.0" and is the correct state for most keys.
# Rule 3 only inspects key-declaration lines, so prose comments — and the file
# header blocks that document this convention, which necessarily quote an
# example marker — do not trip it.
#
# Annotation sites, per §3/§4:
#   .env.reference        every `KEY=` / `#KEY=` line (most keys are documented
#                         commented out, and those carry markers too).
#   etc/defaults/*.yaml   every mapping key carrying a scalar/ERB value. A
#                         parent key that only introduces children is not a
#                         site (the children carry their own markers), and
#                         sequence entries are list *content*, not config keys,
#                         so those subtrees are skipped entirely.
#
# Usage: scripts/check-config-versions.sh    (no arguments; exit 1 on drift)
#
set -euo pipefail
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# --- The recognizer (see "The marker" in the contract doc) --------------
# This is the ONLY pattern that defines a marker. Do not "improve" it here
# without changing the spec and every other tool in the family.
MARKER_RE='[[:blank:]]+# Since (v[0-9]+\.[0-9]+\.[0-9]+|unreleased)[[:blank:]]*$'

# "Someone tried to write a marker": a trailing comment that opens with
# since/Since. Anything matching this but not MARKER_RE is a typo, not prose —
# real English comments read "# kept since v1", never "#Since ...".
MARKER_LOOSE_RE='#[[:blank:]]*[Ss][Ii][Nn][Cc][Ee]([[:blank:]]|$)'

# Key-declaration lines — the only place a marker is allowed to live.
ENV_DECL_RE='^#?[A-Z][A-Z0-9_]+='
YAML_DECL_RE='^[[:space:]]*(- )?[A-Za-z_][A-Za-z0-9_.-]*:([[:space:]]|$)'

[[ -f .env.reference ]] || { echo "FAIL: .env.reference not found" >&2; exit 1; }

TARGETS=(.env.reference)
for y in etc/defaults/*.yaml; do
  if [[ -f "$y" ]]; then TARGETS+=("$y"); fi
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

: > "$tmp/fail_new"        # <file>|<key>
: > "$tmp/fail_changed"    # <file>|<key>|<base_version>|<worktree_marker>
: > "$tmp/fail_malformed"  # <file>|<lineno>|<line>
: > "$tmp/fail_disagree"   # <file>|<path>|<version_a>|<version_b>
: > "$tmp/fail_hidden"     # <file>|<key>|<lineno of the bare active line>
: > "$tmp/note_versioned"  # <file>|<key>|<version>

sites_total=0
markers_total=0
new_total=0

# --- Base ref ------------------------------------------------------------
# "What has already shipped" is whatever this branch is being merged INTO, and
# in this repo that is usually not main: feature PRs target develop (ci.yml and
# migration-tests.yml both gate on it) and develop runs well ahead of main.
# Hardcoding origin/main would compare a develop-based branch against a tree
# hundreds of commits stale and report long-settled keys as brand new.
#
# Order of preference:
#   CONFIG_VERSION_BASE_REF   explicit override (local experiments, release ops)
#   GITHUB_BASE_REF           the branch the PR actually targets, set by Actions
#   origin/develop, origin/main, develop, main
BASE_REF=""
resolve_ref() { git rev-parse --verify --quiet "$1" >/dev/null 2>&1; }

if git rev-parse --git-dir >/dev/null 2>&1; then
  for candidate in \
    "${CONFIG_VERSION_BASE_REF:-}" \
    "${GITHUB_BASE_REF:+origin/$GITHUB_BASE_REF}" \
    "${GITHUB_BASE_REF:-}" \
    origin/develop origin/main develop main
  do
    if [[ -n "$candidate" ]] && resolve_ref "$candidate"; then
      BASE_REF="$candidate"
      break
    fi
  done
fi

# Compare against the fork point, not the base tip. Once the release process
# starts rewriting `unreleased` markers to a concrete version on the base
# branch, a branch that forked before that release would otherwise look like it
# had *reverted* those markers — a spurious immutability failure on a PR that
# never touched them.
BASE_DESC="$BASE_REF"
if [[ -n "$BASE_REF" ]]; then
  if merge_base=$(git merge-base HEAD "$BASE_REF" 2>/dev/null) && [[ -n "$merge_base" ]]; then
    BASE_DESC="$BASE_REF (merge-base ${merge_base:0:9})"
    BASE_REF="$merge_base"
  fi
fi

# CI must not pass merely because it forgot to fetch the base branch. A guard
# that silently downgrades to "syntax only" is a guard that stops guarding.
if [[ -z "$BASE_REF" && -n "${CONFIG_VERSION_REQUIRE_BASE:-}" ]]; then
  echo "FAIL: no base ref available, and CONFIG_VERSION_REQUIRE_BASE is set." >&2
  echo "      New-key and immutability drift cannot be checked without one." >&2
  echo "      Fetch the base branch first, e.g. 'git fetch origin develop'." >&2
  exit 1
fi

# --- Site extraction -----------------------------------------------------
# Both extractors emit one record per annotation site:
#   <key_or_dotted_path> <SP> <marker|-> <SP> <is_annotatable 0|1>
# Keys, dotted paths and versions never contain spaces, so a plain space keeps
# the records cut/comm/join-friendly.

extract_env_sites() {
  local f="$1"
  # Marked declarations. \1 is the key, \2 the version (from MARKER_RE).
  sed -n -E "s/^#?([A-Z][A-Z0-9_]+)=.*${MARKER_RE}/\1 \2 1/p" "$f"
  # Unmarked declarations.
  { grep -E "$ENV_DECL_RE" "$f" || true; } \
    | { grep -vE "$MARKER_RE" || true; } \
    | sed -E 's/^#?([A-Z][A-Z0-9_]+)=.*/\1 - 1/'
}

extract_yaml_sites() {
  # Two passes: whether a key is an annotation site depends on what FOLLOWS it,
  # so the whole file is buffered before any decision is made. Judging by the
  # key's own line alone treats `ignore_paths:` (a list-valued leaf) and
  # `site:` (a parent) identically, and a new list- or nil-valued key then
  # slips past rule 1 needing no marker at all.
  awk '
    { raw[NR] = $0 }
    END {
      n = NR
      for (i = 1; i <= n; i++) {
        l = raw[i]
        if (l ~ /^[ \t]*$/ || l ~ /^[ \t]*#/ || l ~ /^(---|\.\.\.)/) { content[i] = 0; continue }
        content[i] = 1
        match(l, /^ */); indent[i] = RLENGTH
      }

      depth = 0; skip = -1; seqind = -1
      for (i = 1; i <= n; i++) {
        if (!content[i]) continue
        line = raw[i]; ind = indent[i]
        rest = substr(line, ind + 1)

        # Inside a skipped subtree (sequence entry contents, block scalar
        # bodies)? Both open one column deeper than the line that starts them,
        # so a sibling at the same indentation as the opener is never
        # swallowed here.
        if (skip >= 0 && ind >= skip) continue
        skip = -1

        # Still inside the sequence that seqind opened? YAML lets a sequence
        # sit at the indentation of its parent key — config.defaults.yaml
        # writes "links:" and its "- text: ..." entries both at column 8 — so
        # dedent alone cannot mark where a sequence ends: the first line at
        # that indentation which is NOT an entry ends it. Skipping everything
        # at "ind >= entry indent", as this did, also swallowed the sibling
        # KEY that follows such a sequence. That key then vanished from the
        # site list: Rule 1 could not require a marker on it, and Rule 2 could
        # not protect the marker it had.
        if (seqind >= 0) {
          if (ind == seqind && rest ~ /^-([ \t]|$)/) { skip = seqind + 1; continue }
          seqind = -1
        }

        # A sequence entry has no stable dotted path — two sibling "- name:"
        # entries would collide and make the immutability check lie. List
        # content is data, not a config key, so drop the whole subtree.
        if (rest ~ /^-([ \t]|$)/) { seqind = ind; skip = ind + 1; continue }

        if (rest !~ /^[A-Za-z_][A-Za-z0-9_.-]*:([ \t]|$)/) continue
        key = rest; sub(/:.*$/, "", key)

        while (depth > 0 && sind[depth] >= ind) depth--
        depth++; stack[depth] = key; sind[depth] = ind

        path = stack[1]
        for (k = 2; k <= depth; k++) path = path "." stack[k]

        ver = "-"
        if (line ~ /[ \t]+# Since (v[0-9]+\.[0-9]+\.[0-9]+|unreleased)[ \t]*$/) {
          ver = line
          sub(/^.*[ \t]+# Since /, "", ver)
          sub(/[ \t]*$/, "", ver)
        }

        val = rest
        sub(/^[A-Za-z_][A-Za-z0-9_.-]*:/, "", val)
        sub(/[ \t]+# Since (v[0-9]+\.[0-9]+\.[0-9]+|unreleased)[ \t]*$/, "", val)
        sub(/^[ \t]+/, "", val); sub(/[ \t]+$/, "", val)
        rawval = val
        if (val != "" && substr(val, 1, 1) == "#") val = ""   # comment-only = no value

        if (val != "") {
          annot = 1                       # inline scalar/ERB value
        } else {
          j = i + 1
          while (j <= n && !content[j]) j++
          annot = 1                       # nothing nested: nil-valued leaf
          if (j <= n) {
            nrest = substr(raw[j], indent[j] + 1)
            isseq = (nrest ~ /^-([ \t]|$)/)
            if (indent[j] > ind && !isseq) {
              # Nested mapping keys: a parent. The children carry their own
              # markers (spec §4).
              annot = 0
            } else if (isseq && indent[j] >= ind) {
              # The key HOLDS a list. A list of plain scalars (ignore_paths:)
              # is a value — no list item can carry a marker, so the key must.
              # A list of MAPPINGS is a nesting of keys, which
              # config-yaml-version-map.py classifies as a parent and emits no
              # row for, so demanding a marker there asks for one the annotator
              # will never write: site.interface.ui.footer_links.groups,
              # site.interface.ui.workspace_links.links and auth simple are
              # exactly that shape. The `>= ind` is deliberate — a sequence may
              # sit at the indentation of the key that holds it.
              seqi = indent[j]
              for (m = j; m <= n; m++) {
                if (!content[m]) continue
                if (indent[m] < seqi) break
                mrest = substr(raw[m], indent[m] + 1)
                if (indent[m] == seqi && mrest !~ /^-([ \t]|$)/) break
                if (mrest ~ /^-[ \t]*[A-Za-z_][A-Za-z0-9_.-]*:([ \t]|$)/) { annot = 0; break }
                if (indent[m] > seqi && mrest ~ /^[A-Za-z_][A-Za-z0-9_.-]*:([ \t]|$)/) { annot = 0; break }
              }
            }
          }
        }

        # A block scalar body is free text, not keys.
        if (rawval ~ /^[|>]/) skip = ind + 1

        printf "%s %s %d\n", path, ver, annot
      }
    }
  ' "$1"
}

extract_sites() {  # <kind> <file>
  case "$1" in
    env)  extract_env_sites  "$2" ;;
    yaml) extract_yaml_sites "$2" ;;
  esac
}

# --- Per-file checks -----------------------------------------------------
check_file() {
  local path="$1" kind="$2" decl_re
  local head="$tmp/head.sites" base="$tmp/base.sites"

  extract_sites "$kind" "$path" | sort -u > "$head"
  sites_total=$(( sites_total + $(wc -l < "$head" | tr -d ' ') ))
  markers_total=$(( markers_total + $({ grep -cvE ' - [01]$' "$head" || true; }) ))

  # --- Rule 3: well-formedness. Needs no base ref, so it always runs.
  if [[ "$kind" == "yaml" ]]; then decl_re="$YAML_DECL_RE"; else decl_re="$ENV_DECL_RE"; fi
  { grep -nE "$decl_re" "$path" || true; } \
    | { grep -E "$MARKER_LOOSE_RE" || true; } \
    | { grep -vE "$MARKER_RE" || true; } \
    | sed -E "s#^([0-9]+):#${path}|\1|#" >> "$tmp/fail_malformed"

  # Spec §1: "One marker per line, ever." MARKER_RE is anchored only on the
  # right, so `...  # Since v1.2.3  # Since v1.2.4` satisfies it via the last
  # marker and would otherwise sail through — while the two tools that read
  # markers disagree about which version the line means.
  #
  # Counted with MARKER_LOOSE_RE, not by splitting on the literal `# Since`.
  # A literal split is case-sensitive, which left the two halves of this rule
  # with complementary blind spots that intersect on one real line shape:
  #
  #     #NEW_KEY=1  # since unreleased  # Since unreleased
  #
  # The malformed check above drops that line because the TRAILING marker
  # satisfies the right-anchored recognizer; a literal split finds only one
  # `# Since` and never fires either. Both tools that read markers would then
  # disagree with the file, and resolve-unreleased-versions.sh would rewrite
  # only the trailing one at release — publishing a line that makes two
  # contradictory version claims. Reusing MARKER_LOOSE_RE also keeps this from
  # becoming yet another hand-spelled copy of the recognizer.
  { grep -nE "$decl_re" "$path" || true; } \
    | awk -v file="$path" -v loose="$MARKER_LOOSE_RE" '{
        probe = $0
        if (gsub(loose, "&", probe) > 1) {
          split($0, f, ":"); printf "%s|%s|%s\n", file, f[1], substr($0, length(f[1]) + 2)
        }
      }' >> "$tmp/fail_malformed"

  # --- Rule 4: every line that declares one YAML path agrees on its marker.
  # A dotted path written by several mutually exclusive ERB branches resolves
  # to several declaration lines — site.session.secure has three. Rule 2 is
  # blind to that: it asks whether a key/version PAIR still exists somewhere
  # in the file, so stripping the marker from one branch leaves the other two
  # answering for it and the ratchet passes, while a line that shipped in
  # v0.24.0 silently starts claiming it predates the baseline. Comparing the
  # branches against each other is the only thing that catches it, and it
  # needs no base ref. Env files are excluded on purpose: .env.reference
  # declares five keys twice by design (an active default up top, a commented
  # dev override in the DEVELOPMENT ONLY block) and only the active line is
  # the declaration site, so a bare twin there is the intended state.
  if [[ "$kind" == "yaml" ]]; then
    awk -v file="$path" '
      $3 == 1 {
        if (!($1 in seen)) { seen[$1] = $2; next }
        if (seen[$1] != $2 && !($1 in done)) {
          done[$1] = 1
          printf "%s|%s|%s|%s\n", file, $1, seen[$1], $2
        }
      }' "$head" >> "$tmp/fail_disagree"
  fi

  # --- Rule 5: an env key whose marker sits only on its commented twin.
  # The active, uncommented line is the declaration site — annotate-config-
  # versions.py resolves a key with several matches to exactly that line. A
  # marker on the commented DEVELOPMENT ONLY override instead leaves the real
  # declaration reading as "predates v0.24.0", and rule 2 cannot see the move:
  # it matches key/version PAIRS anywhere in the file, so deleting the marker
  # from line 1910 and appending it to line 2312 keeps the pair present and
  # passes. Rule 4 closes this for YAML by requiring the declarations to agree;
  # env files cannot use that rule, because a bare commented twin is their
  # normal state. This is the env-shaped half of the same hole.
  if [[ "$kind" == "env" ]]; then
    { grep -vE ' - [01]$' "$head" || true; } | cut -d' ' -f1 | sort -u > "$tmp/env.marked"
    { grep -nE '^[A-Z][A-Z0-9_]+=' "$path" || true; } \
      | { grep -vE "$MARKER_RE" || true; } \
      | sed -E 's#^([0-9]+):([A-Z][A-Z0-9_]*)=.*$#\2 \1#' | sort -u > "$tmp/env.activebare"
    cut -d' ' -f1 "$tmp/env.activebare" | sort -u > "$tmp/env.activebare.keys"
    comm -12 "$tmp/env.marked" "$tmp/env.activebare.keys" > "$tmp/env.hidden"
    if [[ -s "$tmp/env.hidden" ]]; then
      join "$tmp/env.hidden" "$tmp/env.activebare" \
        | sed -E "s#^([^ ]+) (.*)\$#${path}|\1|\2#" >> "$tmp/fail_hidden"
    fi
  fi

  [[ -n "$BASE_REF" ]] || return 0

  if git show "$BASE_REF:$path" > "$tmp/base.file" 2>/dev/null; then
    extract_sites "$kind" "$tmp/base.file" | sort -u > "$base"
  else
    : > "$base"   # file is new on this branch: every key in it is new
  fi

  cut -d' ' -f1 "$head" | sort -u > "$tmp/head.keys"
  cut -d' ' -f1 "$base" | sort -u > "$tmp/base.keys"
  comm -13 "$tmp/base.keys" "$tmp/head.keys" > "$tmp/new.keys"
  new_total=$(( new_total + $(wc -l < "$tmp/new.keys" | tr -d ' ') ))

  # --- Rule 1: a new key with a value and no marker.
  # "Unmarked" means NO declaration of the key carries a marker, not "some
  # declaration does not". .env.reference documents several vars twice on
  # purpose — an active default in the variable's own section plus a commented
  # override in the DEVELOPMENT ONLY block (DEFAULT_LOG_LEVEL, LOG_HTTP_CAPTURE
  # and three others) — and annotate-config-versions.py deliberately resolves
  # such a key to its ONE active declaration. Failing because the commented
  # twin is bare would demand a marker that no tool in this family will ever
  # write, on a key that is already correctly marked. For YAML, where several
  # declarations of one path must agree, rule 4 keeps that strict.
  { grep -E ' - 1$' "$head" || true; } | cut -d' ' -f1 | sort -u > "$tmp/unmarked.keys"
  { grep -vE ' - [01]$' "$head" || true; } | cut -d' ' -f1 | sort -u > "$tmp/marked.keys"
  comm -23 "$tmp/unmarked.keys" "$tmp/marked.keys" > "$tmp/bare.keys"
  comm -12 "$tmp/new.keys" "$tmp/bare.keys" | sed "s#^#${path}|#" >> "$tmp/fail_new"

  # Advisory: a new key should say `unreleased`, not a released version — it
  # cannot have shipped in a version that predates its own existence.
  { grep -E ' v[0-9]+\.[0-9]+\.[0-9]+ [01]$' "$head" || true; } \
    | cut -d' ' -f1,2 | sort -u > "$tmp/head.versioned"
  cut -d' ' -f1 "$tmp/head.versioned" | sort -u > "$tmp/head.versioned.keys"
  comm -12 "$tmp/new.keys" "$tmp/head.versioned.keys" > "$tmp/new.versioned.keys"
  if [[ -s "$tmp/new.versioned.keys" ]]; then
    join "$tmp/new.versioned.keys" "$tmp/head.versioned" \
      | sed -E "s#^([^ ]+) (.*)\$#${path}|\1|\2#" >> "$tmp/note_versioned"
  fi

  # --- Rule 2: a concrete version the base ref carries must still be carried
  # by that same key. `unreleased` is excluded from the base side on purpose —
  # resolving it at release time is the sanctioned transition.
  { grep -E ' v[0-9]+\.[0-9]+\.[0-9]+ [01]$' "$base" || true; } \
    | cut -d' ' -f1,2 | sort -u > "$tmp/base.pairs"
  { grep -vE ' - [01]$' "$head" || true; } | cut -d' ' -f1,2 | sort -u > "$tmp/head.pairs"
  comm -23 "$tmp/base.pairs" "$tmp/head.pairs" > "$tmp/lost.pairs"
  [[ -s "$tmp/lost.pairs" ]] || return 0

  # A key that no longer exists took its marker with it — that is allowed.
  cut -d' ' -f1 "$tmp/lost.pairs" | sort -u > "$tmp/lost.keys"
  comm -12 "$tmp/lost.keys" "$tmp/head.keys" > "$tmp/still.keys"
  [[ -s "$tmp/still.keys" ]] || return 0

  join "$tmp/still.keys" "$tmp/lost.pairs" \
    | awk -v file="$path" -v headpairs="$tmp/head.pairs" '
        BEGIN {
          while ((getline l < headpairs) > 0) {
            split(l, p, " ")
            # Explicit if, not a ternary: naming now[p[1]] as an assignment
            # target creates the element before the condition is evaluated.
            if (p[1] in now) { now[p[1]] = now[p[1]] "," p[2] }
            else            { now[p[1]] = p[2] }
          }
        }
        { print file "|" $1 "|" $2 "|" (($1 in now) ? now[$1] : "(no marker)") }
      ' >> "$tmp/fail_changed"
}

for target in "${TARGETS[@]}"; do
  case "$target" in
    *.yaml) check_file "$target" yaml ;;
    *)      check_file "$target" env  ;;
  esac
done

# --- Report --------------------------------------------------------------
failed=0

if [[ -s "$tmp/fail_new" ]]; then
  {
    echo "FAIL: $(wc -l < "$tmp/fail_new" | tr -d ' ') config key(s) added without a version marker:"
    sed -E 's/^([^|]*)\|(.*)$/  \1:  \2/' "$tmp/fail_new"
    echo ""
    echo "These keys are not on ${BASE_DESC}, so they are new. Append a marker to the"
    echo "END of each key's own declaration line — two spaces, then the comment:"
    echo ""
    echo "    NEW_ENV_VAR=default  # Since unreleased"
    echo "    new_yaml_key: <%= ENV['NEW_ENV_VAR'] %>  # Since unreleased"
    echo ""
    echo "Use the literal word 'unreleased', not a version number: the release"
    echo "process rewrites it to the version actually being cut. The marker goes on"
    echo "the key's own line, never on a preceding comment line."
    echo ""
    echo "If you MOVED or renamed one of these keys rather than adding it, copy its"
    echo "existing marker across instead. A key is 'new' here whenever its name or"
    echo "its dotted path is not on the base branch, so renaming a parent makes"
    echo "every child below it look new — and 'unreleased' on a setting that"
    echo "shipped three releases ago is frozen by rule 2 at the next release."
  } >&2
  failed=1
fi

if [[ -s "$tmp/fail_changed" ]]; then
  if [[ $failed -eq 1 ]]; then echo "" >&2; fi
  {
    echo "FAIL: $(wc -l < "$tmp/fail_changed" | tr -d ' ') version marker(s) changed. Shipped markers are immutable:"
    while IFS='|' read -r f k was now; do
      echo "  $f:  $k"
      echo "      base:     # Since $was"
      if [[ "$now" == "(no marker)" ]]; then
        echo "      worktree: (no marker)"
      else
        echo "      worktree: # Since $now"
      fi
    done < "$tmp/fail_changed"
    echo ""
    echo "'Since v0.24.0' is a promise to everyone running v0.24.0 — it is history,"
    echo "not a field to update. Restore the original marker. If a key genuinely"
    echo "changed meaning, rename the key instead; the old name's marker leaves with"
    echo "it. The only sanctioned edit is 'unreleased' -> a real version, made by the"
    echo "release process when it cuts that version."
  } >&2
  failed=1
fi

if [[ -s "$tmp/fail_malformed" ]]; then
  if [[ $failed -eq 1 ]]; then echo "" >&2; fi
  {
    echo "FAIL: $(wc -l < "$tmp/fail_malformed" | tr -d ' ') malformed version marker(s):"
    while IFS='|' read -r f ln text; do
      echo "  $f:$ln:$text"
    done < "$tmp/fail_malformed"
    echo ""
    echo "The accepted forms are exactly these, at the end of the key's own line,"
    echo "with two spaces before the '#':"
    echo ""
    echo "    KEY=value  # Since v1.2.3        (capital S, leading 'v', full patch)"
    echo "    KEY=value  # Since unreleased"
    echo ""
    echo "No other text may follow. '# since v1.2.3', '#Since v1.2.3', '# Since 1.2.3'"
    echo "and '# Since v1.2' are all rejected: every tool in this family matches one"
    echo "regex, and a near-miss marker is invisible to all of them."
  } >&2
  failed=1
fi

if [[ -s "$tmp/fail_disagree" ]]; then
  if [[ $failed -eq 1 ]]; then echo "" >&2; fi
  {
    echo "FAIL: $(wc -l < "$tmp/fail_disagree" | tr -d ' ') YAML path(s) whose declaration lines disagree:"
    while IFS='|' read -r f k a b; do
      echo "  $f:  $k"
      if [[ "$a" == "-" ]]; then echo "      one line says: (no marker)"; else echo "      one line says: # Since $a"; fi
      if [[ "$b" == "-" ]]; then echo "      another says:  (no marker)"; else echo "      another says:  # Since $b"; fi
    done < "$tmp/fail_disagree"
    echo ""
    echo "One setting has one first release. When mutually exclusive ERB branches each"
    echo "write the same key, every one of those lines IS that setting, so they all"
    echo "carry the same marker. A bare line among them is not a missing marker, it is"
    echo "a different claim: it reads as 'predates v0.24.0'. Copy the marker onto the"
    echo "branch that lacks it."
  } >&2
  failed=1
fi

if [[ -s "$tmp/fail_hidden" ]]; then
  if [[ $failed -eq 1 ]]; then echo "" >&2; fi
  {
    echo "FAIL: $(wc -l < "$tmp/fail_hidden" | tr -d ' ') key(s) marked only on a commented declaration:"
    while IFS='|' read -r f k ln; do
      echo "  $f:$ln:  $k is marked elsewhere, but this active declaration is bare"
    done < "$tmp/fail_hidden"
    echo ""
    echo "The uncommented line is the declaration site — it is what a reader sees and"
    echo "what the annotator marks. A marker on the commented DEVELOPMENT ONLY twin"
    echo "instead leaves the real declaration claiming it predates v0.24.0. Move the"
    echo "marker back onto the active line."
  } >&2
  failed=1
fi

if [[ $failed -eq 1 ]]; then
  exit 1
fi

if [[ -z "$BASE_REF" ]]; then
  echo "NOTE: no base branch available — marker syntax was checked, but new-key and"
  echo "      immutability drift were not. Run 'git fetch origin develop' (or set"
  echo "      CONFIG_VERSION_REQUIRE_BASE=1 to make this a failure, as CI does)."
fi

if [[ -s "$tmp/note_versioned" ]]; then
  echo "NOTE: new key(s) annotated with a released version rather than 'unreleased'"
  echo "      (correct only if the key really did ship in that version):"
  sed -E 's/^([^|]*)\|([^|]*)\|(.*)$/      \1:  \2  # Since \3/' "$tmp/note_versioned"
fi

if [[ -n "$BASE_REF" ]]; then
  echo "PASS: config version markers are well-formed, and every marker on the base is intact"
  echo "  (${#TARGETS[@]} file(s), $sites_total annotation site(s), $markers_total marked, $new_total new key(s) vs $BASE_DESC)"
else
  echo "PASS: config version markers are well-formed"
  echo "  (${#TARGETS[@]} file(s), $sites_total annotation site(s), $markers_total marked)"
fi
exit 0
