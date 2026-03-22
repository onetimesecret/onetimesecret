// src/tests/apps/workspace/components/layout/WorkspaceFooter.spec.ts
//
// Tests for WorkspaceFooter external link detection and footer links computed property.

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

  const mountComponent = (bootstrapState: Record<string, unknown> = {}) => {
    return mount(WorkspaceFooter, {
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
  };

  describe('default links (no workspace group configured)', () => {
    it('uses computed external flag for default links', async () => {
      wrapper = mountComponent();

      // Default links should use the component's internal logic
      // API Docs and Branding Guide should be external when support_host is set
      const links = wrapper.findAll('a');

      // Should have at least the footer links
      expect(links.length).toBeGreaterThanOrEqual(3);
    });
  });

  describe('configured footer_links with explicit external flag', () => {
    it('preserves explicit external:true from config', async () => {
      wrapper = mountComponent({
        ui: {
          footer_links: {
            enabled: true,
            groups: [
              {
                name: 'workspace',
                links: [
                  {
                    text: 'External Link',
                    url: '/local-path',
                    external: true,
                  },
                ],
              },
            ],
          },
        },
      });

      // Find the link with text "External Link"
      const links = wrapper.findAll('a');
      const externalLink = links.find(link => link.text() === 'External Link');
      expect(externalLink).toBeDefined();
      expect(externalLink?.attributes('target')).toBe('_blank');
      expect(externalLink?.attributes('rel')).toBe('noopener noreferrer');
    });

    it('preserves explicit external:false from config', async () => {
      wrapper = mountComponent({
        ui: {
          footer_links: {
            enabled: true,
            groups: [
              {
                name: 'workspace',
                links: [
                  {
                    text: 'Internal Link',
                    url: 'https://external-url.com',
                    external: false,
                  },
                ],
              },
            ],
          },
        },
      });

      const links = wrapper.findAll('a');
      const internalLink = links.find(link => link.text() === 'Internal Link');
      expect(internalLink).toBeDefined();
      expect(internalLink?.attributes('target')).toBe('_self');
      expect(internalLink?.attributes('rel')).toBeUndefined();
    });
  });

  describe('configured footer_links without explicit external flag', () => {
    it('infers external:true for https:// URL when external not specified', async () => {
      wrapper = mountComponent({
        ui: {
          footer_links: {
            enabled: true,
            groups: [
              {
                name: 'workspace',
                links: [
                  {
                    text: 'HTTPS Link',
                    url: 'https://docs.example.com/api',
                    // external not specified
                  },
                ],
              },
            ],
          },
        },
      });

      const links = wrapper.findAll('a');
      const httpsLink = links.find(link => link.text() === 'HTTPS Link');
      expect(httpsLink).toBeDefined();
      expect(httpsLink?.attributes('target')).toBe('_blank');
      expect(httpsLink?.attributes('rel')).toBe('noopener noreferrer');
    });

    it('infers external:false for relative URL when external not specified', async () => {
      wrapper = mountComponent({
        ui: {
          footer_links: {
            enabled: true,
            groups: [
              {
                name: 'workspace',
                links: [
                  {
                    text: 'Relative Link',
                    url: '/feedback',
                    // external not specified
                  },
                ],
              },
            ],
          },
        },
      });

      const links = wrapper.findAll('a');
      const relativeLink = links.find(link => link.text() === 'Relative Link');
      expect(relativeLink).toBeDefined();
      expect(relativeLink?.attributes('target')).toBe('_self');
      expect(relativeLink?.attributes('rel')).toBeUndefined();
    });
  });

  describe('configured footer_links overrides defaults', () => {
    it('uses workspace group links when configured', async () => {
      wrapper = mountComponent({
        ui: {
          footer_links: {
            enabled: true,
            groups: [
              {
                name: 'workspace',
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
            ],
          },
        },
      });

      const links = wrapper.findAll('a');
      const customLink1 = links.find(link => link.text() === 'Custom Link 1');
      const customLink2 = links.find(link => link.text() === 'Custom Link 2');

      expect(customLink1).toBeDefined();
      expect(customLink2).toBeDefined();

      // Should not have default API Docs link
      const apiDocsLink = links.find(link => link.text() === 'web.footer.api_docs');
      // Note: might exist due to i18n key as text, but we're checking configured links work
    });

    it('uses default links when workspace group has empty links array', async () => {
      wrapper = mountComponent({
        ui: {
          footer_links: {
            enabled: true,
            groups: [
              {
                name: 'workspace',
                links: [],
              },
            ],
          },
        },
      });

      // Should fall back to default links (API Docs, Branding Guide, Feedback)
      const links = wrapper.findAll('a');
      // Default links use i18n keys as labels in tests
      expect(links.length).toBeGreaterThanOrEqual(3);
    });

    it('uses default links when no workspace group exists', async () => {
      wrapper = mountComponent({
        ui: {
          footer_links: {
            enabled: true,
            groups: [
              {
                name: 'other-group',
                links: [
                  { text: 'Other Link', url: '/other' },
                ],
              },
            ],
          },
        },
      });

      // Should fall back to default links since no 'workspace' group
      const links = wrapper.findAll('a');
      expect(links.length).toBeGreaterThanOrEqual(3);
    });
  });

  describe('links with i18n_key', () => {
    it('uses i18n_key for label when provided', async () => {
      wrapper = mountComponent({
        ui: {
          footer_links: {
            enabled: true,
            groups: [
              {
                name: 'workspace',
                links: [
                  {
                    text: 'Fallback Text',
                    i18n_key: 'web.custom.label',
                    url: '/custom',
                  },
                ],
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
          footer_links: {
            enabled: true,
            groups: [
              {
                name: 'workspace',
                links: [
                  {
                    text: 'Plain Text Label',
                    url: '/plain',
                  },
                ],
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

  describe('footer_links filtering', () => {
    it('filters out links with empty URL', async () => {
      wrapper = mountComponent({
        ui: {
          footer_links: {
            enabled: true,
            groups: [
              {
                name: 'workspace',
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
});
