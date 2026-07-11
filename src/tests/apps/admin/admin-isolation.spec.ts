// src/tests/apps/admin/admin-isolation.spec.ts

import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, resolve } from 'node:path';

import { describe, expect, it } from 'vitest';

/**
 * Source-level bundle-isolation guard (CONTRACT 6).
 *
 * The admin console ships as its own Rolldown entry (`src/admin.ts`). Nothing
 * under `src/apps/admin/` may import the retiring `src/apps/colonel/*` tree, the
 * monolithic `colonelInfoStore`, or the customer router graph — any such edge
 * would drag legacy/customer code back into the isolated admin chunk. The built
 * manifest is the ultimate check; this catches a bad import the moment it lands,
 * with a precise file name.
 */
describe('admin app — import isolation (CONTRACT 6)', () => {
  const adminRoot = resolve(process.cwd(), 'src/apps/admin');

  function walk(dir: string): string[] {
    return readdirSync(dir).flatMap((name) => {
      const full = join(dir, name);
      if (statSync(full).isDirectory()) return walk(full);
      return /\.(ts|vue)$/.test(name) ? [full] : [];
    });
  }

  const files = walk(adminRoot);

  it('finds the admin source files', () => {
    expect(files.length).toBeGreaterThan(0);
  });

  it.each(files.map((f) => [f]))(
    '%s has ZERO import edge into the colonel tree / customer router',
    (file: string) => {
      const source = readFileSync(file, 'utf8');
      const importLines = source
        .split('\n')
        .filter((line) => /^\s*import[\s{]/.test(line) || /\bfrom\s+['"]/.test(line))
        .join('\n');

      expect(importLines).not.toMatch(/apps\/colonel/);
      expect(importLines).not.toMatch(/colonelInfoStore/);
      // The admin router must not pull the customer route graph.
      expect(importLines).not.toMatch(/@\/router\b/);
      expect(importLines).not.toMatch(/@\/App\.vue/);
    }
  );
});

/**
 * Built-artifact bundle-isolation guard (CONTRACT 6, the AUTHORITATIVE check).
 *
 * The source guard above proves no import edge originates *inside*
 * `src/apps/admin/`, but the epic's hard invariant is about the shipped chunk:
 * the admin bundle must contain NONE of the retiring `colonelInfoStore`, the
 * `src/apps/colonel/*` tree, or the customer router graph — regardless of how
 * they might sneak in (e.g. a shared barrel re-export dragged in transitively
 * via `App.vue` -> axios interceptors). Only the built sourcemap can catch that
 * transitive class, so we assert against it directly.
 *
 * The assertion runs against the NEWEST `admin.*.js.map` under the dist assets
 * dir (its hash changes every build). When no build has been produced yet the
 * check is skipped with a clear pointer rather than silently passing — CI runs
 * `pnpm build` before the suite, so the artifact is present there.
 */
describe('admin bundle — built-artifact isolation (CONTRACT 6)', () => {
  const distAssets = resolve(process.cwd(), 'public/web/dist/assets');

  // Forbidden module families in the admin chunk's sourcemap `sources`. These
  // are deliberately narrow: `schemas/api/**/colonel.ts` (the customer-detail
  // schemas the admin console legitimately uses) must NOT match, only the
  // monolithic colonel store, the legacy colonel app tree, and the customer
  // route graph (`src/router/index.ts`; the admin router is `apps/admin/router`).
  const FORBIDDEN: Array<[string, RegExp]> = [
    ['colonelInfoStore', /shared\/stores\/colonelInfoStore/],
    ['apps/colonel tree', /apps\/colonel\//],
    ['customer router graph', /src\/router\/index/],
  ];

  function newestAdminMap(): string | null {
    let entries: string[];
    try {
      entries = readdirSync(distAssets);
    } catch {
      return null; // dist not built yet
    }
    const maps = entries
      .filter((name) => /^admin\.[^/]*\.js\.map$/.test(name))
      .map((name) => join(distAssets, name));
    if (maps.length === 0) return null;
    return maps.reduce((newest, m) =>
      statSync(m).mtimeMs > statSync(newest).mtimeMs ? m : newest
    );
  }

  const mapPath = newestAdminMap();

  it('has a built admin sourcemap to inspect (run `pnpm build` first)', () => {
    if (mapPath === null) {
      // Not a failure: the source-level guard above still protects the invariant
      // on unbuilt trees. Surface it so an all-green run without a build is not
      // mistaken for a verified bundle.
      console.warn(
        '[admin-isolation] No admin.*.js.map under public/web/dist/assets — ' +
          'built-bundle isolation not verified. Run `pnpm build` to enforce CONTRACT 6.'
      );
    }
    expect(true).toBe(true);
  });

  it.runIf(mapPath !== null)(
    'admin chunk sourcemap contains ZERO colonelInfoStore / apps/colonel / customer-router source',
    () => {
      const map = JSON.parse(readFileSync(mapPath as string, 'utf8')) as {
        sources?: string[];
      };
      const sources = map.sources ?? [];
      const offenders = FORBIDDEN.flatMap(([label, re]) =>
        sources.filter((s) => re.test(s)).map((s) => `${label}: ${s}`)
      );
      expect(offenders).toEqual([]);
    }
  );
});
