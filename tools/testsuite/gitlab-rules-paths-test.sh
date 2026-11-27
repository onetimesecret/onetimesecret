#!/usr/bin/env bash
#
# tools/testsuite/gitlab-rules-paths-test.sh
#
# Asserts that the GitLab path lists in .gitlab/ci/rules.yml select what the
# GitHub path filters select, and that the Ruby jobs in .gitlab/ci/ruby.yml
# use them.
#
# WHAT THIS PROTECTS
#
# The `ruby` and `typescript` lists in rules.yml are copies of the filters of
# the same names in ci.yml's `changes` job, and `auth` is a copy of
# .github/auth-paths.yml, all rewritten for GitLab: a pattern that ends in
# `/**` ends in `/**/*`, because GitLab's File.fnmatch matches a trailing
# `/**` one directory level deep (migration plan §7, S3 results). A path
# added on one side only, or a copied `/**` left as it is, makes a GitLab
# lane job skip a change that the GitHub job would run on. Nothing else fails
# when that happens: a job that rules:changes leaves out is simply absent
# from the pipeline, and the pipeline is green without it.
#
# The same holds for a lane that no job names. A directory added under
# tests/lanes/ runs nowhere until a job in ruby.yml lists it, so every lane
# must be in a job there or in the list below of lanes that run elsewhere.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
# shellcheck source=tools/testsuite/lib/assert.sh
source "${TEST_DIR}/lib/assert.sh"

WORKFLOW="${REPO_ROOT}/.github/workflows/ci.yml"
AUTH_PATHS="${REPO_ROOT}/.github/auth-paths.yml"
RULES="${REPO_ROOT}/.gitlab/ci/rules.yml"
RUBY_JOBS="${REPO_ROOT}/.gitlab/ci/ruby.yml"
FRONTEND_JOBS="${REPO_ROOT}/.gitlab/ci/frontend.yml"
LANES_DIR="${REPO_ROOT}/tests/lanes"

printf '%s\n' "$ASSERT_SUITE"

for file in "$WORKFLOW" "$AUTH_PATHS" "$RULES" "$RUBY_JOBS" "$FRONTEND_JOBS"; do
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

# The patterns of .github/auth-paths.yml's `auth` list, one per line, unquoted.
github_auth_paths() {
  awk '
    $0 == "auth:" { on = 1; next }
    on && /^[^ #]/ { exit }
    on && /^  - / {
      sub(/^  - /, "")
      gsub(/^'\''|'\''$/, "")
      print
    }
  ' "$AUTH_PATHS"
}

# The items of one list under a top-level key of rules.yml (`.changes` for
# the path lists, `.rules` for the rule sets), unquoted. The list ends at the
# next key at its own depth or above.
gitlab_block() { # <top-level key> <name>
  awk -v top="$1" -v key="$2" '
    /^[^ #]/ { inside = ($0 == top ":") }
    inside && $0 == "  " key ":" { on = 1; next }
    on && /^ {0,2}[^ #]/ { exit }
    on && /^    - / {
      sub(/^    - /, "")
      gsub(/^'\''|'\''$/, "")
      print
    }
  ' "$RULES"
}
gitlab_list() { gitlab_block .changes "$1"; }

# One job of a GitLab CI file: from its key to the next top-level key.
gitlab_job() { # <file> <job>
  awk -v job="$2" '
    /^[^ #]/ { on = ($0 == job ":") }
    on
  ' "$1"
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

protects "rules.yml auth selects what .github/auth-paths.yml selects"
# The .github/ entries of auth-paths.yml select GitHub's own selection
# machinery and workflows. On GitLab that is the `ci` list, which the auth
# rule set also names.
github_auth="$(github_auth_paths | grep -v '^\.github/')"
gitlab_auth="$(gitlab_list auth)"
assert_at_least "auth-paths.yml auth list extracted" 30 "$(count "$github_auth")" "patterns"
assert_at_least "rules.yml auth list extracted" 30 "$(count "$gitlab_auth")" "patterns"
assert_eq "rules.yml auth is auth-paths.yml without .github/ entries, /** rewritten to /**/*" \
  "$(printf '%s\n' "$github_auth" | for_gitlab)" "$gitlab_auth"

protects "no GitLab list ends a pattern in /**, and each fits one rules:changes"
for name in ci ruby typescript auth; do
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
    "- changes: !reference [.changes, ${name}]" "$(gitlab_job "$RUBY_JOBS" smoke-lane)"
done

protects "the rule sets name the lists they are documented to use"
ruby_rules="$(gitlab_block .rules ruby-lanes)"
auth_rules="$(gitlab_block .rules auth-lanes)"
nightly_rules="$(gitlab_block .rules nightly-lanes)"
for name in ci ruby; do
  assert_contains "ruby-lanes has a rule for ${name}" "changes: !reference [.changes, ${name}]" "$ruby_rules"
done
for name in ci auth; do
  assert_contains "auth-lanes has a rule for ${name}" "changes: !reference [.changes, ${name}]" "$auth_rules"
done
assert_not_contains "no path selects the billing configurations" "changes:" "$nightly_rules"
# shellcheck disable=SC2016 # GitLab CI variables, matched as rules.yml writes them
{
  assert_contains "auth-lanes reads the ci:auth label" \
    '$CI_MERGE_REQUEST_LABELS =~ /(^|,)ci:auth(,|$)/' "$auth_rules"
  assert_contains "auth-lanes has a rule for pushes" '$CI_PIPELINE_SOURCE == "push"' "$auth_rules"
  assert_contains "the billing configurations run in scheduled and manual pipelines" \
    '$CI_PIPELINE_SOURCE =~ /^(schedule|web|api)$/' "$nightly_rules"
  assert_contains "the billing configurations run in tag pipelines" '$CI_COMMIT_TAG' "$nightly_rules"
}

protects "each Ruby job uses the rule set of its GitHub job"
for pair in rubocop:ruby-lanes ruby-lanes:ruby-lanes ruby-lane-simple:ruby-lanes \
  ruby-auth-lanes:auth-lanes ruby-auth-browser:auth-lanes ruby-billing-lanes:nightly-lanes; do
  assert_contains "${pair%%:*} uses ${pair##*:}" \
    "- !reference [.rules, ${pair##*:}]" "$(gitlab_job "$RUBY_JOBS" "${pair%%:*}")"
done

protects "the frontend build runs in every pipeline that has a lane job that needs it"
# A lane job `needs` frontend-build. When a lane job's rules select it and
# frontend-build's do not, GitLab refuses to create the pipeline.
build_job="$(gitlab_job "$FRONTEND_JOBS" frontend-build)"
for name in ruby-lanes auth-lanes; do
  assert_contains "frontend-build uses ${name}" "- !reference [.rules, ${name}]" "$build_job"
done

protects "every lane under tests/lanes/ runs in a GitLab job, or is listed here with where it runs"
# selftest: started by the harness lane's specs, never as a job.
# migrations-pg, migrations-sqlite: .github/workflows/migration-tests.yml.
elsewhere=" selftest migrations-pg migrations-sqlite "
job_lanes=" $(sed -nE 's/^ +(- )?LANE: \[?([^]]+)\]?$/\2/p' "$RUBY_JOBS" | tr ',' ' ' | tr -s ' \n' ' ')"
assert_at_least "lanes named in ruby.yml extracted" 12 "$(printf '%s' "$job_lanes" | wc -w | tr -d ' ')" "lanes"
for tasks in "$LANES_DIR"/*/tasks; do
  lane="$(basename "$(dirname "$tasks")")"
  case "$elsewhere" in *" ${lane} "*) continue ;; esac
  assert_contains "lane ${lane} is in a job in ruby.yml" " ${lane} " "$job_lanes"
done
for lane in $job_lanes; do
  exists=false
  [ -f "${LANES_DIR}/${lane}/tasks" ] && exists=true
  assert_eq "ruby.yml lane ${lane} is a lane under tests/lanes/" true "$exists"
done

finish
