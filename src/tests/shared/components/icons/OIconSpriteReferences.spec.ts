// src/tests/shared/components/icons/OIconSpriteReferences.spec.ts
//
// OIcon renders <use href="#<collection>-<name>">. When no mounted sprite
// defines that <symbol id>, the icon draws nothing and nothing fails. These
// specs read the source under src/ and check every static icon reference
// against the ids App.vue mounts: CriticalSprites plus every
// iconLibraryComponents loader. Bound values (:name="...") are not checked.

import { mount } from '@vue/test-utils';
import { describe, expect, it } from 'vitest';
import StatCard from '@/apps/admin/components/kit/StatCard.vue';
import { CONSOLE_SECTIONS } from '@/apps/admin/sections';
import { loadSpriteSymbolIds, staticOIconIds } from '@tests/support/spriteSymbols';

const vueSources = import.meta.glob<string>(['/src/**/*.vue', '!/src/tests/**'], {
  query: '?raw',
  import: 'default',
  eager: true,
});

const tsSources = import.meta.glob<string>(
  ['/src/**/*.ts', '!/src/tests/**', '!/src/**/*.d.ts'],
  { query: '?raw', import: 'default', eager: true }
);

/**
 * Sprite ids for `{ collection: '...', name: '...' }` object literals, the
 * shape icon maps use (settings-navigation.ts, jurisdictions.ts). Typed
 * fields such as `collection: string` have no quoted value and are skipped.
 */
const objectLiteralIconIds = (source: string): string[] =>
  [...source.matchAll(/\bcollection:\s*(['"])(.*?)\1\s*,\s*name:\s*(['"])(.*?)\3/g)].map(
    ([, , collection, , name]) => [collection, name].filter(Boolean).join('-')
  );

const unresolved = (
  sources: Record<string, string>,
  extract: (source: string) => string[],
  ids: Set<string>
) =>
  Object.entries(sources)
    .flatMap(([path, source]) => extract(source).map((id) => `${path} ${id}`))
    .filter((ref) => !ids.has(ref.slice(ref.lastIndexOf(' ') + 1)))
    .sort();

/**
 * Sprite ids for each <StatCard icon="..."> with a static icon. StatCard passes
 * `icon` to OIcon in `iconCollection`; without a static `icon-collection` the
 * tile uses its default, which the caller reads from a mounted StatCard.
 */
const statCardIconIds =
  (defaultCollection: string) =>
  (source: string): string[] =>
    [...source.matchAll(/<StatCard\b([^>]*?)\/?>/gs)].flatMap(([, attrs]) => {
      const icon = attrs.match(/(?<![:\w-])icon="([^"]*)"/)?.[1];
      // A bound collection can't be resolved from source.
      if (icon === undefined || /:icon-collection=/.test(attrs)) return [];
      const collection =
        attrs.match(/(?<![:\w-])icon-collection="([^"]*)"/)?.[1] ?? defaultCollection;
      return [[collection, icon].filter(Boolean).join('-')];
    });

// Sprites mount inside each test: the router mock that mount() needs is
// installed per test, so a beforeAll mount fails.
describe('static icon references', () => {
  it('reads the app source', () => {
    // An empty glob or a regex that stops matching would make every
    // assertion below pass vacuously.
    const oiconRefs = Object.values(vueSources).flatMap(staticOIconIds);
    const literalRefs = Object.values(tsSources).flatMap(objectLiteralIconIds);
    const statCardRefs = Object.values(vueSources).flatMap(statCardIconIds('heroicons'));
    expect(Object.keys(vueSources).length).toBeGreaterThan(100);
    expect(oiconRefs.length).toBeGreaterThan(100);
    expect(literalRefs.length).toBeGreaterThan(10);
    expect(statCardRefs.length).toBeGreaterThan(10);
  });

  it('every static <OIcon collection name> in an SFC resolves to a sprite symbol', async () => {
    const ids = await loadSpriteSymbolIds();
    expect(unresolved(vueSources, staticOIconIds, ids)).toEqual([]);
  });

  it('every { collection, name } icon literal in a .ts file resolves to a sprite symbol', async () => {
    const ids = await loadSpriteSymbolIds();
    expect(unresolved(tsSources, objectLiteralIconIds, ids)).toEqual([]);
  });

  it('every static <StatCard icon> resolves to a sprite symbol', async () => {
    const ids = await loadSpriteSymbolIds();
    const probe = mount(StatCard, { props: { label: 'probe', icon: 'probe' } });
    const href = probe.find('use').attributes('href') ?? '';
    const defaultCollection = href.slice(1, -'-probe'.length);
    expect(defaultCollection).not.toBe('');

    expect(unresolved(vueSources, statCardIconIds(defaultCollection), ids)).toEqual([]);
  });

  it('every admin console section icon resolves to a heroicons symbol', async () => {
    const ids = await loadSpriteSymbolIds();
    // AdminLayout renders section.icon with collection="heroicons".
    const missing = CONSOLE_SECTIONS.map((section) => `heroicons-${section.icon}`).filter(
      (id) => !ids.has(id)
    );
    expect(missing).toEqual([]);
  });
});
