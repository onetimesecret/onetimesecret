// src/tests/schemas/checkCli.spec.ts

import { spawnSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const root = fileURLToPath(new URL('../../../', import.meta.url));
const tsx = createRequire(import.meta.url).resolve('tsx/cli');

/** Run the CLI as documented in its header, with the payload on stdin. */
function runCheck(...args: string[]) {
  return (payload: unknown) =>
    spawnSync(
      process.execPath,
      [tsx, '--tsconfig', 'tsconfig.json', 'src/schemas/scripts/check.ts', ...args],
      { cwd: root, input: JSON.stringify(payload), encoding: 'utf8', timeout: 30_000 }
    );
}

describe('src/schemas/scripts/check.ts', () => {
  // shapes/organization reaches entitlementSchema directly; shapes/feedback
  // reaches it only through the closest-schema ranking.
  it.each(['shapes/organization', 'shapes/feedback'])(
    'suppresses payload-bearing schema diagnostics when checking %s, including closest matches',
    (schema) => {
      const marker = `private-ent-marker-${schema}`;
      const run = runCheck(schema)({ entitlements: [marker] });

      expect(run.error).toBeUndefined();
      expect(run.status).toBe(1);
      expect(run.stdout).toContain(`INVALID against ${schema}`);
      expect(run.stdout).toContain('Closest schemas');
      expect(run.stdout).not.toContain(marker);
      expect(run.stderr).not.toContain(marker);
    },
    30_000
  );
});
