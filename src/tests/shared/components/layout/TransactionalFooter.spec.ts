// src/tests/shared/components/layout/TransactionalFooter.spec.ts
//
// Tests for the footer's bottom bar layout invariant.
//
// The bar is a two-ended flex row: the version/attribution cell on one end,
// the toggle cluster (region, theme, language, feedback) on the other, held
// apart by `justify-between`. It only reads as a bar when both ends are
// occupied — and both left-hand occupants are conditional:
//
//   - the version is authenticated-only (fingerprinting / CVE matching), and
//   - `displayPoweredBy` is an opt-in that App.vue merges in as `false` for
//     every route.
//
// useFooterAnchor resolves this: the existing attribution falls back in as a
// brand anchor, EXCEPT on a custom domain, where it names the install (see
// brand_product_name) and would stamp operator branding on a tenant's
// white-labelled page. That leaves exactly one genuinely empty cell —
// anonymous + custom domain — where the bar must center instead of stranding
// the cluster against a bare edge.

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, afterEach } from 'vitest';
import { createTestingPinia } from '@pinia/testing';
import TransactionalFooter from '@/shared/components/layout/TransactionalFooter.vue';
import { createTestI18n } from '@tests/setup';

const i18n = createTestI18n();

const stubs = {
  FooterLinks: true,
  JurisdictionToggle: true,
  LanguageToggle: true,
  ThemeToggle: true,
  FeedbackToggle: true,
};

interface BarState {
  authenticated?: boolean;
  domain_strategy?: string;
  show_version?: boolean;
}

const mountComponent = (state: BarState = {}, props: Record<string, unknown> = {}) =>
  mount(TransactionalFooter, {
    // App.vue merges an explicit displayPoweredBy: false into every route's
    // layoutProps, which beats this component's own withDefaults(true). Pass
    // it explicitly so these cases exercise the real path.
    props: { displayPoweredBy: false, ...props },
    global: {
      plugins: [
        i18n,
        createTestingPinia({
          createSpy: vi.fn,
          stubActions: false,
          initialState: {
            bootstrap: {
              authenticated: state.authenticated ?? false,
              domain_strategy: state.domain_strategy ?? 'canonical',
              ot_version: '1.0.0',
              ot_version_long: '1.0.0-test',
              brand_product_name: null,
              regions_enabled: false,
              i18n_enabled: false,
              authentication: { enabled: true },
              ui: { show_version: state.show_version ?? true },
            },
          },
        }),
      ],
      stubs,
    },
  });

// The bar is the element carrying the flex-col-reverse/md:flex-row classes.
const bar = (wrapper: VueWrapper) => wrapper.find('.flex-col-reverse');

describe('TransactionalFooter — bottom bar anchor', () => {
  let wrapper: VueWrapper;

  afterEach(() => {
    if (wrapper) wrapper.unmount();
  });

  describe('when the left cell is occupied', () => {
    it('keeps justify-between for an anonymous visitor (attribution anchors)', () => {
      wrapper = mountComponent({ authenticated: false });

      expect(bar(wrapper).classes()).toContain('justify-between');
      expect(bar(wrapper).classes()).not.toContain('justify-center');
    });

    it('keeps justify-between for an authenticated visitor (version shows)', () => {
      wrapper = mountComponent({ authenticated: true });

      expect(bar(wrapper).classes()).toContain('justify-between');
    });

    it('keeps justify-between on a custom domain that opts into attribution', () => {
      // public.routes.ts sets displayPoweredBy: true for the custom-domain
      // homepage deliberately; only the unrequested fallback is suppressed.
      wrapper = mountComponent(
        { authenticated: false, domain_strategy: 'custom' },
        { displayPoweredBy: true }
      );

      expect(bar(wrapper).classes()).toContain('justify-between');
    });
  });

  describe('when the left cell has no occupant', () => {
    it('centers the toggle cluster for an anonymous custom-domain visitor', () => {
      wrapper = mountComponent({ authenticated: false, domain_strategy: 'custom' });

      expect(bar(wrapper).classes()).toContain('justify-center');
      expect(bar(wrapper).classes()).not.toContain('justify-between');
    });

    it('does not render an empty left cell (it would claim a row on mobile)', () => {
      wrapper = mountComponent({ authenticated: false, domain_strategy: 'custom' });

      // The left cell is the only element with md:justify-start.
      expect(wrapper.find('.md\\:justify-start').exists()).toBe(false);
    });

    it('still renders the left cell whenever it has content', () => {
      wrapper = mountComponent({ authenticated: false });

      expect(wrapper.find('.md\\:justify-start').exists()).toBe(true);
    });
  });

  describe('footer-links border binding still composes', () => {
    it('merges the top border with the justification class', () => {
      wrapper = mount(TransactionalFooter, {
        props: { displayPoweredBy: false, displayFooterLinks: true },
        global: {
          plugins: [
            i18n,
            createTestingPinia({
              createSpy: vi.fn,
              stubActions: false,
              initialState: {
                bootstrap: {
                  authenticated: false,
                  domain_strategy: 'canonical',
                  ot_version: '1.0.0',
                  ot_version_long: '1.0.0-test',
                  authentication: { enabled: true },
                  ui: {
                    show_version: true,
                    footer_links: { enabled: true, groups: [] },
                  },
                },
              },
            }),
          ],
          stubs,
        },
      });

      const classes = bar(wrapper).classes();
      expect(classes).toContain('justify-between');
      expect(classes).toContain('border-t');
      // Exactly one justify-* utility — no colliding leftovers.
      expect(classes.filter((c) => c.startsWith('justify-'))).toEqual(['justify-between']);
    });
  });
});
