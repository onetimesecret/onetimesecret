// src/tests/shared/utils/brand-token-guard.spec.ts

import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative, resolve } from 'node:path';

import { describe, expect, it } from 'vitest';

/**
 * Brand font-token guard.
 *
 * Dynamic `fontFamilyClasses[...]` indexing is how the heading/body font
 * ladder got hand-copied into consumers and drifted (a masthead heading
 * rendered in the body font in production). The value→class mapping must flow
 * through resolveBodyFontClass / resolveHeadingFontClass; brand-helpers.ts is
 * the ONLY file allowed to index the map by dynamic key. Dot access
 * (`fontFamilyClasses.sans`) stays legal for explicit presentation defaults.
 */
describe('brand token guard — fontFamilyClasses dynamic indexing', () => {
  const srcRoot = resolve(process.cwd(), 'src');
  const allowedFile = resolve(srcRoot, 'shared/utils/brand-helpers.ts');
  const testsRoot = resolve(srcRoot, 'tests');

  function walk(dir: string): string[] {
    return readdirSync(dir).flatMap((name) => {
      const full = join(dir, name);
      if (full === testsRoot) return [];
      if (statSync(full).isDirectory()) return walk(full);
      return /\.(ts|vue)$/.test(name) && full !== allowedFile ? [full] : [];
    });
  }

  const files = walk(srcRoot);

  it('finds source files to scan', () => {
    expect(files.length).toBeGreaterThan(0);
  });

  it('no file outside brand-helpers.ts indexes fontFamilyClasses dynamically', () => {
    // `?.`/`!` variants (`fontFamilyClasses?.[font]`) index just as
    // dynamically as the bare form and must not slip past the guard.
    const offenders = files
      .filter((file) =>
        /fontFamilyClasses\s*(\?\.|!)?\s*\[/.test(readFileSync(file, 'utf8'))
      )
      .map((file) => relative(process.cwd(), file));

    expect(
      offenders,
      'Dynamic fontFamilyClasses[...] indexing found in:\n' +
        offenders.map((f) => `  ${f}`).join('\n') +
        '\nUse resolveBodyFontClass/resolveHeadingFontClass from' +
        ' src/shared/utils/brand-helpers.ts instead.'
    ).toEqual([]);
  });
});
