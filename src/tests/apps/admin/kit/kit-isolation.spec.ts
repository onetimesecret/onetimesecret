// src/tests/apps/admin/kit/kit-isolation.spec.ts

import { readdirSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { describe, expect, it } from 'vitest';

/**
 * Architecture guard for the admin UI kit (ticket #11).
 *
 * The kit is re-homed under `src/apps/admin/components/kit/` precisely so the
 * isolated admin bundle never imports the retiring `src/apps/colonel/` tree
 * (that is why the pagination control was re-homed rather than reused in place).
 * These tests fail if any kit module grows an import edge into the legacy
 * colonel app or the monolithic colonel god-store.
 */
describe('admin UI kit — import isolation (CONTRACT 5)', () => {
  const kitDir = resolve(process.cwd(), 'src/apps/admin/components/kit');

  const kitFiles = readdirSync(kitDir)
    .filter((name) => /\.(ts|vue)$/.test(name))
    .map((name) => resolve(kitDir, name));

  it('finds the kit source files', () => {
    // Sanity: the six components + re-homed pagination + support modules exist.
    expect(kitFiles.length).toBeGreaterThanOrEqual(8);
  });

  it.each(kitFiles.map((f) => [f]))(
    '%s has ZERO import edge into the retiring colonel tree',
    (file: string) => {
      const source = readFileSync(file, 'utf8');
      const importLines = source
        .split('\n')
        .filter((line) => /^\s*import[\s{]/.test(line) || /\bfrom\s+['"]/.test(line));
      const joined = importLines.join('\n');

      expect(joined).not.toMatch(/apps\/colonel/);
      expect(joined).not.toMatch(/colonelInfoStore/);
    }
  );

  it('exposes the six kit components + re-homed pagination from the barrel', async () => {
    const kit = await import('@/apps/admin/components/kit');
    for (const name of [
      'DataTable',
      'StatCard',
      'FilterBar',
      'DetailDrawer',
      'JsonViewer',
      'AdminConfirmDialog',
      'KitPagination',
    ]) {
      expect(kit[name as keyof typeof kit]).toBeTruthy();
    }
  });
});
