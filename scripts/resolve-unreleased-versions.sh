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
#   scripts/resolve-unreleased-versions.sh v0.26.4
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

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
# once and then frozen by scripts/check-config-versions.sh, so a typo here is
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

TARGETS=(
  .env.reference
  etc/defaults/config.defaults.yaml
  etc/defaults/auth.defaults.yaml
  etc/defaults/logging.defaults.yaml
)

total=0
for f in "${TARGETS[@]}"; do
  [[ -f "$f" ]] || { echo "FAIL: $f not found" >&2; exit 1; }

  n=$(grep -cE '[ \t]+# Since unreleased[ \t]*$' "$f" || true)
  if [[ "$n" -gt 0 ]]; then
    # Anchored to end-of-line so prose that happens to contain the phrase is
    # untouched; only a real trailing marker is rewritten.
    sed -i -E "s/([ \t]+# Since )unreleased([ \t]*)\$/\1${VERSION}\2/" "$f"
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
