// src/tests/build/checkCspChunkGraph.spec.ts

/**
 * The build-time guard for the chunk graph the CSP nonce model depends on
 * (src/build/plugins/checkCspChunkGraph.ts): configureZod.ts shares the zod
 * chunk, no zod module lives anywhere else, and every entry reaches that
 * chunk through static imports.
 *
 * Run:
 *   pnpm test src/tests/build/checkCspChunkGraph.spec.ts
 */

import { describe, expect, it } from 'vitest';

import {
  findCspChunkGraphViolations,
  type ChunkLike,
} from '../../build/plugins/checkCspChunkGraph';

const ZOD_UTIL = '/repo/node_modules/.pnpm/zod@4.3.6/node_modules/zod/v4/core/util.js';
const CONFIGURE_ZOD = '/repo/src/plugins/core/configureZod.ts';

function chunk(fileName: string, extra: Partial<ChunkLike> = {}): ChunkLike {
  return { type: 'chunk', fileName, imports: [], moduleIds: [], ...extra };
}

/**
 * Two entries: main imports the zod chunk directly, admin reaches it through
 * a shared schemas chunk. One stylesheet asset, which the check must ignore.
 */
function soundBundle(): Record<string, ChunkLike> {
  return {
    'assets/main.AAAA.js': chunk('assets/main.AAAA.js', {
      name: 'main',
      isEntry: true,
      imports: ['assets/zod-BBBB.js', 'assets/vue-CCCC.js'],
      moduleIds: ['/repo/src/main.ts'],
    }),
    'assets/admin.DDDD.js': chunk('assets/admin.DDDD.js', {
      name: 'admin',
      isEntry: true,
      imports: ['assets/schemas-EEEE.js'],
      moduleIds: ['/repo/src/admin.ts'],
    }),
    'assets/schemas-EEEE.js': chunk('assets/schemas-EEEE.js', {
      name: 'schemas',
      imports: ['assets/zod-BBBB.js'],
      moduleIds: ['/repo/src/schemas/contracts/config/billing.ts'],
    }),
    'assets/zod-BBBB.js': chunk('assets/zod-BBBB.js', {
      name: 'zod',
      moduleIds: [ZOD_UTIL, CONFIGURE_ZOD],
    }),
    'assets/vue-CCCC.js': chunk('assets/vue-CCCC.js', {
      name: 'vue',
      moduleIds: ['/repo/node_modules/vue/index.js'],
    }),
    'assets/style.FFFF.css': { type: 'asset', fileName: 'assets/style.FFFF.css' },
  };
}

describe('findCspChunkGraphViolations', () => {
  it('accepts a graph where both entries reach the zod chunk statically', () => {
    expect(findCspChunkGraphViolations(soundBundle())).toEqual([]);
  });

  it('reports configureZod.ts chunked away from zod', () => {
    const bundle = soundBundle();
    bundle['assets/zod-BBBB.js'].moduleIds = [ZOD_UTIL];
    bundle['assets/schemas-EEEE.js'].moduleIds = [
      '/repo/src/schemas/contracts/config/billing.ts',
      CONFIGURE_ZOD,
    ];

    const violations = findCspChunkGraphViolations(bundle);

    expect(violations).toEqual([
      'assets/zod-BBBB.js does not contain src/plugins/core/configureZod.ts',
      'assets/schemas-EEEE.js contains 1 zod module(s) outside the zod chunk',
    ]);
  });

  it('reports a zod package module that leaked into another chunk', () => {
    const bundle = soundBundle();
    bundle['assets/vue-CCCC.js'].moduleIds = [
      '/repo/node_modules/vue/index.js',
      '/repo/node_modules/zod/v4/classic/schemas.js',
    ];

    expect(findCspChunkGraphViolations(bundle)).toEqual([
      'assets/vue-CCCC.js contains 1 zod module(s) outside the zod chunk',
    ]);
  });

  it('reports an entry that only reaches the zod chunk through a dynamic import', () => {
    const bundle = soundBundle();
    bundle['assets/admin.DDDD.js'].imports = [];

    expect(findCspChunkGraphViolations(bundle)).toEqual([
      'entry assets/admin.DDDD.js does not import assets/zod-BBBB.js statically',
    ]);
  });

  it('reports a missing zod chunk once, without walking the graph', () => {
    const bundle = soundBundle();
    delete bundle['assets/zod-BBBB.js'];

    expect(findCspChunkGraphViolations(bundle)).toEqual([
      'no chunk named "zod" (is the output.advancedChunks group still there?)',
    ]);
  });

  it('survives an import cycle between chunks', () => {
    const bundle = soundBundle();
    bundle['assets/vue-CCCC.js'].imports = ['assets/schemas-EEEE.js'];
    bundle['assets/schemas-EEEE.js'].imports = ['assets/vue-CCCC.js'];

    expect(findCspChunkGraphViolations(bundle)).toEqual([
      'entry assets/admin.DDDD.js does not import assets/zod-BBBB.js statically',
    ]);
  });
});
