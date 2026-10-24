// src/build/plugins/checkLocaleChunks.ts

import type { Plugin } from 'vite';

import type { ChunkLike } from './checkCspChunkGraph';

/**
 * Vite plugin that fails the build when a locale other than English loads
 * with an entry, or when one chunk contains more than one locale.
 *
 * src/i18n.ts imports generated/locales/en.json eagerly (English is the
 * fallback for every locale) and every other locale lazily, fetched when that
 * locale is activated. A non-English locale module in an entry chunk, or in
 * any chunk an entry reaches through static imports, is downloaded on every
 * page load whatever the visitor's language. A lazy chunk holding several
 * locales downloads all of them for a visitor who needs one. An eager glob, a
 * static import of one locale file, or a chunk group that merges locale
 * modules each cause one of these, and nothing fails: the download grows by
 * megabytes. This turns them into a failed build.
 */

const LOCALE_MODULE = /\/generated\/locales\/([^/?]+)\.json(?:\?.*)?$/;
const EAGER_LOCALE = 'en';

/**
 * Returns one message per offending chunk: one that loads with an entry and
 * contains a non-English locale module, or else one that contains more than one
 * locale module. An empty array means English loads with the entries and
 * every other locale has a lazy chunk of its own.
 */
export function findLocaleChunkViolations(bundle: Readonly<Record<string, ChunkLike>>): string[] {
  const chunks = Object.values(bundle).filter((output) => output.type === 'chunk');
  const byFileName = new Map(chunks.map((chunk) => [chunk.fileName, chunk]));
  const loadedBy = entriesByLoadedChunk(chunks, byFileName);

  return chunks.flatMap((chunk) => {
    const locales = localesIn(chunk);
    const lazy = locales.filter((locale) => locale !== EAGER_LOCALE);
    const entries = loadedBy.get(chunk);
    if (entries && lazy.length > 0) {
      const loadedWith = entries.join(', ');
      return [`${chunk.fileName} contains ${modulePaths(lazy)} and loads with entry ${loadedWith}`];
    }
    if (locales.length > 1) {
      return [`${chunk.fileName} contains ${modulePaths(locales)}, more than one locale`];
    }
    return [];
  });
}

/** Locale codes of the locale modules in `chunk`, English included. */
function localesIn(chunk: ChunkLike): string[] {
  return (chunk.moduleIds ?? []).flatMap((id) => {
    const locale = LOCALE_MODULE.exec(id)?.[1];
    return locale ? [locale] : [];
  });
}

const modulePaths = (locales: readonly string[]): string =>
  locales.map((locale) => `generated/locales/${locale}.json`).join(', ');

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
        '[check-locale-chunks] locales must load on demand, one chunk each, with only ' +
          `en.json in the entries (see src/i18n.ts):\n - ${violations.join('\n - ')}`
      );
    }
  },
});
