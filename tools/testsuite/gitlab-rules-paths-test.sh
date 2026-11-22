#!/usr/bin/env bash
#
# tools/testsuite/gitlab-rules-paths-test.sh
#
# Asserts that the GitLab path lists in .gitlab/ci/rules.yml select what the
# GitHub path filters in .github/workflows/ci.yml select.
#
# WHAT THIS PROTECTS
#
# The `ruby` and `typescript` lists in rules.yml are copies of the filters of
# the same names in ci.yml's `changes` job, rewritten for GitLab: a pattern
# that ends in `/**` ends in `/**/*`, because GitLab's File.fnmatch matches a
# trailing `/**` one directory level deep (migration plan §7, S3 results).
# A path added on one side only, or a copied `/**` left as it is, makes the
# GitLab smoke-lane job skip a change that GitHub's smoke-test job would run
# on. Nothing else fails when that happens: a job that rules:changes leaves
# out is simply absent from the pipeline.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
# shellcheck source=tools/testsuite/lib/assert.sh
source "${TEST_DIR}/lib/assert.sh"

WORKFLOW="${REPO_ROOT}/.github/workflows/ci.yml"
RULES="${REPO_ROOT}/.gitlab/ci/rules.yml"
RUBY_JOBS="${REPO_ROOT}/.gitlab/ci/ruby.yml"

printf '%s\n' "$ASSERT_SUITE"

for file in "$WORKFLOW" "$RULES" "$RUBY_JOBS"; do
  if [ ! -f "$file" ]; then
    printf 'FAIL: %s not found\n' "$file" >&2
    exit 1
  fi
done

# The patterns of one dorny/paths-filter filter in ci.yml, one per line,
# unquoted. Filters are 12-space keys inside the `filters: |` block, their
# patterns 14-space list items.
github_filter() { # <name>
  awk -v key="$1" '
    $0 == "            " key ":" { on = 1; next }
    on && /^            [a-z_]+:$/ { exit }
    on && /^              - / {
      sub(/^              - /, "")
      gsub(/^'\''|'\''$/, "")
      print
    }
  ' "$WORKFLOW"
}

# The patterns of one list under `.changes:` in rules.yml.
gitlab_list() { # <name>
  awk -v key="$1" '
    $0 == "  " key ":" { on = 1; next }
    on && /^  [a-z_]+:$/ { exit }
    on && /^    - / {
      sub(/^    - /, "")
      gsub(/^'\''|'\''$/, "")
      print
    }
  ' "$RULES"
}

# GitHub's `/**` (any depth) is GitLab's `/**/*`.
for_gitlab() { sed 's|/\*\*$|/**/*|'; }

count() { printf '%s' "$1" | grep -c ''; }

for name in ruby typescript; do
  protects "rules.yml ${name} selects what ci.yml's ${name} filter selects"
  github="$(github_filter "$name")"
  gitlab="$(gitlab_list "$name")"
  assert_at_least "ci.yml ${name} filter extracted" 10 "$(count "$github")" "patterns"
  assert_at_least "rules.yml ${name} list extracted" 10 "$(count "$gitlab")" "patterns"
  assert_eq "rules.yml ${name} is ci.yml's filter with /** rewritten to /**/*" \
    "$(printf '%s\n' "$github" | for_gitlab)" "$gitlab"
done

protects "no GitLab list ends a pattern in /**, and each fits one rules:changes"
for name in ci ruby typescript; do
  gitlab="$(gitlab_list "$name")"
  assert_eq "rules.yml ${name} has no pattern ending in /**" "" \
    "$(printf '%s\n' "$gitlab" | grep '/\*\*$' || true)"
  n="$(count "$gitlab")"
  within=false
  [ "$n" -le 50 ] && within=true
  assert_eq "rules.yml ${name} has at most 50 patterns (it has ${n})" true "$within"
done

protects "a change to the pipeline or the commands its jobs call selects the lane jobs (plan §4.4)"
ci_list="$(gitlab_list ci)"
for path in .gitlab-ci.yml '.gitlab/ci/**/*' 'tools/ci/**/*' bin/ci; do
  assert_contains "rules.yml ci lists ${path}" "$path" "$ci_list"
done

protects "the smoke-lane job is selected by all three lists"
for name in ci ruby typescript; do
  assert_contains "smoke-lane has a rule for ${name}" \
    "- changes: !reference [.changes, ${name}]" "$(sed -n '/^smoke-lane:/,/^[a-z]/p' "$RUBY_JOBS")"
done

finish
