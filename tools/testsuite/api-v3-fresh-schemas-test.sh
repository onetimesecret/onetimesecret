#!/usr/bin/env bash
# No Ruby or datastore: exercise CI orchestration with process doubles.
set -euo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"

python3 -I - "$REPO_ROOT" <<'PY'
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
script = root / '.github/scripts/check-api-v3-fresh-schemas.sh'
workflow = (root / '.github/workflows/ci.yml').read_text()
simple = workflow.split('  ruby-integration-simple:\n', 1)[1].split('  ruby-integration-api:\n', 1)[0]
assert 'uses: ./.github/actions/setup-node-env' in simple
assert simple.index('setup-node-env') < simple.index('bash .github/scripts/check-api-v3-fresh-schemas.sh') < simple.index('name: Run simple lane')
assert 'continue-on-error:' not in simple
assert "needs.changes.outputs.ruby == 'true'" in simple
ruby_filter = workflow.split('            ruby:\n', 1)[1].split('            typescript:\n', 1)[0]
for path in ('.github/scripts/check-api-v3-fresh-schemas.sh', 'tools/testsuite/api-v3-fresh-schemas-test.sh', 'src/**', 'scripts/openapi/**', 'package.json', 'pnpm-lock.yaml', 'tsconfig*.json', 'vitest*.ts', 'vite.config.ts', '.node-version'):
    assert f"- '{path}'" in ruby_filter, path
historical = workflow.split('  typescript-unit:\n', 1)[1].split('  ruby-integration-simple:\n', 1)[0]
assert 'pnpm test:base run --printConsoleTrace' in historical
assert 'API_V3_SCHEMA_CAPTURE_DIR' not in historical
print('PASS: workflow selection, dependency setup, blocking order, historical tests')

for mode, expected, consumed in [('success', 0, True), ('missing', 1, False), ('producer-failure', 23, False), ('consumer-failure', 24, True), ('codegen-failure', 25, False)]:
    with tempfile.TemporaryDirectory() as directory:
        work = Path(directory)
        (work / 'tests/lanes').mkdir(parents=True)
        (work / 'bin').mkdir()
        locales = work / 'generated/locales'
        locales.mkdir(parents=True)
        (locales / '.gitkeep').touch()
        captures = work / 'tmp/api-v3-schema-captures'
        captures.mkdir(parents=True)
        (captures / 'stale.json').write_text('{}')
        runner = work / 'tests/lanes/run'
        runner.write_text('''#!/usr/bin/env bash
set -euo pipefail
[[ "$LANES_NO_AUTOSTART" == 1 ]]
[[ "$*" == 'simple --workers 1 --quiet --only spec/integration/simple/api_v3_schema_capture_spec.rb' ]]
[[ ! -e tmp/api-v3-schema-captures/stale.json ]]
[[ -f generated/locales/en.json ]]
printf 'producer\\n' >> order
[[ "$MODE" != producer-failure ]] || exit 23
[[ "$MODE" != missing ]] || exit 0
printf '{}' > tmp/api-v3-schema-captures/fresh.json
''')
        pnpm = work / 'bin/pnpm'
        pnpm.write_text('''#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == 'run locales:sync' ]]; then
  [[ ! -f generated/locales/en.json ]]
  printf 'codegen\\n' >> order
  [[ "$MODE" != codegen-failure ]] || exit 25
  printf '{}' > generated/locales/en.json
  exit 0
fi
[[ "$API_V3_SCHEMA_CAPTURE_DIR" == tmp/api-v3-schema-captures ]]
[[ -f "$API_V3_SCHEMA_CAPTURE_DIR/fresh.json" ]]
[[ "$*" == 'test:base run src/tests/contracts/v3-http-producer-contract.spec.ts src/tests/schemas/api/v3-openapi-producer.spec.ts' ]]
printf 'consumer\\n' >> order
touch consumed
[[ "$MODE" != consumer-failure ]] || exit 24
''')
        runner.chmod(0o755)
        pnpm.chmod(0o755)
        result = subprocess.run([shutil.which('bash'), str(script)], cwd=work,
            env={'PATH': str(work / 'bin') + os.pathsep + os.environ['PATH'], 'MODE': mode,
                 'API_V3_SCHEMA_CAPTURE_DIR': 'must-not-use-ambient-directory'},
            capture_output=True, text=True, timeout=10)
        assert result.returncode == expected, (mode, result.returncode, result.stderr)
        assert (work / 'consumed').exists() == consumed, mode
        expected_order = ['codegen']
        if mode != 'codegen-failure':
            expected_order.append('producer')
        if consumed:
            expected_order.append('consumer')
        assert (work / 'order').read_text().splitlines() == expected_order, mode
        assert not (captures / 'stale.json').exists(), mode
        print(f'PASS: {mode} (exit {expected}); order {expected_order}; stale captures removed')
PY
