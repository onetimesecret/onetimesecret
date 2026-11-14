#!/usr/bin/env bash
#
# scripts/install-shell-lint-tools.sh
#
# Installs the pinned shellcheck and actionlint that scripts/check-shell-lint.sh
# expects, into the directory given as the only argument. Linux x86_64 only:
# the recorded digests are for those release assets.
#
# The versions and SHA-256 digests are read from the `env:` block of
# .github/workflows/static-analysis.yml, so GitHub and the GitLab `shell-lint`
# job (.gitlab/ci/lint.yml) install the same binaries from one set of pins.
# The GitHub workflow still installs them with its own inline step.
#
# Usage:
#   scripts/install-shell-lint-tools.sh /usr/local/bin
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="${REPO_ROOT}/.github/workflows/static-analysis.yml"

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

[ "$#" -eq 1 ] || fail "usage: $0 <install-dir>"
DEST="$1"
[ "$(uname -s)-$(uname -m)" = "Linux-x86_64" ] \
  || fail "only Linux x86_64 is supported: the pinned digests are for those assets"

# Reads `  NAME: 'value'` from the workflow's top-level env block.
pin() { # <name>
  local value
  value="$(sed -nE "s/^  $1: '([^']+)'\$/\\1/p" "$WORKFLOW")"
  [ -n "$value" ] && [ "$(printf '%s\n' "$value" | wc -l)" -eq 1 ] \
    || fail "expected exactly one $1 pin in $WORKFLOW"
  printf '%s' "$value"
}

SHELLCHECK_VERSION="$(pin SHELLCHECK_VERSION)"
SHELLCHECK_SHA256="$(pin SHELLCHECK_SHA256)"
ACTIONLINT_VERSION="$(pin ACTIONLINT_VERSION)"
ACTIONLINT_SHA256="$(pin ACTIONLINT_SHA256)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fetch() { # <url> <file> <sha256>
  curl -fsSL --retry 3 --retry-all-errors -o "$WORK/$2" "$1"
  printf '%s  %s\n' "$3" "$WORK/$2" | sha256sum -c - > /dev/null \
    || fail "SHA-256 mismatch for $1"
}

fetch "https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/shellcheck-v${SHELLCHECK_VERSION}.linux.x86_64.tar.xz" \
  shellcheck.tar.xz "$SHELLCHECK_SHA256"
tar -xJf "$WORK/shellcheck.tar.xz" -C "$WORK" "shellcheck-v${SHELLCHECK_VERSION}/shellcheck"

fetch "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz" \
  actionlint.tar.gz "$ACTIONLINT_SHA256"
tar -xzf "$WORK/actionlint.tar.gz" -C "$WORK" actionlint

mkdir -p "$DEST"
install -m 0755 "$WORK/shellcheck-v${SHELLCHECK_VERSION}/shellcheck" "$DEST/shellcheck"
install -m 0755 "$WORK/actionlint" "$DEST/actionlint"

found_shellcheck="$("$DEST/shellcheck" --version | awk '/^version:/ { print $2 }')"
found_actionlint="$("$DEST/actionlint" --version | head -n1)"
[ "$found_shellcheck" = "$SHELLCHECK_VERSION" ] \
  || fail "installed shellcheck reports $found_shellcheck, pinned $SHELLCHECK_VERSION"
[ "$found_actionlint" = "$ACTIONLINT_VERSION" ] \
  || fail "installed actionlint reports $found_actionlint, pinned $ACTIONLINT_VERSION"

printf 'Installed shellcheck %s and actionlint %s in %s\n' \
  "$SHELLCHECK_VERSION" "$ACTIONLINT_VERSION" "$DEST"
