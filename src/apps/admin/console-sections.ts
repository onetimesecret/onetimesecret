// src/apps/admin/console-sections.ts

/**
 * The admin console's navigable map.
 *
 * Phase 0 ships the Overview screen live; the remaining sections are
 * placeholders that later phases turn into real routes (see
 * docs/specs/colonel-ui/). Keeping the map in one place means the sidebar and
 * the overview dashboard never drift.
 *
 * `labelKey` reuses existing `web.colonel.*` i18n keys, so the Phase-0
 * skeleton needs no new locale content. `icon` is a heroicons sprite name
 * verified to exist in HeroiconsSprites.vue.
 */
export interface ConsoleSection {
  key: string;
  labelKey: string;
  icon: string;
  /** Route path once the section is live; omitted while it is a placeholder. */
  to?: string;
}

export const CONSOLE_SECTIONS: ConsoleSection[] = [
  { key: 'overview', labelKey: 'web.colonel.titles.index', icon: 'home', to: '/colonel' },
  { key: 'customers', labelKey: 'web.colonel.titles.users', icon: 'users' },
  { key: 'secrets', labelKey: 'web.colonel.titles.secrets', icon: 'key' },
  { key: 'organizations', labelKey: 'web.colonel.titles.organizations', icon: 'building-office' },
  { key: 'domains', labelKey: 'web.colonel.titles.domains', icon: 'globe-alt' },
  { key: 'system', labelKey: 'web.colonel.titles.system', icon: 'cog-6-tooth' },
  { key: 'bannedIps', labelKey: 'web.colonel.titles.bannedIps', icon: 'no-symbol' },
  { key: 'usage', labelKey: 'web.colonel.titles.usage', icon: 'rectangle-group' },
];
