// src/components/icons/meta.ts

export interface IconSet {
  prefix: string;
  name: string;
  id: string;
}

export interface IconLibraryMeta {
  name: string;
  component: string;
  license: string;
  licenseUrl: string;
  sourceUrl: string;
  usagePrefix: string;
}

export const iconLibraries: Record<string, IconLibraryMeta> = {
  mdi: {
    name: 'Material Design Icons',
    component: 'MdiSprites',
    license: 'Apache License 2.0',
    licenseUrl: 'https://pictogrammers.com/docs/general/license/',
    sourceUrl: 'https://pictogrammers.com/',
    usagePrefix: 'mdi',
  },
  carbon: {
    name: 'Carbon Icons',
    component: 'CarbonSprites',
    license: 'Apache 2.0',
    licenseUrl: 'https://github.com/carbon-design-system/carbon/blob/main/LICENSE',
    sourceUrl: 'https://github.com/carbon-design-system/carbon',
    usagePrefix: 'carbon',
  },
  fa6: {
    name: 'Font Awesome 6',
    component: 'FontAwesome6Sprites',
    license: 'CC-BY-4.0',
    licenseUrl: 'https://creativecommons.org/licenses/by/4.0/',
    sourceUrl: 'https://fontawesome.com/',
    usagePrefix: 'fa6-solid',
  },
  heroicons: {
    name: 'Heroicons',
    component: 'HeroiconsSprites',
    license: 'MIT',
    licenseUrl: 'https://github.com/tailwindlabs/heroicons/blob/d84ffa5/LICENSE',
    sourceUrl: 'https://github.com/tailwindlabs/heroicons',
    usagePrefix: 'heroicons-outline',
  },
  materialSymbols: {
    name: 'Material Symbols',
    component: 'MaterialSymbolsSprites',
    license: 'Apache 2.0',
    licenseUrl: 'https://github.com/material-icons/material-icons/blob/fae3760/LICENSE',
    sourceUrl: 'https://github.com/material-icons/material-icons',
    usagePrefix: 'material-symbols',
  },
  tabler: {
    name: 'Tabler',
    component: 'TablerSprites',
    license: 'MIT',
    licenseUrl: 'https://github.com/tabler/tabler-icons/blob/main/LICENSE',
    sourceUrl: 'https://github.com/tabler/tabler-icons',
    usagePrefix: 'tabler',
  },
  phosphor: {
    name: 'Phosphor Icons',
    component: 'PhosphorSprites',
    license: 'MIT',
    licenseUrl: 'https://github.com/phosphor-icons/core/blob/main/LICENSE',
    sourceUrl: 'https://github.com/phosphor-icons/core',
    usagePrefix: 'ph',
  },
};
