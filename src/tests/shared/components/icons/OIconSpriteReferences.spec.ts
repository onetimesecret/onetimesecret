// src/tests/shared/components/icons/OIconSpriteReferences.spec.ts
//
// OIcon renders <use href="#<collection>-<name>">. When no mounted sprite
// defines that <symbol id>, the icon draws nothing and nothing fails. These
// specs read the source under src/ and check every static icon reference
// against the ids App.vue mounts: CriticalSprites plus every
// iconLibraryComponents loader. Bound values (:name="...") are not checked.

import { mount } from '@vue/test-utils';
import ts from 'typescript';
import { describe, expect, it } from 'vitest';
import { parse as parseSfc } from 'vue/compiler-sfc';
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

const stringValue = (node: ts.Expression | undefined): string | undefined =>
  node && (ts.isStringLiteral(node) || ts.isNoSubstitutionTemplateLiteral(node))
    ? node.text
    : undefined;

/**
 * Sprite ids for object literals with string `collection` and `name`
 * properties, the shape icon maps use (settings-navigation.ts,
 * ssoProviderIcons.ts). Parsed rather than pattern-matched so property order
 * and other properties in between don't hide an entry. Non-literal values,
 * such as zod schemas or shorthand properties, are skipped.
 */
const objectLiteralIconIds = (code: string): string[] => {
  const found: string[] = [];
  const visit = (node: ts.Node): void => {
    if (ts.isObjectLiteralExpression(node)) {
      const props = new Map<string, ts.Expression>();
      for (const prop of node.properties) {
        if (
          ts.isPropertyAssignment(prop) &&
          (ts.isIdentifier(prop.name) || ts.isStringLiteral(prop.name))
        ) {
          props.set(prop.name.text, prop.initializer);
        }
      }
      const collection = stringValue(props.get('collection'));
      const name = stringValue(props.get('name'));
      if (collection !== undefined && name !== undefined) {
        found.push([collection, name].filter(Boolean).join('-'));
      }
    }
    ts.forEachChild(node, visit);
  };
  visit(ts.createSourceFile('source.ts', code, ts.ScriptTarget.Latest));
  return found;
};

/**
 * Icon literals in an SFC's <script> and <script setup> blocks, where icon
 * maps also live. Vue's own SFC parser picks out the blocks, so the spec sees
 * the same script content the compiler does.
 */
const sfcScriptIconIds = (source: string): string[] => {
  const { descriptor } = parseSfc(source);
  return [descriptor.script, descriptor.scriptSetup].flatMap((block) =>
    block ? objectLiteralIconIds(block.content) : []
  );
};

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
    const scriptRefs = Object.values(vueSources).flatMap(sfcScriptIconIds);
    const statCardRefs = Object.values(vueSources).flatMap(statCardIconIds('heroicons'));
    expect(Object.keys(vueSources).length).toBeGreaterThan(100);
    expect(oiconRefs.length).toBeGreaterThan(100);
    expect(literalRefs.length).toBeGreaterThan(10);
    expect(scriptRefs.length).toBeGreaterThan(10);
    expect(statCardRefs.length).toBeGreaterThan(10);
  });

  it('every static <OIcon collection name> in an SFC resolves to a sprite symbol', async () => {
    const ids = await loadSpriteSymbolIds();
    expect(unresolved(vueSources, staticOIconIds, ids)).toEqual([]);
  });

  it('finds icon literals in any property order and skips non-literal values', () => {
    const code = `
      const a = { name: 'reordered', label: 'between', collection: 'heroicons' };
      const b = { collection: 'mdi', name: 'adjacent' };
      const schema = { collection: z.string(), name: z.string() };
      const shorthand = { collection, name };
    `;
    expect(objectLiteralIconIds(code)).toEqual(['heroicons-reordered', 'mdi-adjacent']);
  });

  it('every { collection, name } icon literal in a .ts file resolves to a sprite symbol', async () => {
    const ids = await loadSpriteSymbolIds();
    expect(unresolved(tsSources, objectLiteralIconIds, ids)).toEqual([]);
  });

  it('every { collection, name } icon literal in an SFC script resolves to a sprite symbol', async () => {
    const ids = await loadSpriteSymbolIds();
    expect(unresolved(vueSources, sfcScriptIconIds, ids)).toEqual([]);
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
