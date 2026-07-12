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
#   - .devcontainer/compose.yaml ruby image tag major.minor == .ruby-version major.minor
#   - .devcontainer/devcontainer.json node feature version == .node-version major
#     (devcontainer features can't read pin files, so those are duplicated by
#     necessity — this guard keeps the duplication in lockstep; C8 → C9)
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

# --- Devcontainer (compose image + node feature) ----------------------
dc_compose=".devcontainer/compose.yaml"
dc_json=".devcontainer/devcontainer.json"

if [[ -f "$dc_compose" ]]; then
  # e.g. image: ghcr.io/rails/devcontainer/images/ruby:3.4.9
  dc_ruby_tag="$(grep -Eo 'devcontainer/images/ruby:[0-9][0-9.]*' "$dc_compose" | head -n1 | cut -d: -f2)"
  [[ -n "$dc_ruby_tag" ]] || fail "ruby image tag not found in $dc_compose"
  if [[ "$dc_ruby_tag" == "$ruby_mm" || "$dc_ruby_tag" == "$ruby_mm"[.@-]* ]]; then
    echo "PASS: $dc_compose ruby image tag ($dc_ruby_tag) matches .ruby-version major.minor ($ruby_mm)"
  else
    fail "$dc_compose ruby image tag ($dc_ruby_tag) does not start with .ruby-version major.minor ($ruby_mm)"
  fi
else
  fail "$dc_compose not found"
fi

if [[ -f "$dc_json" ]]; then
  # e.g. "ghcr.io/devcontainers/features/node:1": { "version": "22" }
  dc_node="$(grep -A1 'features/node' "$dc_json" | grep -Eo '"version"[[:space:]]*:[[:space:]]*"[0-9]+"' | grep -Eo '[0-9]+' | head -n1)"
  [[ -n "$dc_node" ]] || fail "node feature version not found in $dc_json"
  if [[ "$dc_node" == "$node_major" ]]; then
    echo "PASS: $dc_json node feature version ($dc_node) matches .node-version major ($node_major)"
  else
    fail "$dc_json node feature version ($dc_node) does not match .node-version major ($node_major)"
  fi
else
  fail "$dc_json not found"
fi

echo "PASS: all version pins are in sync"
exit 0
