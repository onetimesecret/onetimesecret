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
#
# Which job runs a lane decides when it runs, and its overlay decides what it
# tests: a billing row without its overlay runs with billing off and passes,
# and an auth lane moved into the every-change job costs its minutes on every
# merge request. The table of jobs, lanes, overlays and services below is
# that policy. A row in ruby.yml that differs from it fails here.
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

# The entries of a job's own `script:` in ruby.yml.
job_script() { # <job>
  gitlab_job "$RUBY_JOBS" "$1" | awk '
    $0 == "  script:" { on = 1; next }
    on && /^    - / { print; next }
    on { exit }
  '
}

# The lanes ruby.yml runs, one line each: "<job> <lane> <overlay> <services>",
# with "-" for no overlay and for no service beyond valkey and rabbitmq. A
# lane is a `LANE:` under a job's `variables:` or a row of its
# `parallel:matrix:`, where LANE_OVERLAY and LANE_EXTRA_SERVICES belong to
# the row they follow.
lane_rows() {
  awk '
    function flush(   n, i, names) {
      if (lanes == "") return
      gsub(/[][ ]/, "", lanes)
      n = split(lanes, names, ",")
      for (i = 1; i <= n; i++)
        print job, names[i], (overlay == "" ? "-" : overlay), (services == "" ? "-" : services)
      lanes = ""; overlay = ""; services = ""
    }
    /^[^ #]/ { flush(); job = $0; sub(/:$/, "", job); next }
    /^    LANE: / || /^      - LANE: / { flush(); lanes = $0; sub(/^.*LANE: /, "", lanes); next }
    /^        LANE_OVERLAY: / { overlay = $2; next }
    /^        LANE_EXTRA_SERVICES: / { services = $2; next }
    END { flush() }
  ' "$RUBY_JOBS"
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
# The push rule is two lines. Without its second line the auth lanes would
# run on every push to main and develop, whatever it changed.
assert_eq "auth-lanes' push rule is limited to Ruby changes" \
  "      changes: !reference [.changes, ruby]" \
  "$(grep -A1 -F 'CI_PIPELINE_SOURCE == "push"' "$RULES" | tail -n 1)"
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
for name in ruby-lanes auth-lanes nightly-lanes; do
  assert_contains "frontend-build uses ${name}" "- !reference [.rules, ${name}]" "$build_job"
done
lane_template="$(gitlab_job "$RUBY_JOBS" .lane)"
assert_contains "a lane job waits for frontend-build" "    - job: frontend-build" "$lane_template"
# smoke-lane is also selected by the typescript list, which frontend-build is
# not, so it must not inherit the template's needs.
for job in smoke-lane rubocop; do
  assert_contains "${job} waits on no job" "  needs: []" "$(gitlab_job "$RUBY_JOBS" "$job")"
done
assert_contains "frontend-build waits on no job" "  needs: []" "$build_job"

protects "each job runs the lanes, overlays and services of its GitHub job"
rows="$(lane_rows)"
assert_eq "ruby.yml's jobs, lanes, overlays and extra services" "\
smoke-lane smoke - -
ruby-lanes unit - -
ruby-lanes harness - -
ruby-lanes billing - -
ruby-lanes api - -
ruby-lanes full-sqlite - -
ruby-lanes disabled - -
ruby-lanes strategies - -
ruby-lanes full-pg - postgres
ruby-lane-simple simple - -
ruby-auth-lanes full-mfa - -
ruby-auth-lanes full-saml-platform - -
ruby-auth-lanes full-webauthn-verify - -
ruby-auth-lanes full-pg-agnostic - postgres
ruby-auth-browser browser - -
ruby-billing-lanes billing-integration - -
ruby-billing-lanes full-sqlite billing -
ruby-billing-lanes full-pg billing postgres
ruby-billing-lanes full-pg-agnostic billing postgres" "$rows"

protects "a lane gets postgres exactly when its env names the test PostgreSQL port"
# compose.test.yml publishes PostgreSQL on 2154, and the lane runner's
# preflight requires every endpoint in a lane's env to answer.
while read -r job lane overlay services; do
  [ -n "$lane" ] || continue
  expected=-
  grep -q '127\.0\.0\.1:2154' "${LANES_DIR}/${lane}/env" 2> /dev/null && expected=postgres
  assert_eq "${job}: ${lane} (overlay ${overlay}) extra services" "$expected" "$services"
done <<< "$rows"
assert_contains "the lane template starts the extra services" \
  "    - bin/ci services up valkey rabbitmq \$LANE_EXTRA_SERVICES" "$lane_template"
assert_contains "the lane template passes the overlay" \
  "    - bin/ci lane \$LANE \$LANE_OVERLAY" "$lane_template"

protects "every lane under tests/lanes/ runs in a GitLab job, or is listed here with where it runs"
# selftest: started by the harness lane's specs, never as a job.
# migrations-pg, migrations-sqlite: .github/workflows/migration-tests.yml.
elsewhere=" selftest migrations-pg migrations-sqlite "
job_lanes=" $(printf '%s\n' "$rows" | awk '{ print $2 }' | tr '\n' ' ')"
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

protects "the steps a job adds to the lane template, and the jobs that write the bundle cache"
assert_eq "ruby-lane-simple runs the fresh-schema check, then the lane" "\
    - bash .github/scripts/check-api-v3-fresh-schemas.sh
    - bin/ci lane \$LANE" "$(job_script ruby-lane-simple)"
assert_eq "ruby-auth-browser installs the Playwright browsers, then runs the lane" "\
    - pnpm exec playwright install --with-deps chromium firefox webkit
    - bin/ci lane \$LANE" "$(job_script ruby-auth-browser)"
# Lane jobs only read the cache. If neither of these wrote it, every lane job
# would install the whole bundle on every run.
assert_eq "the shared cache is read-only by default" "    policy: pull" \
  "$(gitlab_job "$RUBY_JOBS" .ruby-job | grep '^ *policy:')"
for job in rubocop smoke-lane; do
  assert_contains "${job} writes the bundle cache" "    policy: pull-push" "$(gitlab_job "$RUBY_JOBS" "$job")"
done

finish
