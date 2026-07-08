// src/apps/admin/console-sections.ts

/**
 * The admin console's navigable map.
 *
 * Every section is live: each entry routes to a real screen (see
 * docs/specs/colonel-ui/). Keeping the map in one place means the sidebar and
 * the overview dashboard never drift.
 *
 * `labelKey` mixes legacy `web.colonel.*` keys (Phase-0 parity screens) with
 * `web.admin.*` keys (Phase-3 screens). `icon` is a heroicons sprite name
 * verified to exist in HeroiconsSprites.vue.
 */
export interface ConsoleSection {
  key: string;
  labelKey: string;
  icon: string;
  /**
   * Route path for the section. Optional only for the historical placeholder
   * affordance in AdminLayout/AdminOverview; every current entry sets it.
   */
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
  { key: 'auditLog', labelKey: 'web.admin.audit.title', icon: 'document-text', to: '/colonel/audit' },
  { key: 'banner', labelKey: 'web.admin.banner.title', icon: 'bell', to: '/colonel/banner' },
  { key: 'domaintoolbox', labelKey: 'web.admin.domaintoolbox.title', icon: 'shield-exclamation', to: '/colonel/domain-toolbox' },
  { key: 'emailTools', labelKey: 'web.admin.emailtools.title', icon: 'envelope', to: '/colonel/email-tools' },
  { key: 'billing', labelKey: 'web.admin.billing.title', icon: 'credit-card', to: '/colonel/billing' },
];
