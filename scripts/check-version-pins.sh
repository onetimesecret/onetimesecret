#!/usr/bin/env bash
#
# check-version-pins.sh
#
# Dependency-free (grep/sed/cut only) guard that asserts the Docker image tags
# stay in sync with the single-source-of-truth pin files (.node-version and
# .ruby-version). Any drift makes this exit non-zero so CI goes red.
#
# Checks:
#   - docker/base.dockerfile NODE_IMAGE_TAG major == .node-version major
#   - docker/base.dockerfile RUBY_IMAGE_TAG major.minor == .ruby-version major.minor
#   - Dockerfile             RUBY_IMAGE_TAG major.minor == .ruby-version major.minor
#
set -euo pipefail

# Run from the repo root regardless of how the script is invoked.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

fail() { echo "FAIL: $1" >&2; exit 1; }

# --- Read pins --------------------------------------------------------
[[ -f .node-version ]] || fail ".node-version not found"
[[ -f .ruby-version ]] || fail ".ruby-version not found"

node_major="$(sed 's/[^0-9].*$//' .node-version | tr -d '[:space:]')"
[[ -n "$node_major" ]] || fail "could not read major version from .node-version"

ruby_full="$(tr -d '[:space:]' < .ruby-version)"
ruby_mm="$(echo "$ruby_full" | cut -d. -f1-2)"
[[ -n "$ruby_mm" ]] || fail "could not read major.minor from .ruby-version"

# --- Helper: extract an ARG <NAME>=<value> from a Dockerfile ----------
arg_value() {
  # $1 = file, $2 = ARG name; prints the value (text after '=', before any space)
  grep -E "^ARG[[:space:]]+$2=" "$1" | head -n1 | sed -E "s/^ARG[[:space:]]+$2=//" | cut -d' ' -f1
}

# --- Node image tag in docker/base.dockerfile -------------------------
base_df="docker/base.dockerfile"
[[ -f "$base_df" ]] || fail "$base_df not found"

node_tag="$(arg_value "$base_df" NODE_IMAGE_TAG)"
[[ -n "$node_tag" ]] || fail "NODE_IMAGE_TAG not found in $base_df"
if [[ "$node_tag" == "$node_major" || "$node_tag" == "$node_major"[.@-]* ]]; then
  echo "PASS: $base_df NODE_IMAGE_TAG ($node_tag) matches .node-version major ($node_major)"
else
  fail "$base_df NODE_IMAGE_TAG ($node_tag) does not start with .node-version major ($node_major)"
fi

# --- Ruby image tag in docker/base.dockerfile and Dockerfile ----------
for df in "$base_df" "Dockerfile"; do
  [[ -f "$df" ]] || fail "$df not found"
  ruby_tag="$(arg_value "$df" RUBY_IMAGE_TAG)"
  [[ -n "$ruby_tag" ]] || fail "RUBY_IMAGE_TAG not found in $df"
  if [[ "$ruby_tag" == "$ruby_mm" || "$ruby_tag" == "$ruby_mm"[.@-]* ]]; then
    echo "PASS: $df RUBY_IMAGE_TAG ($ruby_tag) matches .ruby-version major.minor ($ruby_mm)"
  else
    fail "$df RUBY_IMAGE_TAG ($ruby_tag) does not start with .ruby-version major.minor ($ruby_mm)"
  fi
done

echo "PASS: all version pins are in sync"
exit 0
