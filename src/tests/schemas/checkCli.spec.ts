import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const root = fileURLToPath(new URL('../../../', import.meta.url));
const tsxCli = fileURLToPath(import.meta.resolve('tsx/cli'));

function organizationInput(entitlement: string) {
  return {
    objid: 'organization-test',
    extid: 'on-organization-test',
    display_name: 'Organization test',
    description: null,
    contact_email: null,
    is_default: false,
    planid: 'free_v1',
    created: 1700000000,
    updated: 1700000000,
    entitlements: [entitlement],
  };
}

function runCheck(schema: string, input: unknown) {
  const result = spawnSync(
    process.execPath,
    [tsxCli, '--tsconfig', 'tsconfig.json', 'src/schemas/scripts/check.ts', schema],
    {
      cwd: root,
      input: JSON.stringify(input),
      encoding: 'utf8',
      timeout: 10000,
    }
  );
  expect(result.error).toBeUndefined();
  expect(result.signal).toBeNull();
  return result;
}

describe('schema check CLI diagnostics (F1)', () => {
  it.each([true, false])(
    'does not expose unfamiliar entitlements for a selected organization (valid: %s)',
    (valid) => {
      const privateMarker = `F1-private-selected-entitlement-${valid}`;
      const input = {
        ...organizationInput(privateMarker),
        created: valid ? 1700000000 : 'not-a-timestamp',
      };
      const result = runCheck('shapes/organization', input);

      expect(result.status).toBe(valid ? 0 : 1);
      expect(result.stdout).toContain(
        valid ? 'OK: valid against shapes/organization' : 'INVALID against shapes/organization'
      );
      if (!valid) expect(result.stdout).toContain('Closest schemas (by fields recognised):');
      expect(result.stdout).not.toContain(privateMarker);
      expect(result.stderr).not.toContain(privateMarker);
      expect(result.stderr).toBe('');
    },
    15000
  );

  it('does not expose unfamiliar entitlements when organization is a fallback candidate', () => {
    const privateMarker = 'F1-private-fallback-entitlement';
    const result = runCheck('shapes/secret', organizationInput(privateMarker));

    expect(result.status).toBe(1);
    expect(result.stdout).toContain('INVALID against shapes/secret');
    expect(result.stdout).toContain('Closest schemas (by fields recognised):');
    expect(result.stdout).toMatch(/shapes\/organization\s+\d+ matched\s+valid/);
    expect(result.stdout).not.toContain(privateMarker);
    expect(result.stderr).not.toContain(privateMarker);
    expect(result.stderr).toBe('');
  }, 15000);
});
