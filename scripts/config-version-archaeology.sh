#!/usr/bin/env bash
#
# config-version-archaeology.sh
#
# Derives, from git history, the first released version of every configuration
# key — the raw material for the "Since vX.Y.Z" annotations in .env.reference
# and etc/defaults/*.yaml.
#
# This is a ONE-TIME BACKFILL tool, not a build step. Once a key carries its
# annotation in the config file, that comment is the source of truth and this
# script is only used to re-derive/audit it. Annotations are immutable: a key
# that shipped in v0.24.0 is "Since v0.24.0" forever, regardless of later edits.
#
# Method, per key:
#   1. Find the earliest commit whose diff adds a *definition site* for the key
#      (an ENV['KEY'] read, or a KEY= assignment line). Word boundaries keep
#      SECRET from matching SECRET_KEY — the naive `git log -S KEY` pickaxe
#      reports a substring match and dates keys far too early.
#   2. Find the earliest stable release tag (vX.Y.Z, no pre-release suffix)
#      that contains that commit and is reachable from HEAD.
#
# A key whose introducing commit is in no release tag yet is UNRELEASED: it
# ships in the next version, so its annotation is written once that is known.
#
# Requires full history — a shallow clone silently reports everything as
# introduced at the graft point. The script refuses to run on one.
#
# Usage:
#   scripts/config-version-archaeology.sh                  # all env vars
#   scripts/config-version-archaeology.sh KEY [KEY...]     # specific keys
#   PARALLEL=8 scripts/config-version-archaeology.sh       # tune concurrency
#
# Output: TSV on stdout, progress on stderr.
#   key <TAB> first_release <TAB> commit <TAB> commit_date <TAB> subject
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PARALLEL="${PARALLEL:-4}"

if [[ "$(git rev-parse --is-shallow-repository)" == "true" ]]; then
  echo "FAIL: shallow clone — history is truncated and every result would be wrong." >&2
  echo "      Run: git fetch --unshallow && git fetch --tags" >&2
  exit 1
fi

# Stable releases only, oldest first. Pre-releases (-rc0, -PRE) and archive/
# tags are not what a self-hoster runs, so they never appear in an annotation.
mapfile -t STABLE_TAGS < <(
  git tag --merged HEAD --sort=creatordate | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$'
)
if [[ ${#STABLE_TAGS[@]} -eq 0 ]]; then
  echo "FAIL: no stable release tags reachable from HEAD. Run: git fetch --tags" >&2
  exit 1
fi
echo "info: ${#STABLE_TAGS[@]} stable tags, ${STABLE_TAGS[0]} .. ${STABLE_TAGS[-1]}" >&2

# --- key list ------------------------------------------------------------
if [[ $# -gt 0 ]]; then
  printf '%s\n' "$@" > /tmp/.cva_keys.$$
else
  sed -n -E 's/^#?([A-Z][A-Z0-9_]+)=.*/\1/p' .env.reference | sort -u > /tmp/.cva_keys.$$
fi
KEY_COUNT=$(wc -l < /tmp/.cva_keys.$$ | tr -d ' ')
echo "info: resolving $KEY_COUNT key(s) with PARALLEL=$PARALLEL" >&2

# --- per-key resolution --------------------------------------------------
# Exported so the xargs subshells can call it.
resolve_key() {
  local key="$1" commit tag date subject

  # Definition sites: ENV['KEY'] / ENV["KEY"] / ENV.fetch('KEY' / KEY= .
  # \b before KEY= is what stops FOO_KEY= from being read as KEY= .
  commit=$(git log --format=%H --reverse \
    -G"(ENV(\[|\.fetch\()['\"]${key}['\"]|\b${key}=)" 2>/dev/null | head -1)

  if [[ -z "$commit" ]]; then
    printf '%s\tNOT_FOUND\t-\t-\t-\n' "$key"
    return
  fi

  # Earliest stable tag containing the commit. --contains is the expensive
  # call, so ask once and take the oldest answer.
  tag=$(git tag --contains "$commit" --merged HEAD --sort=creatordate 2>/dev/null \
    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1)

  date=$(git log -1 --format=%ad --date=short "$commit")
  subject=$(git log -1 --format=%s "$commit" | tr '\t' ' ' | cut -c1-72)

  printf '%s\t%s\t%s\t%s\t%s\n' "$key" "${tag:-UNRELEASED}" "${commit:0:9}" "$date" "$subject"
}
export -f resolve_key

xargs -a /tmp/.cva_keys.$$ -P "$PARALLEL" -I{} bash -c 'resolve_key "$@"' _ {}
rm -f /tmp/.cva_keys.$$
