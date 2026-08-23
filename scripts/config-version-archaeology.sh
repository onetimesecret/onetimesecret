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
# METHOD: scan release trees, not commits.
#
# The obvious approach — pickaxe the commit that introduced a key, then find the
# first tag containing that commit — is wrong here in four separate ways, each
# of which produced real bad data when this script used to work that way:
#
#   1. 17 of the 85 stable tags are not ancestors of HEAD (release branches
#      tagged without a merge back). Filtering containment by `--merged HEAD`
#      skipped them, dating FROM_NAME to v0.24.0 when it shipped in v0.23.5.
#   2. A key mentioned in prose dates from the prose. GITHUB_KEY's only
#      occurrence at v0.24.0 is a code sample inside the vendored third-party
#      file apps/web/auth/docs/rodauth-reference-2.41+.md.
#   3. A Ruby-only pattern misses the frontend. NODE_ENV has been read by
#      src/utils/debug.ts since v0.19.0 via process.env, not ENV[].
#   4. `--reverse | head -1` takes the first match ever, so a key that was
#      removed and later reintroduced (STRIPE_WEBHOOK_SIGNING_SECRET, absent
#      from all of v0.23.x) is dated to the abandoned first attempt.
#
# So instead: ask each released tree directly whether it consumes the key. The
# answer is the earliest tag beginning an UNBROKEN run of releases that consume
# it through to HEAD — which is what a self-hoster actually needs to know, and
# which makes reintroduction fall out for free. Scanning is per-tag, not
# per-key-per-tag: one pass over a tag yields every key it consumes, so the
# cost is ~85 greps rather than ~30,000.
#
# Requires full history and tags — a shallow clone silently reports everything
# as introduced at the graft point. The script refuses to run on one.
#
# Usage:
#   scripts/config-version-archaeology.sh                  # all keys in .env.reference
#   scripts/config-version-archaeology.sh KEY [KEY...]     # specific keys
#
# Output: TSV on stdout, progress on stderr.
#   key <TAB> first_release <TAB> evidence
#
# first_release is a stable version, or PRE_HISTORY (consumed by the oldest tag
# scanned, so it predates the annotation baseline), or UNRELEASED (consumed at
# HEAD but by no tag yet).
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if [[ "$(git rev-parse --is-shallow-repository)" == "true" ]]; then
  echo "FAIL: shallow clone — history is truncated and every result would be wrong." >&2
  echo "      Run: git fetch --unshallow && git fetch --tags" >&2
  exit 1
fi

# Every stable release, oldest first, ordered by version rather than by date:
# tags on release branches are not created in version order, and it is version
# order that defines "the release before this one".
#
# NOTE: deliberately NOT filtered by `--merged HEAD`. A tag that contains the
# key shipped the key, whether or not its commits were ever merged back.
mapfile -t TAGS < <(
  git tag | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V
)
if [[ ${#TAGS[@]} -eq 0 ]]; then
  echo "FAIL: no stable release tags found. Run: git fetch --tags" >&2
  exit 1
fi
echo "info: ${#TAGS[@]} stable tags, ${TAGS[0]} .. ${TAGS[-1]}" >&2

# --- key list ------------------------------------------------------------
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [[ $# -gt 0 ]]; then
  printf '%s\n' "$@" | sort -u > "$WORK/keys.txt"
else
  sed -n -E 's/^#?([A-Z][A-Z0-9_]+)=.*/\1/p' .env.reference | sort -u > "$WORK/keys.txt"
fi
echo "info: resolving $(wc -l < "$WORK/keys.txt" | tr -d ' ') key(s) across ${#TAGS[@]} release trees" >&2

# --- what counts as "this release consumes KEY" --------------------------
# Real consumption sites only. Markdown is excluded wholesale: a variable named
# in documentation is not a variable the release supports, and the vendored
# Rodauth reference doc is full of examples for keys this app never reads.
#
# Paths are the places config is actually read or declared. apps/web/auth/docs
# is vendored upstream material and is excluded explicitly.
PATHSPEC=(
  lib apps etc src bin config.ru .env.reference .env.example
  ':(exclude)*.md'
  ':(exclude)apps/web/auth/docs'
)

# Ruby ENV['X'] / ENV["X"] / ENV.fetch('X' ; JS/TS process.env.X and
# import.meta.env.X ; and a bare X= declaration in a .env file or shell.
SCAN_RE="(ENV(\[|\.fetch\()['\"][A-Z][A-Z0-9_]+['\"]|(process|import\.meta)\.env\.[A-Z][A-Z0-9_]+|^[[:space:]]*#?[A-Z][A-Z0-9_]+=)"

# Emit the set of keys consumed by one tree.
keys_in_tree() {
  git grep -h -I -E -o "$SCAN_RE" "$1" -- "${PATHSPEC[@]}" 2>/dev/null \
    | grep -oE '[A-Z][A-Z0-9_]+' \
    | grep -vxE 'ENV|PATH' \
    | sort -u
}

# --- scan every release tree once ---------------------------------------
for tag in "${TAGS[@]}"; do
  keys_in_tree "$tag" > "$WORK/tag.$tag"
done
keys_in_tree HEAD > "$WORK/tag.HEAD"
echo "info: scanned ${#TAGS[@]} release trees" >&2

# --- resolve each key ----------------------------------------------------
# Walk releases newest -> oldest while the key is still consumed. The oldest
# tag in that unbroken run is the answer; a gap ends the run, so a key that was
# removed and reintroduced is dated to the reintroduction.
while read -r key; do
  [[ -n "$key" ]] || continue

  if ! grep -qxF "$key" "$WORK/tag.HEAD"; then
    printf '%s\tNOT_CONSUMED\tabsent from HEAD\n' "$key"
    continue
  fi

  first=""
  broke=""
  for (( i=${#TAGS[@]}-1; i>=0; i-- )); do
    if grep -qxF "$key" "$WORK/tag.${TAGS[$i]}"; then
      first="${TAGS[$i]}"
    else
      broke="${TAGS[$i]}"
      break
    fi
  done

  if [[ -z "$first" ]]; then
    printf '%s\tUNRELEASED\tconsumed at HEAD, in no release yet\n' "$key"
  elif [[ "$first" == "${TAGS[0]}" ]]; then
    printf '%s\tPRE_HISTORY\tconsumed since the oldest tag scanned (%s)\n' "$key" "${TAGS[0]}"
  elif [[ -n "$broke" ]]; then
    printf '%s\t%s\tabsent at %s, consumed continuously since\n' "$key" "$first" "$broke"
  else
    printf '%s\t%s\tconsumed continuously since\n' "$key" "$first"
  fi
done < "$WORK/keys.txt"
