// src/tests/support/spriteSymbols.ts
//
// OIcon renders <use href="#<collection>-<name>">; a name with no matching
// <symbol> draws nothing and fails silently. These helpers let specs check
// icon references against the sprites App.vue actually mounts.

import { mount } from '@vue/test-utils';
import CriticalSprites from '@/shared/components/icons/sprites/CriticalSprites.vue';
import { iconLibraryComponents } from '@/shared/components/icons/sprites';

/** Every <symbol id> from CriticalSprites plus each lazily loaded library. */
export const loadSpriteSymbolIds = async (): Promise<Set<string>> => {
  const components = [CriticalSprites];
  for (const loader of Object.values(iconLibraryComponents)) {
    components.push((await loader()).default);
  }

  const ids = new Set<string>();
  for (const component of components) {
    for (const symbol of mount(component).findAll('symbol')) {
      ids.add(symbol.attributes('id') ?? '');
    }
  }
  return ids;
};

/**
 * Sprite ids for each <OIcon> in an SFC source that sets both `collection`
 * and `name` as static attributes. Bound (`:name`) values are skipped.
 */
export const staticOIconIds = (source: string): string[] =>
  [...source.matchAll(/<OIcon\b([^>]*?)\/?>/gs)].flatMap(([, attrs]) => {
    const collection = attrs.match(/(?<![:\w-])collection="([^"]*)"/)?.[1];
    const name = attrs.match(/(?<![:\w-])name="([^"]*)"/)?.[1];
    return collection !== undefined && name !== undefined
      ? [[collection, name].filter(Boolean).join('-')]
      : [];
  });
