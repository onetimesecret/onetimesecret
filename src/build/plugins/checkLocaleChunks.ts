// src/build/plugins/checkLocaleChunks.ts

import type { Plugin } from 'vite';

import type { ChunkLike } from './checkCspChunkGraph';

/**
 * Vite plugin that fails the build when a locale other than English loads
 * with an entry.
 *
 * src/i18n.ts imports generated/locales/en.json eagerly (English is the
 * fallback for every locale) and every other locale lazily, one chunk each,
 * fetched when that locale is activated. A non-English locale module in an
 * entry chunk, or in any chunk an entry reaches through static imports, is
 * downloaded on every page load whatever the visitor's language. An eager
 * glob, a static import of one locale file, or a chunk group that merges the
 * locale chunks into a shared chunk each cause that, and nothing fails: the
 * entry graph grows by megabytes. This turns it into a failed build.
 */

const LOCALE_MODULE = /\/generated\/locales\/([^/?]+)\.json(?:\?.*)?$/;
const EAGER_LOCALE = 'en';

/**
 * Returns one message per chunk that loads with an entry and holds a
 * non-English locale module; an empty array means every such locale stays
 * in a lazy chunk.
 */
export function findLocaleChunkViolations(bundle: Readonly<Record<string, ChunkLike>>): string[] {
  const chunks = Object.values(bundle).filter((output) => output.type === 'chunk');
  const byFileName = new Map(chunks.map((chunk) => [chunk.fileName, chunk]));

  return [...entriesByLoadedChunk(chunks, byFileName)].flatMap(([chunk, entries]) => {
    const locales = lazyLocalesIn(chunk);
    if (locales.length === 0) return [];
    const modules = locales.map((locale) => `generated/locales/${locale}.json`).join(', ');
    return [`${chunk.fileName} contains ${modules} and loads with entry ${entries.join(', ')}`];
  });
}

/** Locale codes of the non-English locale modules in `chunk`. */
function lazyLocalesIn(chunk: ChunkLike): string[] {
  return (chunk.moduleIds ?? []).flatMap((id) => {
    const locale = LOCALE_MODULE.exec(id)?.[1];
    return locale && locale !== EAGER_LOCALE ? [locale] : [];
  });
}

/**
 * Every chunk that loads with an entry (the entry itself and what it reaches
 * through static imports; dynamic imports do not count), mapped to the
 * entries that load it.
 */
function entriesByLoadedChunk(
  chunks: readonly ChunkLike[],
  byFileName: ReadonlyMap<string, ChunkLike>
): Map<ChunkLike, string[]> {
  const loadedBy = new Map<ChunkLike, string[]>();
  for (const entry of chunks.filter((chunk) => chunk.isEntry)) {
    for (const chunk of staticGraph(entry, byFileName)) {
      loadedBy.set(chunk, [...(loadedBy.get(chunk) ?? []), entry.fileName]);
    }
  }
  return loadedBy;
}

/** Breadth-first walk over static imports, starting with `entry` itself. */
function staticGraph(entry: ChunkLike, byFileName: ReadonlyMap<string, ChunkLike>): ChunkLike[] {
  const seen = new Set<string>([entry.fileName]);
  const graph = [entry];
  for (let index = 0; index < graph.length; index++) {
    for (const fileName of graph[index].imports ?? []) {
      const chunk = byFileName.get(fileName);
      if (!chunk || seen.has(fileName)) continue;
      seen.add(fileName);
      graph.push(chunk);
    }
  }
  return graph;
}

export const checkLocaleChunks = (): Plugin => ({
  name: 'check-locale-chunks',
  generateBundle(_options, bundle) {
    const violations = findLocaleChunkViolations(bundle);
    if (violations.length > 0) {
      throw new Error(
        '[check-locale-chunks] a non-English locale loads with an entry instead of ' +
          `on demand (see src/i18n.ts):\n - ${violations.join('\n - ')}`
      );
    }
  },
});
