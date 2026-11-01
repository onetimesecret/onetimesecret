// src/build/plugins/checkCspChunkGraph.ts

import type { Plugin } from 'vite';

/**
 * Vite plugin that fails the build when the chunk graph loses a shape the
 * nonce-only CSP model depends on (see the CSP note in vite.config.ts).
 *
 * Checked once the chunks are generated:
 * 1. src/plugins/core/configureZod.ts sits in the chunk named `zod`, together
 *    with every module of the zod package, so `z.config({ jitless: true })`
 *    runs before any schema is constructed. With configureZod in a chunk that
 *    runs after the first schemas, Zod's `new Function("")` probe trips a
 *    script-src violation on every page load, with no functional symptom.
 * 2. Every entry chunk reaches the zod chunk through static imports, so that
 *    ordering guarantee applies to each shell.
 *
 * Both regress silently (a chunking change in Rolldown or in
 * output.advancedChunks) and only a browser run would notice; this turns them
 * into a failed build.
 */

const ZOD_CHUNK_NAME = 'zod';
const CONFIGURE_ZOD_SUFFIX = '/src/plugins/core/configureZod.ts';
const ZOD_PACKAGE_SEGMENT = '/node_modules/zod/';

/** The subset of a Rolldown output chunk the check reads. */
export interface ChunkLike {
  type: string;
  fileName: string;
  name?: string;
  isEntry?: boolean;
  imports?: readonly string[];
  moduleIds?: readonly string[];
}

/**
 * Returns one message per violated invariant; an empty array means the chunk
 * graph is sound.
 */
export function findCspChunkGraphViolations(bundle: Readonly<Record<string, ChunkLike>>): string[] {
  const chunks = Object.values(bundle).filter((output) => output.type === 'chunk');
  const zodChunk = chunks.find((chunk) => chunk.name === ZOD_CHUNK_NAME);
  if (!zodChunk) {
    return [
      `no chunk named "${ZOD_CHUNK_NAME}" (is the output.advancedChunks group still there?)`,
      ...leakViolations(chunks, undefined),
    ];
  }
  return [
    ...zodChunkViolations(zodChunk),
    ...leakViolations(chunks, zodChunk),
    ...reachabilityViolations(chunks, zodChunk),
  ];
}

/** The zod chunk must hold configureZod.ts and at least one zod module. */
function zodChunkViolations(zodChunk: ChunkLike): string[] {
  const ids = zodChunk.moduleIds ?? [];
  const violations: string[] = [];
  if (!ids.some((id) => id.endsWith(CONFIGURE_ZOD_SUFFIX))) {
    violations.push(`${zodChunk.fileName} does not contain ${CONFIGURE_ZOD_SUFFIX.slice(1)}`);
  }
  if (!ids.some((id) => id.includes(ZOD_PACKAGE_SEGMENT))) {
    violations.push(`${zodChunk.fileName} contains no module of the zod package`);
  }
  return violations;
}

/** No zod module, and no configureZod.ts, anywhere but the zod chunk. */
function leakViolations(chunks: readonly ChunkLike[], zodChunk: ChunkLike | undefined): string[] {
  return chunks.flatMap((chunk) => {
    if (chunk === zodChunk) return [];
    const leaked = (chunk.moduleIds ?? []).filter(
      (id) => id.includes(ZOD_PACKAGE_SEGMENT) || id.endsWith(CONFIGURE_ZOD_SUFFIX)
    );
    if (leaked.length === 0) return [];
    return [
      `${chunk.fileName} contains ${leaked.length} zod module(s) outside the ${ZOD_CHUNK_NAME} chunk`,
    ];
  });
}

/** Every entry must reach the zod chunk through static imports. */
function reachabilityViolations(chunks: readonly ChunkLike[], zodChunk: ChunkLike): string[] {
  const byFileName = new Map(chunks.map((chunk) => [chunk.fileName, chunk]));
  return chunks
    .filter((chunk) => chunk.isEntry && !reachesStatically(chunk, zodChunk.fileName, byFileName))
    .map((entry) => `entry ${entry.fileName} does not import ${zodChunk.fileName} statically`);
}

/** Breadth-first walk over static imports only; dynamic imports do not count. */
function reachesStatically(
  from: ChunkLike,
  target: string,
  byFileName: ReadonlyMap<string, ChunkLike>
): boolean {
  const seen = new Set<string>();
  const queue = [...(from.imports ?? [])];
  for (let fileName = queue.shift(); fileName !== undefined; fileName = queue.shift()) {
    if (fileName === target) return true;
    if (seen.has(fileName)) continue;
    seen.add(fileName);
    queue.push(...(byFileName.get(fileName)?.imports ?? []));
  }
  return false;
}

export const checkCspChunkGraph = (): Plugin => ({
  name: 'check-csp-chunk-graph',
  generateBundle(_options, bundle) {
    const violations = findCspChunkGraphViolations(bundle);
    if (violations.length > 0) {
      throw new Error(
        '[check-csp-chunk-graph] the chunk graph no longer fits the CSP nonce model ' +
          `(see vite.config.ts):\n - ${violations.join('\n - ')}`
      );
    }
  },
});
