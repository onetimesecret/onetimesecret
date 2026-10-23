// src/tests/apps/admin/admin-isolation.spec.ts

import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
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
 * `src/apps/admin/`, but the epic's hard invariant is about the shipped code:
 * nothing the admin entry loads may contain the retiring `colonelInfoStore`,
 * the `src/apps/colonel/*` tree, or the customer router graph — regardless of
 * how they might sneak in (e.g. a shared barrel re-export dragged in
 * transitively via `App.vue` -> axios interceptors). Only the built sourcemaps
 * can catch that transitive class, so we assert against them directly.
 *
 * The build is code-split (vite.config.ts): the admin entry chunk has only
 * the modules nothing else uses, what it shares with the customer entry sits
 * in shared chunks (`assets/<name>-<hash>.js`), and its lazy routes load their
 * own. The check therefore walks the entry's imports and dynamic imports
 * transitively from `.vite/manifest.json` (the graph the server shell preloads
 * from, see apps/web/core/views/helpers/vite_manifest.rb) and scans the
 * sourcemap of every reachable chunk. Rolldown emits no sourcemap for its
 * runtime and helper chunks, nor for a chunk that only re-exports; neither can
 * contain source of ours, so they are skipped. Any other chunk without a
 * sourcemap fails the check rather than shrinking it.
 *
 * When no build has been produced yet the check is skipped with a clear
 * pointer rather than silently passing. Run `pnpm build` first to enforce
 * CONTRACT 6 against the shipped chunks.
 */
describe('admin bundle — built-artifact isolation (CONTRACT 6)', () => {
  const dist = resolve(process.cwd(), 'public/web/dist');
  const ADMIN_ENTRY = 'admin.ts';

  interface ManifestChunk {
    file: string;
    imports?: string[];
    dynamicImports?: string[];
  }

  // Forbidden module families in the sourcemap `sources` of any chunk the
  // admin entry loads. These are deliberately narrow: `schemas/api/**/colonel.ts`
  // (the customer-detail schemas the admin console legitimately uses) must NOT
  // match, only the monolithic colonel store, the legacy colonel app tree, and
  // the customer route graph (`src/router/index.ts`; the admin router is
  // `apps/admin/router`).
  const FORBIDDEN: Array<[string, RegExp]> = [
    ['colonelInfoStore', /shared\/stores\/colonelInfoStore/],
    ['apps/colonel tree', /apps\/colonel\//],
    ['customer router graph', /src\/router\/index/],
  ];

  function readManifest(): Record<string, ManifestChunk> | null {
    const manifestPath = join(dist, '.vite/manifest.json');
    if (!existsSync(manifestPath)) return null; // dist not built yet
    return JSON.parse(readFileSync(manifestPath, 'utf8')) as Record<string, ManifestChunk>;
  }

  /** Files of every chunk reachable from `entry` through static and dynamic imports. */
  function reachableChunks(manifest: Record<string, ManifestChunk>, entry: string): string[] {
    const seen = new Set<string>([entry]);
    const queue = [entry];
    const files: string[] = [];
    for (let key = queue.shift(); key !== undefined; key = queue.shift()) {
      const chunk = manifest[key];
      if (!chunk) continue;
      files.push(chunk.file);
      for (const dep of [...(chunk.imports ?? []), ...(chunk.dynamicImports ?? [])]) {
        if (seen.has(dep)) continue;
        seen.add(dep);
        queue.push(dep);
      }
    }
    return files;
  }

  // Chunks Rolldown emits without a sourcemap and without source of ours.
  const HELPER_CHUNK = /^assets\/(?:preload-helper|rolldown-runtime|_plugin-vue_export-helper)-/;
  const REEXPORT_ONLY = /^(?:\s*(?:import|export)\b[^;]*;)*\s*$/;

  const manifest = readManifest();
  const adminEntry = manifest?.[ADMIN_ENTRY] ?? null;

  it('has a built manifest with the admin entry to inspect (run `pnpm build` first)', () => {
    if (adminEntry === null) {
      // Not a failure: the source-level guard above still protects the invariant
      // on unbuilt trees. Surface it so an all-green run without a build is not
      // mistaken for a verified bundle.
      console.warn(
        '[admin-isolation] No public/web/dist/.vite/manifest.json with an admin.ts entry — ' +
          'built-bundle isolation not verified. Run `pnpm build` to enforce CONTRACT 6.'
      );
    }
    expect(true).toBe(true);
  });

  it.runIf(adminEntry !== null)(
    'no chunk the admin entry loads contains colonelInfoStore / apps/colonel / customer-router source',
    () => {
      const files = reachableChunks(manifest as Record<string, ManifestChunk>, ADMIN_ENTRY);
      const inspected: string[] = [];
      const offenders: string[] = [];
      const unverifiable: string[] = [];
      for (const file of files) {
        const mapPath = join(dist, `${file}.map`);
        if (!existsSync(mapPath)) {
          const harmless =
            HELPER_CHUNK.test(file) || REEXPORT_ONLY.test(readFileSync(join(dist, file), 'utf8'));
          if (!harmless) unverifiable.push(file);
          continue;
        }
        inspected.push(file);
        const map = JSON.parse(readFileSync(mapPath, 'utf8')) as { sources?: string[] };
        const sources = map.sources ?? [];
        offenders.push(
          ...FORBIDDEN.flatMap(([label, re]) =>
            sources.filter((s) => re.test(s)).map((s) => `${file}: ${label}: ${s}`)
          )
        );
      }

      // The entry's own chunk and the ones it shares with the customer entry:
      // a walk that reached only the entry would be the vacuous check again.
      expect(inspected).toContain((adminEntry as ManifestChunk).file);
      expect(inspected.length).toBeGreaterThan(1);
      // A chunk this check could not read is a gap, not a pass.
      expect(unverifiable).toEqual([]);
      expect(offenders).toEqual([]);
    }
  );
});
