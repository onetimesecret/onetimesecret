// src/tests/apps/workspace/components/layout/WorkspaceFooter.spec.ts
//
// Tests for isExternalUrl helper and WorkspaceFooter footer links computed property.

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { mount, VueWrapper } from '@vue/test-utils';
import { createTestingPinia } from '@pinia/testing';
import { ref } from 'vue';
import { isExternalUrl } from '@/utils/url';

// ─────────────────────────────────────────────────────────────────────────────
// Unit tests for isExternalUrl helper (imported from @/utils/url)
// ─────────────────────────────────────────────────────────────────────────────

describe('isExternalUrl helper', () => {
  describe('external URLs (https://)', () => {
    it('detects https:// URL as external', () => {
      expect(isExternalUrl('https://docs.example.com/api')).toBe(true);
    });

    it('detects https:// URL with port as external', () => {
      expect(isExternalUrl('https://docs.example.com:8443/api')).toBe(true);
    });

    it('detects https:// URL with path as external', () => {
      expect(isExternalUrl('https://support.onetimesecret.com/en/rest-api/')).toBe(true);
    });
  });

  describe('external URLs (http://)', () => {
    it('detects http:// URL as external', () => {
      expect(isExternalUrl('http://example.com')).toBe(true);
    });

    it('detects HTTP:// (uppercase) URL as external', () => {
      expect(isExternalUrl('HTTP://example.com')).toBe(true);
    });

    it('detects HtTpS:// (mixed case) URL as external', () => {
      expect(isExternalUrl('HtTpS://example.com')).toBe(true);
    });
  });

  describe('internal URLs (relative paths)', () => {
    it('detects relative path as internal', () => {
      expect(isExternalUrl('/feedback')).toBe(false);
    });

    it('detects root path as internal', () => {
      expect(isExternalUrl('/')).toBe(false);
    });

    it('detects nested relative path as internal', () => {
      expect(isExternalUrl('/account/settings')).toBe(false);
    });

    it('detects relative path without leading slash as internal', () => {
      expect(isExternalUrl('feedback')).toBe(false);
    });
  });

  describe('edge cases', () => {
    it('handles empty string as internal', () => {
      expect(isExternalUrl('')).toBe(false);
    });

    it('handles protocol-relative URL as internal (no scheme)', () => {
      // Protocol-relative URLs like //example.com don't match https?://
      expect(isExternalUrl('//example.com/path')).toBe(false);
    });

    it('handles ftp:// URL as internal (not http/https)', () => {
      expect(isExternalUrl('ftp://example.com')).toBe(false);
    });

    it('handles mailto: URL as internal (not http/https)', () => {
      expect(isExternalUrl('mailto:support@example.com')).toBe(false);
    });

    it('handles URL with https in path but not scheme as internal', () => {
      expect(isExternalUrl('/docs/https-guide')).toBe(false);
    });
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Integration tests for footerLinks computed property
// ─────────────────────────────────────────────────────────────────────────────

// Mock vue-i18n
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key: string) => key,
    locale: ref('en'),
  }),
}));

// Mock vue-router
vi.mock('vue-router', () => ({
  useRoute: () => ({
    path: '/dashboard',
  }),
}));

// Mock OIcon component
vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" />',
    props: ['collection', 'name'],
  },
}));

// Mock stores used by component
vi.mock('@/shared/stores', () => ({
  useDomainsStore: () => ({
    count: 0,
  }),
  useReceiptListStore: () => ({
    count: 0,
  }),
}));

import WorkspaceFooter from '@/apps/workspace/components/layout/WorkspaceFooter.vue';

describe('WorkspaceFooter footerLinks', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    if (wrapper) {
      wrapper.unmount();
    }
  });

  const mountComponent = (
    bootstrapState: Record<string, unknown> = {},
    props: Record<string, unknown> = {}
  ) => mount(WorkspaceFooter, {
      props,
      global: {
        plugins: [
          createTestingPinia({
            createSpy: vi.fn,
            stubActions: false,
            initialState: {
              bootstrap: {
                ot_version: '1.0.0',
                ot_version_long: '1.0.0-test',
                domains_enabled: false,
                support_host: 'support.onetimesecret.com',
                authenticated: true,
                ui: bootstrapState.ui ?? {
                  footer_links: {
                    enabled: true,
                    groups: [],
                  },
                },
                ...bootstrapState,
              },
            },
          }),
        ],
        stubs: {
          RouterLink: true,
        },
      },
    });

  describe('default links (no workspace_links configured)', () => {
    it('renders default links when no workspace_links set', async () => {
      wrapper = mountComponent();

      const links = wrapper.findAll('a');
      // Should have at least the footer links (API Docs, Branding Guide, Feedback)
      expect(links.length).toBeGreaterThanOrEqual(3);
    });
  });

  describe('configured workspace_links overrides defaults', () => {
    it('uses workspace_links when configured', async () => {
      wrapper = mountComponent({
        ui: {
          workspace_links: {
            enabled: true,
            links: [
              {
                text: 'Custom Link 1',
                url: '/custom-1',
              },
              {
                text: 'Custom Link 2',
                url: 'https://custom.example.com',
              },
            ],
          },
        },
      });

      const links = wrapper.findAll('a');
      const customLink1 = links.find(link => link.text() === 'Custom Link 1');
      const customLink2 = links.find(link => link.text() === 'Custom Link 2');

      expect(customLink1).toBeDefined();
      expect(customLink2).toBeDefined();
    });

    it('uses default links when workspace_links.links is empty array', async () => {
      wrapper = mountComponent({
        ui: {
          workspace_links: {
            enabled: true,
            links: [],
          },
        },
      });

      // Should fall back to default links (API Docs, Branding Guide, Feedback)
      const links = wrapper.findAll('a');
      // Default links use i18n keys as labels in tests
      expect(links.length).toBeGreaterThanOrEqual(3);
    });

    it('uses default links when workspace_links not configured', async () => {
      wrapper = mountComponent({
        ui: {
          footer_links: {
            enabled: true,
            groups: [],
          },
        },
      });

      // Should fall back to default links since no workspace_links
      const links = wrapper.findAll('a');
      expect(links.length).toBeGreaterThanOrEqual(3);
    });
  });

  describe('workspace_links enabled toggle', () => {
    it('hides all footer links when workspace_links.enabled is false', async () => {
      wrapper = mountComponent({
        ui: {
          workspace_links: {
            enabled: false,
            links: [
              {
                text: 'Should Not Appear',
                url: '/hidden',
              },
            ],
          },
        },
      });

      const links = wrapper.findAll('a');
      const hiddenLink = links.find(link => link.text() === 'Should Not Appear');
      expect(hiddenLink).toBeUndefined();
      // Also no default links should render
      const feedbackLink = links.find(link => link.text() === 'web.TITLES.feedback');
      expect(feedbackLink).toBeUndefined();
    });

    it('shows default links when enabled is true but no links configured', async () => {
      wrapper = mountComponent({
        ui: {
          workspace_links: {
            enabled: true,
          },
        },
      });

      const links = wrapper.findAll('a');
      expect(links.length).toBeGreaterThanOrEqual(3);
    });
  });

  describe('links with i18n_key', () => {
    it('uses i18n_key for label when provided', async () => {
      wrapper = mountComponent({
        ui: {
          workspace_links: {
            enabled: true,
            links: [
              {
                text: 'Fallback Text',
                i18n_key: 'web.custom.label',
                url: '/custom',
              },
            ],
          },
        },
      });

      const links = wrapper.findAll('a');
      // With mock t() returning the key, the label should be the i18n key
      const customLink = links.find(link => link.text() === 'web.custom.label');
      expect(customLink).toBeDefined();
    });

    it('falls back to text when i18n_key not provided', async () => {
      wrapper = mountComponent({
        ui: {
          workspace_links: {
            enabled: true,
            links: [
              {
                text: 'Plain Text Label',
                url: '/plain',
              },
            ],
          },
        },
      });

      const links = wrapper.findAll('a');
      const plainLink = links.find(link => link.text() === 'Plain Text Label');
      expect(plainLink).toBeDefined();
    });
  });

  describe('workspace_links filtering', () => {
    it('filters out links with empty URL', async () => {
      wrapper = mountComponent({
        ui: {
          workspace_links: {
            enabled: true,
            links: [
              {
                text: 'Valid Link',
                url: '/valid',
              },
              {
                text: 'Empty URL',
                url: '',
              },
              {
                text: 'Whitespace URL',
                url: '   ',
              },
            ],
          },
        },
      });

      const links = wrapper.findAll('a');
      const validLink = links.find(link => link.text() === 'Valid Link');
      const emptyLink = links.find(link => link.text() === 'Empty URL');
      const whitespaceLink = links.find(link => link.text() === 'Whitespace URL');

      expect(validLink).toBeDefined();
      expect(emptyLink).toBeUndefined();
      expect(whitespaceLink).toBeUndefined();
    });
  });

  describe('version display respects showVersionConfig and authentication', () => {
    it('shows version when displayVersion=true and ui.show_version=true', async () => {
      wrapper = mountComponent({
        ui: {
          show_version: true,
        },
      });

      const versionLink = wrapper.find('a[href*="github.com/onetimesecret/onetimesecret/releases"]');
      expect(versionLink.exists()).toBe(true);
      expect(versionLink.text()).toContain('v1.0.0');
    });

    it('shows version when displayVersion=true and ui.show_version is undefined (default)', async () => {
      wrapper = mountComponent({
        ui: {},
      });

      const versionLink = wrapper.find('a[href*="github.com/onetimesecret/onetimesecret/releases"]');
      expect(versionLink.exists()).toBe(true);
    });

    it('hides version when ui.show_version=false even with displayVersion=true', async () => {
      wrapper = mountComponent({
        ui: {
          show_version: false,
        },
      });

      const versionLink = wrapper.find('a[href*="github.com/onetimesecret/onetimesecret/releases"]');
      expect(versionLink.exists()).toBe(false);
    });

    it('hides version when displayVersion prop is false', async () => {
      wrapper = mount(WorkspaceFooter, {
        props: {
          displayVersion: false,
        },
        global: {
          plugins: [
            createTestingPinia({
              createSpy: vi.fn,
              stubActions: false,
              initialState: {
                bootstrap: {
                  ot_version: '1.0.0',
                  ot_version_long: '1.0.0-test',
                  domains_enabled: false,
                  support_host: 'support.onetimesecret.com',
                  authenticated: true,
                  ui: {
                    show_version: true,
                  },
                },
              },
            }),
          ],
          stubs: {
            RouterLink: true,
          },
        },
      });

      const versionLink = wrapper.find('a[href*="github.com/onetimesecret/onetimesecret/releases"]');
      expect(versionLink.exists()).toBe(false);
    });

    it('requires BOTH displayVersion AND showVersionConfig to show version', async () => {
      // Case: displayVersion=true, showVersionConfig=false -> hidden
      wrapper = mountComponent({
        ui: {
          show_version: false,
        },
      });

      let versionLink = wrapper.find('a[href*="github.com/onetimesecret/onetimesecret/releases"]');
      expect(versionLink.exists()).toBe(false);
      wrapper.unmount();

      // Case: displayVersion=default(true), showVersionConfig=true -> shown
      wrapper = mountComponent({
        ui: {
          show_version: true,
        },
      });

      versionLink = wrapper.find('a[href*="github.com/onetimesecret/onetimesecret/releases"]');
      expect(versionLink.exists()).toBe(true);
    });

    it('hides version for unauthenticated sessions even when show_version=true', async () => {
      wrapper = mountComponent({
        authenticated: false,
        ui: {
          show_version: true,
        },
      });

      const versionLink = wrapper.find('a[href*="github.com/onetimesecret/onetimesecret/releases"]');
      expect(versionLink.exists()).toBe(false);
    });
  });

  // The version/attribution cell is one half of a two-ended bottom bar. With
  // the version now authenticated-only and `displayPoweredBy` defaulting off
  // across App.vue and most route metas, that cell rendered empty on nearly
  // every anonymous surface and the bar went lop-sided. useFooterAnchor falls
  // the existing attribution back in as a brand anchor so the cell is never
  // empty — except on custom domains, where the attribution names the INSTALL
  // (brand_product_name), not the tenant, and must not be forced onto a
  // white-labelled page.
  describe('brand anchor keeps the version/attribution cell occupied', () => {
    // The cell is the wrapping div of the version span; assert on the
    // attribution link (t() is mocked to echo the key).
    const attributionLink = (w: VueWrapper) =>
      w.findAll('a').find((link) => link.text() === 'web.branding.powered_by_onetime_secret');

    // WorkspaceFooter's own withDefaults sets displayPoweredBy: true, but
    // App.vue merges an explicit `false` into every route's layoutProps, so
    // `false` is what this component really receives in the app. These cases
    // pass it explicitly to exercise the real path.
    it('anchors with the attribution for an anonymous visitor', async () => {
      wrapper = mountComponent(
        { authenticated: false, ui: { show_version: true } },
        { displayPoweredBy: false }
      );

      expect(
        wrapper.find('a[href*="github.com/onetimesecret/onetimesecret/releases"]').exists()
      ).toBe(false);
      // Left cell is NOT empty: attribution stands in for the hidden version.
      expect(attributionLink(wrapper)).toBeDefined();
    });

    it('anchors when the deployment disabled show_version', async () => {
      wrapper = mountComponent(
        { authenticated: true, ui: { show_version: false } },
        { displayPoweredBy: false }
      );

      expect(attributionLink(wrapper)).toBeDefined();
    });

    it('drops the fallback attribution once the version occupies the cell', async () => {
      wrapper = mountComponent(
        { authenticated: true, ui: { show_version: true } },
        { displayPoweredBy: false }
      );

      expect(
        wrapper.find('a[href*="github.com/onetimesecret/onetimesecret/releases"]').exists()
      ).toBe(true);
      // displayPoweredBy is unset here, so the anchor stands down.
      expect(attributionLink(wrapper)).toBeUndefined();
    });

    it('withholds the fallback anchor on a custom domain (white-label guard)', async () => {
      wrapper = mountComponent(
        { authenticated: false, domain_strategy: 'custom', ui: { show_version: true } },
        { displayPoweredBy: false }
      );

      expect(attributionLink(wrapper)).toBeUndefined();
    });

    it('omits the version/attribution row entirely when nothing occupies it', async () => {
      // Anonymous + custom domain is the one case with no occupant. Note
      // WorkspaceFooter's bottom block is already a centered column with no
      // toggle cluster, so there is no `justify-between` to swap here (unlike
      // TransactionalFooter / ManagementFooter) — the only observable effect
      // is that the empty row stops claiming a `gap-2` slot.
      wrapper = mountComponent(
        { authenticated: false, domain_strategy: 'custom', ui: { show_version: true } },
        { displayPoweredBy: false }
      );

      expect(wrapper.find('.flex.items-center.gap-x-3').exists()).toBe(false);
    });

    it('renders the version/attribution row whenever it has an occupant', async () => {
      wrapper = mountComponent(
        { authenticated: false, ui: { show_version: true } },
        { displayPoweredBy: false }
      );

      expect(wrapper.find('.flex.items-center.gap-x-3').exists()).toBe(true);
    });

    it('still renders the attribution on a custom domain when asked explicitly', async () => {
      // Custom-domain route overrides (public.routes.ts, receipt.ts) opt in
      // deliberately; only the unrequested fallback is suppressed.
      wrapper = mountComponent(
        { authenticated: false, domain_strategy: 'custom', ui: { show_version: true } },
        { displayPoweredBy: true }
      );

      expect(attributionLink(wrapper)).toBeDefined();
    });
  });
});
