#!/usr/bin/env bash
#
# resolve-unreleased-versions.sh
#
# Closes the loop on the "Since vX.Y.Z" config annotations.
#
# Adding a config key means annotating it `# Since unreleased` — the author
# cannot know which version will ship it, and guessing produces a wrong number
# that the drift guard then freezes forever. This script is the release-time
# step that turns every such placeholder into the real version.
#
# Run it as part of cutting a release, BEFORE the tag is created:
#
#   bin/envref resolve v0.26.4
#   git add -u && git commit -m "chore(release): resolve Since annotations to v0.26.4"
#   git tag v0.26.4
#
# Ordering matters. Resolve, commit, then tag — so the tagged tree already
# says "Since v0.26.4" and `git show v0.26.4:.env.reference` tells the truth.
#
# Idempotent: with no `unreleased` markers left it reports 0 and exits 0, so it
# is safe to run twice or to wire into a release script unconditionally.
#
set -euo pipefail

# bin/envref finds the checkout once and exports ENVREF_REPO_ROOT, so this
# script, its two siblings and the Python modules all agree by construction
# instead of by four more copies of the same walk. The fallback keeps a direct
# `bash .../<script>.sh` working: every subcommand here reads git history, so
# requiring a real checkout costs nothing it did not already need.
REPO_ROOT="${ENVREF_REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
if [[ -z "$REPO_ROOT" || ! -d "$REPO_ROOT/etc/defaults" ]]; then
  echo "FAIL: cannot locate the onetimesecret checkout." >&2
  echo "      Run this through bin/envref, or set ENVREF_REPO_ROOT." >&2
  exit 2
fi
cd "$REPO_ROOT"

VERSION="${1:-}"

if [[ -z "$VERSION" ]]; then
  echo "usage: $0 vX.Y.Z" >&2
  echo "" >&2
  echo "Rewrites every '# Since unreleased' marker in the config files to the" >&2
  echo "given version. Run while cutting a release, before tagging." >&2
  exit 2
fi

# A marker must never carry a pre-release or a malformed version: it is written
# once and then frozen by bin/envref check, so a typo here is
# permanent history.
if [[ ! "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "FAIL: '$VERSION' is not a stable release version (expected vX.Y.Z, no suffix)." >&2
  echo "      Pre-release tags (-rc0, -PRE) must not appear in an annotation:" >&2
  echo "      a self-hoster on the stable release needs to know the stable version." >&2
  exit 1
fi

if git rev-parse -q --verify "refs/tags/$VERSION" >/dev/null 2>&1; then
  echo "FAIL: tag $VERSION already exists." >&2
  echo "      Resolve annotations BEFORE tagging, or the tagged tree will still" >&2
  echo "      say 'unreleased'. To recover: resolve, commit, then move the tag." >&2
  exit 1
fi

# Discovered, not listed — the same glob bin/envref check uses.
# A hardcoded list silently diverges the moment a defaults file is added: the
# ratchet would see the new file, treat every key in it as new and require
# `# Since unreleased` on each, and then this script would skip the file at
# release time and still report PASS. The tag would ship a whole config file
# claiming "arrives in the next release", and nothing would ever correct it —
# rule 2 freezes concrete versions only, so `unreleased` stays invisible to the
# guard in every release after that one too.
TARGETS=(.env.reference)
for y in etc/defaults/*.yaml etc/defaults/*.yml; do
  if [[ -f "$y" ]]; then TARGETS+=("$y"); fi
done

# `[ \t]` inside a bracket expression is the three characters space,
# backslash and `t` — not a tab. The §1 recognizer accepts a tab before the
# `#`, and check-config-versions.sh matches it with [[:blank:]], so writing
# the class by hand here would leave a tab-form marker uncounted AND
# unrewritten: it would ship as `unreleased` forever.
UNRESOLVED_RE='[[:blank:]]+# Since unreleased[[:blank:]]*$'

# Declaration lines only — the same set bin/envref check
# polices. Rule 3 there inspects declaration lines deliberately, so that the
# header blocks explaining this convention (which must quote an example marker
# to explain it) do not trip it. Applying the rewrite to every line instead
# gives the release step a wider reach than the guard that watches it: a
# comment line ending in the marker form gets rewritten, counted in the total
# this script prints, and passed by its own re-grep. logging.defaults.yaml is
# one edit away from having such a line — its legend row survives only because
# of the description column after the marker — and the result would be a
# legend that explains the convention with a concrete version in it.
ENV_DECL_RE='^#?[A-Z][A-Z0-9_]+='
YAML_DECL_RE='^[[:space:]]*(- )?[A-Za-z0-9_][A-Za-z0-9_.-]*[[:blank:]]*:([[:space:]]|$)'

scratch=$(mktemp)
trap 'rm -f "$scratch"' EXIT

total=0
for f in "${TARGETS[@]}"; do
  [[ -f "$f" ]] || { echo "FAIL: $f not found" >&2; exit 1; }

  case "$f" in
    *.yaml|*.yml) decl_re="$YAML_DECL_RE" ;;
    *)            decl_re="$ENV_DECL_RE" ;;
  esac

  n=$({ grep -E "$decl_re" "$f" || true; } | { grep -cE "$UNRESOLVED_RE" || true; })
  if [[ "$n" -gt 0 ]]; then
    # Anchored to end-of-line so prose that happens to contain the phrase is
    # untouched; only a real trailing marker is rewritten.
    #
    # NOT `sed -i`: the GNU form (`sed -i -E`) and the BSD form (`sed -i '' -E`)
    # are mutually incompatible. Under BSD sed — macOS is a supported host, see
    # the bash 3.2 parity gate in CI — `-E` is taken as the backup SUFFIX, the
    # script is then compiled as a BRE where `(` and `+` are literals, nothing
    # matches, and a stray `.env.reference-E` is left behind. Redirect plus
    # `cat` back over the original behaves identically everywhere and keeps the
    # file mode. The result is then re-checked rather than trusted: the count
    # above was taken BEFORE the rewrite, so on its own it would report success
    # for a substitution that did nothing.
    sed -E "/$decl_re/ s/([[:blank:]]+# Since )unreleased([[:blank:]]*)\$/\1${VERSION}\2/" "$f" > "$scratch"
    cat "$scratch" > "$f"

    left=$({ grep -E "$decl_re" "$f" || true; } | { grep -cE "$UNRESOLVED_RE" || true; })
    if [[ "$left" -ne 0 ]]; then
      echo "FAIL: $f still carries $left 'unreleased' marker(s) after the rewrite" >&2
      exit 1
    fi

    echo "  $f: $n marker(s) -> $VERSION"
    total=$((total + n))
  fi
done

if [[ "$total" -eq 0 ]]; then
  echo "PASS: no unresolved markers — nothing to do for $VERSION"
  exit 0
fi

echo "PASS: resolved $total marker(s) to $VERSION"
echo ""
echo "Next: review 'git diff', commit, THEN tag $VERSION."
