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

protects 'the decision reads the whole current label set and matches ci:auth exactly, never a substring'
expect_selection 'ci:auth present on its own' true label:ci:auth \
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

protects 'the label reader returns the PR'"'"'s current labels as one JSON line and fails closed on any lookup problem'
LABELS="${REPO_ROOT}/.github/scripts/read-pr-labels.sh"
STUB="$TMP/bin"
mkdir -p "$STUB"
# A stand-in for gh: records its arguments, then prints GH_STUB_BODY or fails.
cat > "$STUB/gh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_ARGS_LOG"
if [[ "${GH_STUB_EXIT:-0}" != 0 ]]; then
  echo 'gh: Not Found (HTTP 404)' >&2
  exit "$GH_STUB_EXIT"
fi
printf '%s' "${GH_STUB_BODY-}"
SH
chmod +x "$STUB/gh"

read_labels() {
  : > "$TMP/gh-args"
  env -i PATH="$STUB:$PATH" GH_TOKEN=test-token GH_ARGS_LOG="$TMP/gh-args" \
    GITHUB_REPOSITORY=onetimesecret/onetimesecret PR_NUMBER=42 "$@" bash "$LABELS" 2>&1
}

expect_labels() {
  local label="$1" expected="$2" body="$3" out status
  out="$(read_labels GH_STUB_BODY="$body")"
  status=$?
  assert_eq "$label: exit" 0 "$status"
  assert_eq "$label: labels" "$expected" "$out"
}

reject_labels() {
  local label="$1" error="$2" out status
  shift 2
  : > "$TMP/output"
  out="$(read_labels GITHUB_OUTPUT="$TMP/output" "$@")"
  status=$?
  assert_eq "$label: exit" 1 "$status"
  assert_contains "$label: diagnostic" "$error" "$out"
  assert_eq "$label: no labels output" '' "$(cat "$TMP/output")"
}

expect_labels 'two labels' '["ci:auth","bug"]' \
  '{"number":42,"labels":[{"id":1,"name":"ci:auth"},{"id":2,"name":"bug"}]}'
assert_eq 'one read of the pull request, nothing else' \
  'api repos/onetimesecret/onetimesecret/pulls/42' "$(cat "$TMP/gh-args")"
expect_labels 'a PR without labels is an empty list, not a failure' '[]' '{"number":42,"labels":[]}'
hostile='{"labels":[{"name":"quote\"and\nnewline"},{"name":"étiquette"},{"name":"ci:auth"}]}'
out="$(read_labels GH_STUB_BODY="$hostile")"
assert_eq 'hostile label names stay on one JSON line' 1 "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
expect_selection 'reader output feeds the selector unchanged' true label:ci:auth LABELS_JSON="$out"

reject_labels 'API failure' 'Could not read the pull request' GH_STUB_EXIT=1 GH_STUB_BODY='{"labels":[]}'
for bad in '' 'null' '[]' '"ci:auth"' '{"message":"Not Found"}' '{"labels":null}' \
  '{"labels":{}}' '{"labels":[{"name":1}]}' '{"labels":[{}]}' '{"labels":["ci:auth"]}' '{'; do
  reject_labels "unusable response [$bad]" 'not a pull request with a list of labels' GH_STUB_BODY="$bad"
done
for bad in '' 0 007 12a '42 ' '42;id' '$(id)' ../43; do
  reject_labels "invalid PR number [$bad]" PR_NUMBER PR_NUMBER="$bad" GH_STUB_BODY='{"labels":[]}'
  assert_eq "invalid PR number [$bad]: the API is never called" '' "$(cat "$TMP/gh-args")"
done
reject_labels 'unset PR number' PR_NUMBER env -u PR_NUMBER GH_STUB_BODY='{"labels":[]}'
for bad in '' onetimesecret 'a/b/c' 'a b/c' '../x/y?z'; do
  reject_labels "invalid repository [$bad]" GITHUB_REPOSITORY GITHUB_REPOSITORY="$bad" GH_STUB_BODY='{"labels":[]}'
done
out="$(env -i PATH="$STUB:$PATH" GH_ARGS_LOG="$TMP/gh-args" GITHUB_REPOSITORY=a/b PR_NUMBER=1 \
  GH_STUB_BODY='{"labels":[]}' bash "$LABELS" --all 2>&1)"
assert_eq 'label reader rejects flags' 1 "$?"
assert_contains 'label reader flag diagnostic' 'environment inputs only' "$out"

printf 'existing=kept\n' > "$TMP/output"
out="$(read_labels GITHUB_OUTPUT="$TMP/output" GH_STUB_BODY='{"labels":[{"name":"ci:auth"}]}')"
assert_eq 'label file output exit' 0 "$?"
assert_eq 'label file output does not duplicate stdout' '' "$out"
assert_eq 'labels appended as one output' $'existing=kept\njson=["ci:auth"]' "$(cat "$TMP/output")"

protects 'the local action uses a pinned cumulative-PR filter and the live label set, without masking PR errors'
action="$(cat "$ACTION")"
assert_contains 'pinned paths-filter' 'dorny/paths-filter@ceb8a2b8f2d89434be7ff52d3de7ec3738c5cc9d' "$action"
assert_contains 'filter runs only for PR' "if: github.event_name == 'pull_request'" "$action"
assert_contains 'external filters file' 'filters: .github/auth-paths.yml' "$action"
assert_contains 'event context passed' 'EVENT_NAME: ${{ github.event_name }}' "$action"
assert_contains 'label reader invoked' 'run: bash .github/scripts/read-pr-labels.sh' "$action"
assert_contains 'label reader gets the PR number' 'PR_NUMBER: ${{ github.event.pull_request.number }}' "$action"
assert_contains 'live labels on PRs and an explicit empty array elsewhere' "LABELS_JSON: \${{ github.event_name != 'pull_request' && '[]' || steps.labels.outputs.json }}" "$action"
case "$action" in
  *github.event.pull_request.labels*) frozen=present ;;
  *) frozen=absent ;;
esac
assert_eq 'the frozen event-payload labels are not consulted' absent "$frozen"
assert_contains 'force input passed' 'FORCE_AUTH: ${{ inputs.force }}' "$action"
assert_contains 'false fallback only outside PRs' "FILTER_AUTH: \${{ github.event_name != 'pull_request' && 'false' || steps.filter.outputs.auth }}" "$action"
assert_contains 'compute script invoked' 'run: bash .github/scripts/compute-auth-selection.sh' "$action"

protects 'the path list selects auth code and the selected jobs'"'"' own tests, and leaves shared code, other suites and translations out'
# PyYAML is optional in the bare shell-tests job. The fallback accepts only this
# file's simple auth: list of quoted positive globs; it fails on unfamiliar YAML
# rather than silently testing the wrong thing. Exercise it even with PyYAML.
# The matcher implements the subset the list uses: *, **, **/, {a,b} and
# two-letter [Aa] classes (dotfiles included, as in paths-filter/picomatch).
# It rejects other syntax so the list cannot drift past what is tested here.
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
    match = re.fullmatch(r"  - '([a-zA-Z0-9_./*\-{},\[\]]+)'", line)
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
    assert [step['id'] for step in steps] == ['filter', 'labels', 'compute']
    for step in steps[:2]:
        assert step['if'] == "github.event_name == 'pull_request'"
        assert 'continue-on-error' not in step, 'a failed lookup must fail the job'
    assert steps[0]['with']['filters'] == '.github/auth-paths.yml'
    assert steps[1]['shell'] == 'bash'
    assert steps[1]['env'] == {
        'GH_TOKEN': '${{ github.token }}',
        'PR_NUMBER': '${{ github.event.pull_request.number }}',
    }
    assert steps[2]['shell'] == 'bash'
    assert 'if' not in steps[2], 'selection runs on every event'
    assert set(steps[2]['env']) == {'FILTER_AUTH', 'FORCE_AUTH', 'EVENT_NAME', 'LABELS_JSON'}
    assert steps[2]['env']['LABELS_JSON'] == (
        "${{ github.event_name != 'pull_request' && '[]' || steps.labels.outputs.json }}"
    )

assert set(filters) == {'auth'}
patterns = filters['auth']
assert all(isinstance(p, str) for p in patterns)
assert len(set(patterns)) == len(patterns), 'duplicate glob'

# The name list appears twice, once matching files and once matching
# directories. Both lines must carry the same names.
named = [p for p in patterns if '[Aa]uth' in p]
assert len(named) == 2 and named[0].endswith('}*') and named[1] == named[0] + '/**', \
    'the file and directory forms of the auth name list differ'


def expand(pattern):
    """Brace expansion, innermost first; the list uses no nesting."""
    match = re.search(r'\{([^{}]*)\}', pattern)
    if not match:
        if '{' in pattern or '}' in pattern:
            raise ValueError(f'unbalanced braces: {pattern}')
        return [pattern]
    expanded = []
    for alternative in match[1].split(','):
        if not alternative:
            raise ValueError(f'empty brace alternative: {pattern}')
        expanded.extend(expand(pattern[:match.start()] + alternative + pattern[match.end():]))
    return expanded


def glob_regex(pattern):
    for segment in pattern.split('/'):
        if '**' in segment and segment != '**':
            raise ValueError(f'unsupported glob: {pattern}')
    parts = []
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
        elif pattern[i] == '[':
            letters = re.match(r'\[([A-Za-z]{2})\]', pattern[i:])
            if not letters:
                raise ValueError(f'unsupported character class: {pattern}')
            parts.append('[' + letters[1] + ']')
            i += 4
        elif pattern[i] in ']{},':
            raise ValueError(f'unsupported glob: {pattern}')
        else:
            parts.append(re.escape(pattern[i]))
            i += 1
    return re.compile(''.join(parts))


matchers = [glob_regex(simple) for pattern in patterns for simple in expand(pattern)]
positive = [
    # Applications that are auth throughout, and the sign-in pages.
    'apps/web/auth/database.rb', 'apps/web/auth/migrations/001_initial.rb',
    'apps/web/auth/spec/unit/config_spec.rb',
    'apps/api/account/logic/account/destroy_account.rb', 'apps/api/invite/routes.txt',
    'src/apps/session/views/Login.vue', 'src/apps/session/routes.ts',
    'src/apps/session/components/NewHelper.vue',
    # Files named for an auth concept, including ones that do not exist yet.
    'lib/onetime/auth_config.rb', 'lib/onetime/session.rb', 'lib/.hidden/auth.rb',
    'lib/onetime/tenant_sso_resolution.rb', 'lib/onetime/new_oidc_client.rb',
    'lib/onetime/middleware/saml_callback_transport.rb',
    'lib/onetime/middleware/csrf_response_header.rb',
    'lib/onetime/middleware/identity_resolution.rb',
    'lib/onetime/models/custom_domain/sso_config.rb',
    'lib/onetime/security/login_rate_limiter.rb', 'lib/onetime/utils/totp.rb',
    'lib/onetime/logic/credential_change_session_revocation.rb',
    'lib/onetime/mail/templates/magic_link.html.erb',
    'lib/onetime/mail/templates/password_request.txt.erb',
    'lib/onetime/cli/passwords_command.rb', 'lib/onetime/signup_validation.rb',
    'apps/api/v2/auth_strategies.rb', 'apps/web/core/controllers/authentication.rb',
    'apps/web/core/views/serializers/authentication_serializer.rb',
    'apps/api/colonel/logic/colonel/revoke_customer_session.rb',
    'etc/defaults/auth.defaults.yaml',
    'spec/support/auth_mode_helpers.rb', 'spec/unit/onetime/mfa_policy_spec.rb',
    'src/shared/stores/authStore.ts', 'src/shared/stores/csrfStore.ts',
    'src/shared/stores/identityStore.ts', 'src/shared/composables/useMfa.ts',
    'src/shared/composables/useWebAuthn.ts', 'src/shared/composables/useMagicLink.ts',
    'src/shared/composables/useReauth.ts', 'src/shared/utils/sso.ts',
    'src/services/sso.service.ts', 'src/types/auth.ts', 'src/utils/sessionTransition.ts',
    'src/schemas/contracts/session-failure.ts',
    'src/apps/workspace/components/domains/DomainSsoConfigForm.vue',
    'src/apps/workspace/domains/DomainSignin.vue',
    'src/tests/stores/authStore.spec.ts',
    # Directories named for an auth concept.
    'lib/onetime/session/store.rb', 'lib/onetime/sso_provider/base.rb',
    'lib/onetime/application/auth_strategies/basic.rb',
    'lib/onetime/operations/sessions/revoke.rb', 'lib/onetime/cli/sso/backfill_issuer_command.rb',
    'apps/api/domains/logic/sso_config/update.rb',
    'apps/api/organizations/logic/invitations/create.rb',
    'src/shared/components/auth/StaleSessionNotice.vue', 'src/schemas/api/auth/index.ts',
    'spec/unit/onetime/session/store_spec.rb',
    # Auth code the names miss.
    'apps/web/core/views/serializers/config_serializer.rb',
    'src/apps/workspace/account/settings/ProfileSettings.vue',
    'src/apps/workspace/components/account/APIKeyCard.vue',
    'src/services/bootstrap.service.ts', 'src/shared/stores/bootstrapStore.ts',
    'src/schemas/contracts/bootstrap.ts', 'locales/content/en/session-auth.json',
    'locales/content/en/session-auth-extended.json',
    # Boot configuration and gems.
    'etc/defaults/config.defaults.yaml', 'Gemfile', 'Gemfile.lock',
    # Tests and lane definitions only the selected jobs run.
    'tests/browser/saml_callback_spec.rb', 'tests/browser/saml_callback.mjs',
    'tests/lanes/browser/tasks', 'tests/lanes/full-mfa/env',
    'tests/lanes/full-saml-platform/env', 'tests/lanes/full-pg-agnostic/tasks',
    'tests/lanes/full-sqlite/env', 'tests/lanes/overlays/billing.env',
    'e2e/auth/signup-redirect-preservation.spec.ts', 'e2e/all/auth-hydration.spec.ts',
    'e2e/system/connected-identities-custom-host.spec.ts',
    'e2e/system/tenant_connect_seed.rb', 'e2e/system/tenant_connect_test_boot.rb',
    'e2e/support/fixtures.ts', 'e2e/global.setup.ts', 'e2e/playwright.config.ts',
    'compose.e2e.yml',
    # The selection machinery and the workflows it gates.
    '.github/auth-paths.yml', '.github/scripts/compute-auth-selection.sh',
    '.github/scripts/read-pr-labels.sh', '.github/workflows/ci.yml',
    '.github/workflows/e2e-full-auth.yml', '.github/workflows/e2e-tenant-connect.yml',
    '.github/actions/detect-auth-changes/action.yml',
    '.github/actions/setup-ruby-test-env/action.yml',
]
# Pin all three exact full-auth directories across root and arbitrary apps.
for base in ('spec', 'apps/web/new_app/spec', 'apps/api/new_app/spec'):
    for lane in ('full', 'full_mfa', 'full_saml_platform'):
        positive.append(f'{base}/integration/{lane}/nested/routes_spec.rb')
negative = [
    # Documentation and repository metadata, whatever it is called.
    'README.md', 'docs/auth-guide.md', 'docs/development/auth-ci.md', 'changelog.d/auth.md',
    '.simplecov', '.ruby-version', '.rspec',
    # Shared backend code: the lanes every Ruby change runs cover it.
    'lib/onetime.rb', 'lib/onetime/boot.rb', 'lib/onetime/config.rb',
    'lib/onetime/models/secret.rb', 'lib/onetime/models/customer.rb',
    'lib/onetime/models/organization.rb', 'lib/onetime/middleware/security.rb',
    'lib/onetime/application/middleware_stack.rb',
    'lib/onetime/mail/templates/secret_link.html.erb',
    'lib/onetime/jobs/workers/email_worker.rb', 'lib/tasks/spec.rake',
    'etc/defaults/logging.defaults.yaml', 'etc/examples/puma.example.rb',
    'apps/api/v2/logic/secrets/conceal_secret.rb',
    'apps/api/domains/logic/domains/add_domain.rb',
    'apps/api/organizations/logic/members.rb', 'apps/web/core/controllers/page.rb',
    'apps/internal/acme/application.rb',
    'bin/ots', 'config.ru', 'Rakefile', 'migrations/2026-07-27/01_backfill.rb',
    # Billing and the suites that are not auth coverage.
    'apps/web/billing/logic/checkout.rb',
    'apps/web/billing/spec/integration/full_billing/checkout_spec.rb',
    'spec/integration/full_billing/checkout_spec.rb',
    'spec/spec_helper.rb', 'spec/support/model_helpers.rb',
    'spec/integration/integration_spec_helper.rb',
    'spec/integration/simple/adapter_spec.rb', 'spec/integration/all/routes_spec.rb',
    'spec/integration/disabled/public_access_spec.rb',
    'spec/unit/onetime/models/secret_spec.rb',
    # Tryouts run in the unit and simple lanes only, so no selected job loads them.
    'try/integration/auth/new_try.rb', 'try/unit/session_try.rb',
    'try/support/auth_mode_config.rb',
    # Lanes every Ruby change runs, and the runner itself.
    'tests/lanes/unit/tasks', 'tests/lanes/simple/env', 'tests/lanes/run',
    'tests/lanes/base.env', 'tests/fixtures/session.json',
    # Shared frontend code and the other applications.
    'src/main.ts', 'src/App.vue', 'src/i18n.ts', 'src/admin.ts',
    'src/router/index.ts', 'src/plugins/core/appInitializer.ts',
    'src/api/index.ts', 'src/utils/redirect.ts', 'src/assets/style.css',
    'src/shared/components/ui/BaseButton.vue', 'src/shared/stores/secretStore.ts',
    'src/apps/admin/routes.ts', 'src/apps/secret/components/SecretForm.vue',
    'src/apps/workspace/billing/Invoices.vue',
    'src/apps/workspace/dashboard/DashboardIndex.vue',
    'src/apps/workspace/routes/index.ts',
    'src/tests/stores/secretStore.spec.ts',
    'src/tests/apps/workspace/billing/checkout.spec.ts',
    # Translations, and English copy that is not sign-in copy.
    'locales/content/de/session-auth.json', 'locales/content/en/secret-manage.json',
    'locales/content/en/workspace-billing.json',
    # Browser suites the two auth workflows do not run.
    'e2e/full/domain-sso-config.spec.ts', 'e2e/full-billing/checkout.spec.ts',
    'e2e/all/secret-context.spec.ts', 'e2e/visual/secret.spec.ts',
    # Build inputs and unrelated CI scripts.
    'package.json', 'pnpm-lock.yaml', 'Dockerfile', 'compose.test.yml',
    'vite.config.ts', 'tsconfig.json', 'public/schemas/bootstrap.json',
    '.github/scripts/ci-verdict.sh', 'scripts/tests/auth-selection-test.sh',
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
  assert_at_least 'path fixtures exercised' 150 "$count" 'positive/negative glob fixtures'
fi

finish
