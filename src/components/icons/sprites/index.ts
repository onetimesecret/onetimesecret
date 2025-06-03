// src/components/icons/sprites/index.ts

import type { Component } from 'vue';

/**
 * Represents a single icon within an icon set
 */
export interface IconSet {
  prefix: string;
  name: string;
  id: string;
}

/**
 * Metadata and component loader for an icon library
 */
export interface IconLibraryMeta {
  name: string;
  component: () => Promise<Component>;
  license: string;
  licenseUrl: string;
  sourceUrl: string;
  usagePrefix: string;
}

/**
 * Dynamic import functions for all icon sprite components
 *
 * Provides lazy loading of sprite components to enable code splitting.
 * Each function returns a Promise that resolves to the component module.
 *
 * @example
 * ```ts
 * const carbonModule = await iconLibraryComponents.carbon();
 * const CarbonSprites = carbonModule.default;
 * ```
 */
export const iconLibraryComponents = {
  carbon: () => import('./CarbonSprites.vue'),
  mdi: () => import('./MdiSprites.vue'),
  fa6: () => import('./FontAwesome6Sprites.vue'),
  heroicons: () => import('./HeroiconsSprites.vue'),
  materialSymbols: () => import('./MaterialSymbolsSprites.vue'),
  tabler: () => import('./TablerSprites.vue'),
  phosphor: () => import('./PhosphorSprites.vue'),
} as const;

/**
 * Complete registry of available icon libraries with metadata and component loaders
 *
 * Combines descriptive metadata (name, license, URLs) with dynamic component loading
 * functions. This provides a single source of truth for all icon library information
 * while enabling efficient code splitting.
 *
 * @example
 * ```ts
 * // Access metadata immediately
 * const carbonInfo = iconLibraries.carbon;
 * console.log(carbonInfo.name); // "Carbon Icons"
 *
 * // Load component on demand
 * const CarbonSprites = (await carbonInfo.component()).default;
 * ```
 */
export const iconLibraries: Record<string, IconLibraryMeta> = {
  /** Material Design Icons - Community-driven icon collection */
  mdi: {
    name: 'Material Design Icons',
    component: iconLibraryComponents.mdi,
    license: 'Apache License 2.0',
    licenseUrl: 'https://pictogrammers.com/docs/general/license/',
    sourceUrl: 'https://pictogrammers.com/',
    usagePrefix: 'mdi',
  },
  /** Carbon Design System - IBM's enterprise design system icons */
  carbon: {
    name: 'Carbon Icons',
    component: iconLibraryComponents.carbon,
    license: 'Apache 2.0',
    licenseUrl: 'https://github.com/carbon-design-system/carbon/blob/main/LICENSE',
    sourceUrl: 'https://github.com/carbon-design-system/carbon',
    usagePrefix: 'carbon',
  },
  /** Font Awesome 6 - Popular icon toolkit with solid style icons */
  fa6: {
    name: 'Font Awesome 6',
    component: iconLibraryComponents.fa6,
    license: 'CC-BY-4.0',
    licenseUrl: 'https://creativecommons.org/licenses/by/4.0/',
    sourceUrl: 'https://fontawesome.com/',
    usagePrefix: 'fa6-solid',
  },
  /** Heroicons - Beautiful hand-crafted SVG icons by Tailwind Labs */
  heroicons: {
    name: 'Heroicons',
    component: iconLibraryComponents.heroicons,
    license: 'MIT',
    licenseUrl: 'https://github.com/tailwindlabs/heroicons/blob/d84ffa5/LICENSE',
    sourceUrl: 'https://github.com/tailwindlabs/heroicons',
    usagePrefix: 'heroicons-outline',
  },
  /** Material Symbols - Google's latest Material Design icon system */
  materialSymbols: {
    name: 'Material Symbols',
    component: iconLibraryComponents.materialSymbols,
    license: 'Apache 2.0',
    licenseUrl: 'https://github.com/material-icons/material-icons/blob/fae3760/LICENSE',
    sourceUrl: 'https://github.com/material-icons/material-icons',
    usagePrefix: 'material-symbols',
  },
  /** Tabler Icons - Free and open source icons for web interfaces */
  tabler: {
    name: 'Tabler',
    component: iconLibraryComponents.tabler,
    license: 'MIT',
    licenseUrl: 'https://github.com/tabler/tabler-icons/blob/main/LICENSE',
    sourceUrl: 'https://github.com/tabler/tabler-icons',
    usagePrefix: 'tabler',
  },
  /** Phosphor Icons - Flexible icon family with multiple weights and styles */
  phosphor: {
    name: 'Phosphor Icons',
    component: iconLibraryComponents.phosphor,
    license: 'MIT',
    licenseUrl: 'https://github.com/phosphor-icons/core/blob/main/LICENSE',
    sourceUrl: 'https://github.com/phosphor-icons/core',
    usagePrefix: 'ph',
  },
};

export const loadIconLibrary = async (libraryKey: keyof typeof iconLibraries) => {
  const library = iconLibraries[libraryKey];
  const module = await library.component();
  return module;
};

export const getIconLibrary = (key: string): IconLibraryMeta | null => iconLibraries[key] || null;
