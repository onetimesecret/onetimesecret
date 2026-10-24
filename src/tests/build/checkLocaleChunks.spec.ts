// src/tests/build/checkLocaleChunks.spec.ts

/**
 * The build-time guard for lazy locales (src/build/plugins/checkLocaleChunks.ts):
 * generated/locales/en.json loads with the entries, every other locale module
 * stays out of the entries and out of every chunk they import statically, so
 * it is fetched only when its locale is activated, and no chunk holds more
 * than one locale, so a visitor downloads only the language they need.
 *
 * Run:
 *   pnpm test src/tests/build/checkLocaleChunks.spec.ts
 */

import { describe, expect, it } from 'vitest';

import { type ChunkLike } from '../../build/plugins/checkCspChunkGraph';
import { findLocaleChunkViolations } from '../../build/plugins/checkLocaleChunks';

const locale = (code: string) => `/repo/generated/locales/${code}.json`;

function chunk(fileName: string, extra: Partial<ChunkLike> = {}): ChunkLike {
  return { type: 'chunk', fileName, imports: [], moduleIds: [], ...extra };
}

/**
 * Two entries that share a chunk holding en.json; bg and nl are lazy chunks
 * reached only through dynamic imports. One stylesheet asset, which the check
 * must ignore.
 */
function soundBundle(): Record<string, ChunkLike> {
  return {
    'assets/main.AAAA.js': chunk('assets/main.AAAA.js', {
      name: 'main',
      isEntry: true,
      imports: ['assets/i18n-BBBB.js'],
      moduleIds: ['/repo/src/main.ts'],
    }),
    'assets/admin.CCCC.js': chunk('assets/admin.CCCC.js', {
      name: 'admin',
      isEntry: true,
      imports: ['assets/i18n-BBBB.js'],
      moduleIds: ['/repo/src/admin.ts'],
    }),
    'assets/i18n-BBBB.js': chunk('assets/i18n-BBBB.js', {
      name: 'i18n',
      moduleIds: ['/repo/src/i18n.ts', locale('en')],
    }),
    'assets/bg-DDDD.js': chunk('assets/bg-DDDD.js', { name: 'bg', moduleIds: [locale('bg')] }),
    'assets/nl-EEEE.js': chunk('assets/nl-EEEE.js', { name: 'nl', moduleIds: [locale('nl')] }),
    'assets/style.FFFF.css': { type: 'asset', fileName: 'assets/style.FFFF.css' },
  };
}

describe('findLocaleChunkViolations', () => {
  it('accepts en in a shared entry chunk and the other locales in lazy chunks', () => {
    expect(findLocaleChunkViolations(soundBundle())).toEqual([]);
  });

  it('reports a locale bundled into an entry chunk, with the entry named', () => {
    const bundle = soundBundle();
    bundle['assets/main.AAAA.js'].moduleIds = ['/repo/src/main.ts', locale('bg')];

    expect(findLocaleChunkViolations(bundle)).toEqual([
      'assets/main.AAAA.js contains generated/locales/bg.json and loads with entry assets/main.AAAA.js',
    ]);
  });

  it('reports locales in a chunk an entry imports statically, naming every entry that loads it', () => {
    const bundle = soundBundle();
    bundle['assets/i18n-BBBB.js'].moduleIds = [
      '/repo/src/i18n.ts',
      locale('en'),
      locale('bg'),
      locale('de_AT'),
    ];

    expect(findLocaleChunkViolations(bundle)).toEqual([
      'assets/i18n-BBBB.js contains generated/locales/bg.json, generated/locales/de_AT.json ' +
        'and loads with entry assets/main.AAAA.js, assets/admin.CCCC.js',
    ]);
  });

  it('follows static imports transitively', () => {
    const bundle = soundBundle();
    bundle['assets/i18n-BBBB.js'].imports = ['assets/nl-EEEE.js'];

    expect(findLocaleChunkViolations(bundle)).toEqual([
      'assets/nl-EEEE.js contains generated/locales/nl.json ' +
        'and loads with entry assets/main.AAAA.js, assets/admin.CCCC.js',
    ]);
  });

  it('matches a locale module id that carries a query string', () => {
    const bundle = soundBundle();
    bundle['assets/admin.CCCC.js'].moduleIds = ['/repo/src/admin.ts', `${locale('ja')}?import`];

    expect(findLocaleChunkViolations(bundle)).toEqual([
      'assets/admin.CCCC.js contains generated/locales/ja.json and loads with entry assets/admin.CCCC.js',
    ]);
  });

  it('ignores a locale that only an unloaded chunk holds', () => {
    const bundle = soundBundle();
    // A dynamic import is not in `imports`, so this chunk loads with nothing.
    bundle['assets/feature-GGGG.js'] = chunk('assets/feature-GGGG.js', {
      moduleIds: ['/repo/src/feature.ts', locale('ru')],
    });

    expect(findLocaleChunkViolations(bundle)).toEqual([]);
  });

  it('reports a lazy chunk that holds more than one locale', () => {
    const bundle = soundBundle();
    bundle['assets/bg-DDDD.js'].moduleIds = [locale('bg'), locale('nl')];
    delete bundle['assets/nl-EEEE.js'];

    expect(findLocaleChunkViolations(bundle)).toEqual([
      'assets/bg-DDDD.js contains generated/locales/bg.json, generated/locales/nl.json, ' +
        'more than one locale',
    ]);
  });

  it('counts English when a lazy chunk holds it with another locale', () => {
    const bundle = soundBundle();
    bundle['assets/bg-DDDD.js'].moduleIds = [locale('en'), locale('bg')];

    expect(findLocaleChunkViolations(bundle)).toEqual([
      'assets/bg-DDDD.js contains generated/locales/en.json, generated/locales/bg.json, ' +
        'more than one locale',
    ]);
  });

  it('accepts a lazy chunk with one locale next to other modules', () => {
    const bundle = soundBundle();
    bundle['assets/bg-DDDD.js'].moduleIds = ['/repo/src/feature.ts', locale('bg')];

    expect(findLocaleChunkViolations(bundle)).toEqual([]);
  });

  // One message per chunk: the entry-loaded one says more than the count.
  it('reports an entry-loaded chunk with several locales once, as loading with the entry', () => {
    const bundle = soundBundle();
    bundle['assets/i18n-BBBB.js'].moduleIds = [
      '/repo/src/i18n.ts',
      locale('en'),
      locale('bg'),
      locale('nl'),
    ];

    expect(findLocaleChunkViolations(bundle)).toEqual([
      'assets/i18n-BBBB.js contains generated/locales/bg.json, generated/locales/nl.json ' +
        'and loads with entry assets/main.AAAA.js, assets/admin.CCCC.js',
    ]);
  });

  it('survives an import cycle between chunks', () => {
    const bundle = soundBundle();
    bundle['assets/i18n-BBBB.js'].imports = ['assets/bg-DDDD.js'];
    bundle['assets/bg-DDDD.js'].imports = ['assets/i18n-BBBB.js'];

    expect(findLocaleChunkViolations(bundle)).toEqual([
      'assets/bg-DDDD.js contains generated/locales/bg.json ' +
        'and loads with entry assets/main.AAAA.js, assets/admin.CCCC.js',
    ]);
  });
});
