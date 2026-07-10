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
 * verified to exist in HeroiconsSprites.vue. `group` clusters the flat list into
 * four labelled bands in the rail (see {@link CONSOLE_GROUPS}) so the 14-item nav
 * reads as a structured console map rather than an undifferentiated stack.
 */
export type ConsoleGroup = 'monitor' | 'accounts' | 'secrets' | 'controls';

export interface ConsoleSection {
  key: string;
  labelKey: string;
  icon: string;
  /** Rail band this section belongs to. */
  group: ConsoleGroup;
  /**
   * Route path for the section. Optional only for the historical placeholder
   * affordance in AdminLayout/AdminOverview; every current entry sets it.
   */
  to?: string;
}

/**
 * Rail bands, in display order. The label is a translated eyebrow rendered above
 * each cluster; the grouping encodes what an operator actually reaches for —
 * what's happening (monitor), who's on the system (accounts), what they share
 * (secrets & domains), and the levers to pull (controls).
 */
export const CONSOLE_GROUPS: { key: ConsoleGroup; labelKey: string }[] = [
  { key: 'monitor', labelKey: 'web.colonel.nav.groups.monitor' },
  { key: 'accounts', labelKey: 'web.colonel.nav.groups.accounts' },
  { key: 'secrets', labelKey: 'web.colonel.nav.groups.secrets' },
  { key: 'controls', labelKey: 'web.colonel.nav.groups.controls' },
];

export const CONSOLE_SECTIONS: ConsoleSection[] = [
  { key: 'overview', labelKey: 'web.colonel.titles.index', icon: 'home', group: 'monitor', to: '/colonel' },
  { key: 'sessions', labelKey: 'web.admin.sessions.title', icon: 'finger-print', group: 'monitor', to: '/colonel/sessions' },
  { key: 'auditLog', labelKey: 'web.admin.audit.title', icon: 'document-text', group: 'monitor', to: '/colonel/audit' },
  { key: 'usage', labelKey: 'web.colonel.titles.usage', icon: 'rectangle-group', group: 'monitor', to: '/colonel/usage' },

  { key: 'customers', labelKey: 'web.colonel.titles.users', icon: 'users', group: 'accounts', to: '/colonel/customers' },
  { key: 'organizations', labelKey: 'web.colonel.titles.organizations', icon: 'building-office', group: 'accounts', to: '/colonel/organizations' },
  { key: 'billing', labelKey: 'web.admin.billing.title', icon: 'credit-card', group: 'accounts', to: '/colonel/billing' },

  { key: 'secrets', labelKey: 'web.colonel.titles.secrets', icon: 'key', group: 'secrets', to: '/colonel/secrets' },
  { key: 'domains', labelKey: 'web.colonel.titles.domains', icon: 'globe-alt', group: 'secrets', to: '/colonel/domains' },
  { key: 'domaintoolbox', labelKey: 'web.admin.domaintoolbox.title', icon: 'shield-exclamation', group: 'secrets', to: '/colonel/domain-toolbox' },
  { key: 'emailTools', labelKey: 'web.admin.emailtools.title', icon: 'envelope', group: 'secrets', to: '/colonel/email-tools' },

  { key: 'system', labelKey: 'web.colonel.titles.system', icon: 'cog-6-tooth', group: 'controls', to: '/colonel/system' },
  { key: 'bannedIps', labelKey: 'web.colonel.titles.bannedIps', icon: 'no-symbol', group: 'controls', to: '/colonel/banned-ips' },
  { key: 'banner', labelKey: 'web.admin.banner.title', icon: 'bell', group: 'controls', to: '/colonel/banner' },
];
