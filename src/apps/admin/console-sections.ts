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
  { key: 'customers', labelKey: 'web.colonel.titles.users', icon: 'users', to: '/colonel/customers' },
  { key: 'secrets', labelKey: 'web.colonel.titles.secrets', icon: 'key', to: '/colonel/secrets' },
  { key: 'organizations', labelKey: 'web.colonel.titles.organizations', icon: 'building-office', to: '/colonel/organizations' },
  { key: 'domains', labelKey: 'web.colonel.titles.domains', icon: 'globe-alt', to: '/colonel/domains' },
  { key: 'system', labelKey: 'web.colonel.titles.system', icon: 'cog-6-tooth', to: '/colonel/system' },
  { key: 'bannedIps', labelKey: 'web.colonel.titles.bannedIps', icon: 'no-symbol', to: '/colonel/banned-ips' },
  { key: 'usage', labelKey: 'web.colonel.titles.usage', icon: 'rectangle-group', to: '/colonel/usage' },
  { key: 'sessions', labelKey: 'web.admin.sessions.title', icon: 'finger-print', to: '/colonel/sessions' },
  { key: 'banner', labelKey: 'web.admin.banner.title', icon: 'bell', to: '/colonel/banner' },
  { key: 'queueDlq', labelKey: 'web.admin.queue.nav', icon: 'rectangle-stack', to: '/colonel/queues/dlq' },
  { key: 'domaintoolbox', labelKey: 'web.admin.domaintoolbox.title', icon: 'shield-exclamation', to: '/colonel/domain-toolbox' },
  { key: 'emailTools', labelKey: 'web.admin.emailtools.title', icon: 'envelope', to: '/colonel/email-tools' },
  { key: 'billing', labelKey: 'web.admin.billing.title', icon: 'credit-card', to: '/colonel/billing' },
];
