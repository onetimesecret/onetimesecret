#!/usr/bin/env bash
# Pure-text tests for the shared auth selector; no Ruby, services, or network.
# Markdown backticks and GitHub expressions in assertions are literal strings.
# shellcheck disable=SC2016
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
# shellcheck source=scripts/tests/lib/assert.sh
source "${TEST_DIR}/lib/assert.sh"
SCRIPT="${REPO_ROOT}/.github/scripts/compute-auth-selection.sh"
FILTERS="${REPO_ROOT}/.github/auth-paths.yml"
ACTION="${REPO_ROOT}/.github/actions/detect-auth-changes/action.yml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

printf '%s\n' "$ASSERT_SUITE"

selection() {
  env -i PATH="$PATH" FILTER_AUTH=false FORCE_AUTH=false \
    EVENT_NAME=pull_request LABELS_JSON='[]' "$@" bash "$SCRIPT" 2>&1
}

expect_selection() {
  local label="$1" auth="$2" reason="$3" out status
  shift 3
  out="$(selection "$@")"
  status=$?
  assert_eq "$label: exit" 0 "$status"
  assert_eq "$label: outputs" "$(printf 'auth=%s\nreason=%s' "$auth" "$reason")" "$out"
}

reject_selection() {
  local label="$1" error="$2" out status
  shift 2
  : > "$TMP/output"
  : > "$TMP/summary"
  out="$(selection GITHUB_OUTPUT="$TMP/output" GITHUB_STEP_SUMMARY="$TMP/summary" "$@")"
  status=$?
  assert_eq "$label: exit" 1 "$status"
  assert_contains "$label: diagnostic" "$error" "$out"
  assert_eq "$label: no selection output" '' "$(cat "$TMP/output")"
  assert_eq "$label: no summary" '' "$(cat "$TMP/summary")"
}

protects 'PR paths, current labels, and force are ORed; baseline events always run without detection'
for event in pull_request schedule push merge_group workflow_dispatch; do
  for filter in true false; do
    for force in true false; do
      for labels in '[]' '["unrelated"]' '["unrelated", "ci:auth"]'; do
        auth=true
        if [[ "$event" != pull_request ]]; then
          reason="event:$event"
        elif [[ "$force" == true ]]; then
          reason=force
        elif [[ "$labels" == *ci:auth* ]]; then
          reason=label:ci:auth
        elif [[ "$filter" == true ]]; then
          reason=paths
        else
          auth=false
          reason=no-auth-changes
        fi
        expect_selection "$event filter=$filter force=$force labels=$labels" "$auth" "$reason" \
          EVENT_NAME="$event" FILTER_AUTH="$filter" FORCE_AUTH="$force" LABELS_JSON="$labels"
      done
    done
  done
done

protects 'label/unlabel runs use the current full label set, not the triggering label or a substring'
expect_selection 'ci:auth still present after unrelated unlabel' true label:ci:auth \
  LABELS_JSON='["ci:auth"]'
expect_selection 'ci:auth removed, unrelated label remains' false no-auth-changes \
  LABELS_JSON='["unrelated"]'
expect_selection 'near-miss labels cannot force auth' false no-auth-changes \
  LABELS_JSON='["CI:AUTH", "ci:auth-skip", "ci:auth "]'
expect_selection 'valid Unicode and escaped labels' true label:ci:auth \
  LABELS_JSON='["étiquette", "quote\"and\nnewline", "ci:auth"]'

protects 'skip flags cannot override the shared auth decision'
expect_selection 'ambient skip variables are ignored' true paths \
  FILTER_AUTH=true SKIP_CI=true SKIP_AUTH=true
out="$(env -i PATH="$PATH" FILTER_AUTH=true FORCE_AUTH=false \
  EVENT_NAME=pull_request LABELS_JSON='[]' bash "$SCRIPT" --skip 2>&1)"
assert_eq 'command-line skip flag rejected' 1 "$?"
assert_contains 'flag diagnostic' 'environment inputs only' "$out"

protects 'invalid booleans never turn broken detection into a skip, even when another input forces auth'
for bad in '' True FALSE 1 null ' true' $'false\n'; do
  reject_selection "invalid filter [$bad] with force" FILTER_AUTH \
    FILTER_AUTH="$bad" FORCE_AUTH=true LABELS_JSON='["ci:auth"]'
  reject_selection "invalid force [$bad] with matching paths" FORCE_AUTH \
    FORCE_AUTH="$bad" FILTER_AUTH=true
done
# All unconditional events validate too; the action supplies false for the
# deliberately skipped filter, not an empty or missing result.
for event in schedule push merge_group workflow_dispatch; do
  reject_selection "$event invalid filter" FILTER_AUTH \
    EVENT_NAME="$event" FILTER_AUTH='' FORCE_AUTH=true
  reject_selection "$event invalid force" FORCE_AUTH \
    EVENT_NAME="$event" FORCE_AUTH='' FILTER_AUTH=true
done

protects 'labels must be exactly one JSON array of strings before any PR or event override'
for event in pull_request schedule push merge_group workflow_dispatch; do
  for bad in '' '{' 'null' '{}' '"ci:auth"' '[1]' '[false]' '[null]' '[{}]' \
    '["ci:auth", 1]' '[] []'; do
    reject_selection "$event invalid labels [$bad]" LABELS_JSON \
      EVENT_NAME="$event" FILTER_AUTH=true FORCE_AUTH=true LABELS_JSON="$bad"
  done
done

protects 'missing required inputs and unknown events are failures, not successful no-change decisions'
for missing in FILTER_AUTH FORCE_AUTH EVENT_NAME LABELS_JSON; do
  reject_selection "unset $missing" "$missing" env -u "$missing"
done
reject_selection 'empty event' EVENT_NAME EVENT_NAME=''
reject_selection 'unsupported event' EVENT_NAME EVENT_NAME=issues FORCE_AUTH=true

protects 'GitHub output and summary append the same decision; local mode needs neither file'
printf 'existing output\n' > "$TMP/output"
printf 'existing summary\n' > "$TMP/summary"
out="$(selection FILTER_AUTH=true GITHUB_OUTPUT="$TMP/output" GITHUB_STEP_SUMMARY="$TMP/summary")"
assert_eq 'file output exit' 0 "$?"
assert_eq 'file output does not duplicate stdout' '' "$out"
assert_eq 'output appended' $'existing output\nauth=true\nreason=paths' "$(cat "$TMP/output")"
assert_contains 'summary preserves earlier content' 'existing summary' "$(cat "$TMP/summary")"
assert_contains 'summary shows auth' 'auth: `true`' "$(cat "$TMP/summary")"
assert_contains 'summary shows reason' 'reason: `paths`' "$(cat "$TMP/summary")"
expect_selection 'local mode without optional files' false no-auth-changes

protects 'the local action uses a pinned cumulative-PR filter and passes current labels without masking PR errors'
action="$(cat "$ACTION")"
assert_contains 'pinned paths-filter' 'dorny/paths-filter@ceb8a2b8f2d89434be7ff52d3de7ec3738c5cc9d' "$action"
assert_contains 'filter runs only for PR' "if: github.event_name == 'pull_request'" "$action"
assert_contains 'external filters file' 'filters: .github/auth-paths.yml' "$action"
assert_contains 'event context passed' 'EVENT_NAME: ${{ github.event_name }}' "$action"
assert_contains 'current PR labels and explicit non-PR empty array' "LABELS_JSON: \${{ github.event_name != 'pull_request' && '[]' || toJSON(github.event.pull_request.labels.*.name) }}" "$action"
assert_contains 'force input passed' 'FORCE_AUTH: ${{ inputs.force }}' "$action"
assert_contains 'false fallback only outside PRs' "FILTER_AUTH: \${{ github.event_name != 'pull_request' && 'false' || steps.filter.outputs.auth }}" "$action"
assert_contains 'compute script invoked' 'run: bash .github/scripts/compute-auth-selection.sh' "$action"

protects 'actual external YAML globs select shared/auth changes but leave independent billing/dashboard/test changes out'
# PyYAML is optional in the bare shell-tests job. The fallback accepts only this
# file's simple auth: list of quoted positive globs; it fails on unfamiliar YAML
# rather than silently testing the wrong thing. Exercise it even with PyYAML.
# The matcher implements the *, ** and **/ subset used here (dotfiles included,
# as in paths-filter/picomatch). Reject other syntax so it cannot drift silently.
path_results="$(python3 - "$FILTERS" "$ACTION" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text()
fixture = []
header = False
for raw in text.splitlines():
    line = raw.split('#', 1)[0].rstrip()
    if not line:
        continue
    if line == 'auth:' and not header:
        header = True
        continue
    match = re.fullmatch(r"  - '([a-zA-Z0-9_./*\-]+)'", line)
    if not header or not match:
        raise ValueError(f'unsupported filters YAML: {raw}')
    fixture.append(match[1])
if not fixture:
    raise ValueError('empty auth filter')

try:
    import yaml
except ImportError:
    filters = {'auth': fixture}
else:
    filters = yaml.safe_load(text)
    assert filters == {'auth': fixture}, 'PyYAML and fixture parser disagree'
    action = yaml.safe_load(Path(sys.argv[2]).read_text())
    assert set(action['inputs']) == {'force'}, 'no skip input is accepted'
    assert action['inputs']['force']['default'] == 'false'
    assert set(action['outputs']) == {'auth', 'reason'}
    for name in ('auth', 'reason'):
        assert action['outputs'][name]['value'] == '${{ steps.compute.outputs.' + name + ' }}'
    assert action['runs']['using'] == 'composite'
    steps = action['runs']['steps']
    assert len(steps) == 2
    assert steps[0]['if'] == "github.event_name == 'pull_request'"
    assert steps[0]['with']['filters'] == '.github/auth-paths.yml'
    assert steps[1]['shell'] == 'bash'
    assert set(steps[1]['env']) == {'FILTER_AUTH', 'FORCE_AUTH', 'EVENT_NAME', 'LABELS_JSON'}
    assert steps[1]['env']['LABELS_JSON'] == (
        "${{ github.event_name != 'pull_request' && '[]' || "
        "toJSON(github.event.pull_request.labels.*.name) }}"
    )

assert set(filters) == {'auth'}
patterns = filters['auth']
assert all(isinstance(p, str) for p in patterns)

def glob_regex(pattern):
    parts = []
    for segment in pattern.split('/'):
        if '**' in segment and segment != '**':
            raise ValueError(f'unsupported glob: {pattern}')
    i = 0
    while i < len(pattern):
        if pattern[i:i+3] == '**/':
            parts.append('(?:.*/)?')
            i += 3
        elif pattern[i:i+2] == '**':
            parts.append('.*')
            i += 2
        elif pattern[i] == '*':
            parts.append('[^/]*')
            i += 1
        else:
            parts.append(re.escape(pattern[i]))
            i += 1
    return re.compile(''.join(parts))

matchers = [glob_regex(p) for p in patterns]
positive = [
    'lib/onetime/new_unknown_module.rb', 'lib/.hidden/auth.rb',
    'etc/new_unknown_config.yaml', 'apps/web/auth/database.rb',
    'apps/web/core/routes.txt', 'apps/api/base_json_api.rb',
    'apps/api/account/logic/change_password.rb',
    'apps/api/domains/logic/update_domain_sso_config.rb',
    'apps/api/organizations/logic/members.rb', 'apps/api/invite/routes.txt',
    'apps/internal/routes.txt', 'bin/ots', 'config.ru', 'Rakefile',
    'migrations/new_migration.rb', 'Gemfile', 'Gemfile.lock', '.ruby-version',
    'tests/browser/auth_spec.rb', 'tests/lanes/full-mfa/env',
    'tests/lanes/full-saml-platform/env', 'tests/fixtures/session.json',
    'spec/support/new_helper.rb', 'spec/spec_helper.rb', 'spec/auth.test.yaml',
    'try/support/auth_mode_config.rb', 'try/integration/auth/new_try.rb',
    'try/integration/authentication/new_try.rb', 'try/integration/boot/new_try.rb',
    'try/integration/domain_auth_enforcement_try.rb',
    'src/apps/session/views/Login.vue', 'src/shared/stores/authStore.ts',
    'src/shared/new_dependency.ts', 'src/router/guards.routes.ts',
    'src/plugins/core/appInitializer.ts', 'src/api/index.ts',
    'src/schemas/contracts/bootstrap.ts', 'src/services/bootstrap.service.ts',
    'src/services/sso.service.ts', 'src/types/auth.ts', 'src/utils/redirect.ts',
    'src/utils/sessionTransition.ts', 'src/main.ts', 'src/App.vue', 'src/i18n.ts',
    'src/assets/style.css', 'src/apps/workspace/routes/index.ts',
    'src/apps/secret/routes/index.ts', 'src/apps/session/routes.ts',
    'src/apps/workspace/account/ConnectedIdentities.vue',
    'src/apps/workspace/components/domains/DomainSsoConfigForm.vue',
    'src/apps/workspace/components/dashboard/DomainHeader.vue',
    'src/apps/workspace/components/dashboard/DomainsTableActionsCell.vue',
    'src/apps/workspace/components/dashboard/DomainsTableDomainCell.vue',
    'src/apps/workspace/components/dashboard/DeliveryPanel.vue',
    'src/apps/workspace/components/dashboard/LanguageSelector.vue',
    'src/apps/workspace/components/dashboard/SecretPreview.vue',
    'src/apps/workspace/components/dashboard/brand/BrandPreviewColumn.vue',
    'src/apps/workspace/components/dashboard/brand/BrandLogoField.vue',
    'src/apps/workspace/components/billing/EntitlementUpgradePrompt.vue',
    'src/tests/views/session/Login.spec.ts', 'src/tests/apps/session/Login.spec.ts',
    'src/tests/stores/authStore.spec.ts', 'src/tests/composables/useMfa.spec.ts',
    'src/tests/composables/useAuth.billing.spec.ts', 'src/tests/setup.ts',
    'e2e/auth/signup-redirect-preservation.spec.ts',
    'e2e/all/auth-hydration.spec.ts', 'e2e/full/domain-sso-config.spec.ts',
    'e2e/full/invite-token-security.spec.ts', 'e2e/full/mfa-bootstrap-reactivity.spec.ts',
    'e2e/system/connected-identities-custom-host.spec.ts',
    'e2e/system/tenant-sso-unverified-domain.spec.ts',
    'e2e/system/tenant_connect_seed.rb', 'e2e/system/tenant_connect_test_boot.rb',
    'e2e/support/fixtures.ts', 'e2e/global.setup.ts', 'e2e/playwright.config.ts',
    'package.json', 'pnpm-lock.yaml', 'pnpm-workspace.yaml', '.node-version',
    '.bash-version', 'Dockerfile', 'docker/bake.hcl', 'compose.test.yml',
    'vite.config.ts', 'tsconfig.json', 'public/schemas/bootstrap.json',
    'templates/auth.html.erb', 'templates/mail/welcome.html.erb',
    'locales/content/en/auth.json', '.github/auth-paths.yml',
    '.github/workflows/ci.yml', '.github/actions/detect-auth-changes/action.yml',
    '.github/scripts/compute-auth-selection.sh', 'scripts/tests/auth-selection-test.sh',
]
# Pin all three exact full-auth directories across root and arbitrary apps.
for base in ('spec', 'apps/web/new_app/spec', 'apps/api/new_app/spec'):
    for lane in ('full', 'full_mfa', 'full_saml_platform'):
        positive.append(f'{base}/integration/{lane}/nested/auth_spec.rb')
negative = [
    'README.md', 'docs/auth-guide.md', 'changelog.d/auth.md', '.simplecov',
    'src/admin.ts', 'src/apps/admin/routes.ts',
    'src/apps/admin/views/AdminOverview.vue',
    'src/apps/secret/components/SecretForm.vue',
    'apps/web/billing/logic/checkout.rb',
    'apps/web/billing/spec/integration/full_billing/checkout_spec.rb',
    'spec/integration/full_billing/checkout_spec.rb',
    'try/integration/billing/checkout_try.rb',
    'src/apps/workspace/billing/Invoices.vue',
    'src/apps/workspace/dashboard/DashboardIndex.vue',
    'src/tests/apps/workspace/billing/checkout.spec.ts',
    'src/tests/apps/workspace/dashboard/Dashboard.spec.ts',
    'src/tests/views/dashboard/Dashboard.spec.ts',
    'src/tests/composables/useSecret.spec.ts',
    'src/tests/services/billing.service.spec.ts',
    'src/tests/stores/secretStore.spec.ts',
    'e2e/full-billing/checkout.spec.ts', 'e2e/all/secret-context.spec.ts',
    'e2e/visual/secret.spec.ts',
]
for expected, paths in ((True, positive), (False, negative)):
    for path in paths:
        actual = any(m.fullmatch(path) for m in matchers)
        print(f'{path}\t{str(expected).lower()}\t{str(actual).lower()}')
PY
)"
status=$?
assert_eq 'filters YAML/action parse and supported glob grammar' 0 "$status"
if [[ "$status" -eq 0 ]]; then
  count=0
  while IFS=$'\t' read -r path expected actual; do
    [[ -n "$path" ]] || continue
    assert_eq "path $path" "$expected" "$actual"
    count=$((count + 1))
  done <<< "$path_results"
  assert_at_least 'path fixtures exercised' 90 "$count" 'positive/negative glob fixtures'
fi

finish
