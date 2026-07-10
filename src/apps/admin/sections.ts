// src/apps/admin/sections.ts

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
 * labelled bands in the rail (see {@link CONSOLE_GROUPS}), ordered most- to
 * least-used with the rare/destructive levers at the bottom, so the nav reads as
 * a structured console map rather than an undifferentiated stack.
 */
export type ConsoleGroup =
  | 'overview'
  | 'identity'
  | 'security'
  | 'platform'
  | 'billing'
  | 'communications';

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
  /**
   * If true, the section is hidden from the left navigation. We use this for tools that
   * aren't production-ready yet, but still want to be able to link to them.
   */
  hide?: boolean;
}

/**
 * Rail bands, in display order. The label is a translated eyebrow rendered above
 * each cluster; the grouping encodes what an operator actually reaches for.
 *
 * `overview` carries an empty `labelKey` on purpose: it holds the single
 * dashboard entry, so per the "a group of one reads as clutter" rule it renders
 * headerless, pinned at the very top.
 */
export const CONSOLE_GROUPS: { key: ConsoleGroup; labelKey: string }[] = [
  { key: 'overview', labelKey: '' },
  { key: 'identity', labelKey: 'web.colonel.nav.groups.identity' },
  { key: 'security', labelKey: 'web.colonel.nav.groups.security' },
  { key: 'platform', labelKey: 'web.colonel.nav.groups.platform' },
  { key: 'billing', labelKey: 'web.colonel.nav.groups.billing' },
  { key: 'communications', labelKey: 'web.colonel.nav.groups.communications' },
];

export const CONSOLE_SECTIONS: ConsoleSection[] = [
  {
    key: 'overview',
    labelKey: 'web.colonel.titles.index',
    icon: 'home',
    group: 'overview',
    to: '/colonel',
  },

  {
    key: 'customers',
    labelKey: 'web.colonel.titles.users',
    icon: 'users',
    group: 'identity',
    to: '/colonel/customers',
  },
  {
    key: 'organizations',
    labelKey: 'web.colonel.titles.organizations',
    icon: 'building-office',
    group: 'identity',
    to: '/colonel/organizations',
  },
  {
    key: 'sessions',
    labelKey: 'web.admin.sessions.title',
    icon: 'finger-print',
    group: 'identity',
    to: '/colonel/sessions',
  },
  {
    key: 'secrets',
    labelKey: 'web.colonel.titles.secrets',
    icon: 'key',
    group: 'identity',
    to: '/colonel/secrets',
  },

  {
    key: 'auditLog',
    labelKey: 'web.admin.audit.title',
    icon: 'document-text',
    group: 'security',
    to: '/colonel/audit',
  },
  {
    key: 'bannedIps',
    labelKey: 'web.colonel.titles.bannedIps',
    icon: 'no-symbol',
    group: 'security',
    to: '/colonel/banned-ips',
  },

  {
    key: 'system',
    labelKey: 'web.colonel.titles.system',
    icon: 'cog-6-tooth',
    group: 'platform',
    to: '/colonel/system',
  },
  {
    key: 'domains',
    labelKey: 'web.colonel.titles.domains',
    icon: 'globe-alt',
    group: 'platform',
    to: '/colonel/domains',
  },
  {
    key: 'domaintoolbox',
    labelKey: 'web.admin.domaintoolbox.title',
    icon: 'shield-exclamation',
    group: 'platform',
    to: '/colonel/domain-toolbox',
  },
  {
    key: 'emailTools',
    labelKey: 'web.admin.emailtools.title',
    icon: 'envelope',
    group: 'platform',
    to: '/colonel/email-tools',
  },

  {
    key: 'billing',
    labelKey: 'web.admin.billing.title',
    icon: 'credit-card',
    group: 'billing',
    to: '/colonel/billing',
  },
  {
    key: 'usage',
    labelKey: 'web.colonel.titles.usage',
    icon: 'rectangle-group',
    group: 'billing',
    to: '/colonel/usage',
  },

  {
    key: 'banner',
    labelKey: 'web.admin.banner.title',
    icon: 'bell',
    group: 'communications',
    to: '/colonel/banner',
  },
];
