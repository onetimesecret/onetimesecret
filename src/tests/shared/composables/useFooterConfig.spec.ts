// src/tests/shared/composables/useFooterConfig.spec.ts
//
// Tests for useFooterConfig composable behavior:
// - showVersionConfig returns true when ui.show_version is true
// - showVersionConfig returns true when ui.show_version is undefined (default)
// - showVersionConfig returns false when ui.show_version is false
// - useFooterAnchor keeps the footer's two-ended bottom bar occupied

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { ref } from 'vue';
import { setActivePinia, createPinia } from 'pinia';
import { useFooterConfig, useFooterAnchor } from '@/shared/composables/useFooterConfig';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';

describe('useFooterConfig', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  describe('showVersionConfig', () => {
    it('returns true when ui.show_version is true', () => {
      const bootstrapStore = useBootstrapStore();
      bootstrapStore.$patch({
        ui: { show_version: true },
      });

      const { showVersionConfig } = useFooterConfig();

      expect(showVersionConfig.value).toBe(true);
    });

    it('returns true when ui.show_version is undefined (default behavior)', () => {
      const bootstrapStore = useBootstrapStore();
      bootstrapStore.$patch({
        ui: {},
      });

      const { showVersionConfig } = useFooterConfig();

      expect(showVersionConfig.value).toBe(true);
    });

    it('returns true when ui is undefined', () => {
      // Default store state has ui as empty object or undefined
      const { showVersionConfig } = useFooterConfig();

      expect(showVersionConfig.value).toBe(true);
    });

    it('returns false when ui.show_version is false', () => {
      const bootstrapStore = useBootstrapStore();
      bootstrapStore.$patch({
        ui: { show_version: false },
      });

      const { showVersionConfig } = useFooterConfig();

      expect(showVersionConfig.value).toBe(false);
    });

    it('is reactive to store changes', () => {
      const bootstrapStore = useBootstrapStore();
      bootstrapStore.$patch({
        ui: { show_version: true },
      });

      const { showVersionConfig } = useFooterConfig();
      expect(showVersionConfig.value).toBe(true);

      // Change store value
      bootstrapStore.$patch({
        ui: { show_version: false },
      });

      expect(showVersionConfig.value).toBe(false);
    });

    it('preserves other ui properties when checking show_version', () => {
      const bootstrapStore = useBootstrapStore();
      bootstrapStore.$patch({
        ui: {
          show_version: false,
          footer_links: { enabled: true, groups: [] },
          workspace_links: { enabled: true, links: [] },
        },
      });

      const { showVersionConfig } = useFooterConfig();

      expect(showVersionConfig.value).toBe(false);
      // Verify other props weren't affected
      expect(bootstrapStore.ui?.footer_links?.enabled).toBe(true);
    });
  });

  // showVersion is the flag footers actually render on. It ANDs the deployment
  // config with the session's authenticated state, so the exact build version
  // is never shown to anonymous visitors (fingerprinting / CVE matching).
  // The server withholds it too (SystemSerializer) — this is the UI half.
  describe('showVersion', () => {
    it('is true only when configured AND authenticated', () => {
      const bootstrapStore = useBootstrapStore();
      bootstrapStore.$patch({
        authenticated: true,
        ui: { show_version: true },
      });

      const { showVersion } = useFooterConfig();

      expect(showVersion.value).toBe(true);
    });

    it('is false for an anonymous visitor even when show_version is true', () => {
      const bootstrapStore = useBootstrapStore();
      bootstrapStore.$patch({
        authenticated: false,
        ui: { show_version: true },
      });

      const { showVersion } = useFooterConfig();

      expect(showVersion.value).toBe(false);
    });

    it('is false when authenticated but the deployment disabled show_version', () => {
      const bootstrapStore = useBootstrapStore();
      bootstrapStore.$patch({
        authenticated: true,
        ui: { show_version: false },
      });

      const { showVersion } = useFooterConfig();

      expect(showVersion.value).toBe(false);
    });

    it('defaults to hidden when authenticated is unset (fails closed)', () => {
      const bootstrapStore = useBootstrapStore();
      bootstrapStore.$patch({
        ui: { show_version: true },
      });

      const { showVersion } = useFooterConfig();

      expect(showVersion.value).toBe(false);
    });

    it('flips reactively when the session becomes authenticated', () => {
      const bootstrapStore = useBootstrapStore();
      bootstrapStore.$patch({
        authenticated: false,
        ui: { show_version: true },
      });

      const { showVersion } = useFooterConfig();
      expect(showVersion.value).toBe(false);

      bootstrapStore.$patch({ authenticated: true });

      expect(showVersion.value).toBe(true);
    });
  });

  // useFooterAnchor decides what occupies the LEFT cell of the footer's
  // bottom bar. That bar is a two-ended `justify-between` row (left cell vs
  // toggle cluster) and only reads as a bar when both ends are filled. Since
  // the version went authenticated-only and `displayPoweredBy` is an opt-in
  // App.vue defaults to false, the cell was empty on nearly every surface —
  // so the existing attribution falls back in as a brand anchor.
  //
  // The one place it must NOT fall back is a custom domain: the attribution
  // interpolates the INSTALL's brand_product_name (never the tenant's), so an
  // unrequested anchor would stamp operator branding onto a customer's
  // white-labelled page. An explicit displayPoweredBy: true still wins there.
  describe('useFooterAnchor', () => {
    const anchor = (displayVersion = true, displayPoweredBy = false) =>
      useFooterAnchor({ displayVersion, displayPoweredBy });

    describe('anonymous surfaces (the lop-sided case this fixes)', () => {
      it('anchors with the attribution when the version is withheld', () => {
        const bootstrapStore = useBootstrapStore();
        bootstrapStore.$patch({
          authenticated: false,
          ui: { show_version: true },
        });

        const { showVersion, showPoweredBy, showSeparator } = anchor();

        expect(showVersion.value).toBe(false);
        expect(showPoweredBy.value).toBe(true);
        // Nothing on the left of it, so no divider.
        expect(showSeparator.value).toBe(false);
      });

      it('never leaves the left cell empty (version OR attribution always on)', () => {
        const bootstrapStore = useBootstrapStore();
        bootstrapStore.$patch({
          authenticated: false,
          ui: { show_version: false },
        });

        const { showVersion, showPoweredBy } = anchor();

        expect(showVersion.value || showPoweredBy.value).toBe(true);
      });
    });

    describe('authenticated surfaces', () => {
      it('shows the version and drops the fallback attribution', () => {
        const bootstrapStore = useBootstrapStore();
        bootstrapStore.$patch({
          authenticated: true,
          ui: { show_version: true },
        });

        const { showVersion, showPoweredBy, showSeparator } = anchor();

        expect(showVersion.value).toBe(true);
        // The version already occupies the cell; no anchor needed.
        expect(showPoweredBy.value).toBe(false);
        expect(showSeparator.value).toBe(false);
      });

      it('shows the separator only when BOTH occupants render', () => {
        const bootstrapStore = useBootstrapStore();
        bootstrapStore.$patch({
          authenticated: true,
          ui: { show_version: true },
        });

        const { showVersion, showPoweredBy, showSeparator } = anchor(true, true);

        expect(showVersion.value).toBe(true);
        expect(showPoweredBy.value).toBe(true);
        expect(showSeparator.value).toBe(true);
      });

      it('anchors when the deployment disabled show_version', () => {
        const bootstrapStore = useBootstrapStore();
        bootstrapStore.$patch({
          authenticated: true,
          ui: { show_version: false },
        });

        const { showVersion, showPoweredBy, showSeparator } = anchor();

        expect(showVersion.value).toBe(false);
        expect(showPoweredBy.value).toBe(true);
        expect(showSeparator.value).toBe(false);
      });

      it('anchors when the layout passes displayVersion: false', () => {
        const bootstrapStore = useBootstrapStore();
        bootstrapStore.$patch({
          authenticated: true,
          ui: { show_version: true },
        });

        const { showVersion, showPoweredBy } = anchor(false);

        expect(showVersion.value).toBe(false);
        expect(showPoweredBy.value).toBe(true);
      });
    });

    describe('explicit displayPoweredBy opt-in', () => {
      it('renders the attribution regardless of the version state', () => {
        const bootstrapStore = useBootstrapStore();
        bootstrapStore.$patch({
          authenticated: false,
          ui: { show_version: true },
        });

        const { showPoweredBy } = anchor(true, true);

        expect(showPoweredBy.value).toBe(true);
      });
    });

    describe('custom domain (white-label guard)', () => {
      it('suppresses the fallback anchor so operator branding does not leak', () => {
        const bootstrapStore = useBootstrapStore();
        bootstrapStore.$patch({
          authenticated: false,
          domain_strategy: 'custom',
          ui: { show_version: true },
        });

        const { isCustomDomain, showVersion, showPoweredBy } = anchor();

        expect(isCustomDomain.value).toBe(true);
        expect(showVersion.value).toBe(false);
        // Left cell stays empty here on purpose: a lop-sided bar is cheaper
        // than "Powered by <operator>" on a customer's white-labelled page.
        expect(showPoweredBy.value).toBe(false);
      });

      it('still honours an explicit displayPoweredBy: true on a custom domain', () => {
        // public.routes.ts and apps/secret/routes/receipt.ts deliberately opt
        // in to the attribution for custom-domain surfaces. The guard must
        // only suppress the FALLBACK, never the explicit request.
        const bootstrapStore = useBootstrapStore();
        bootstrapStore.$patch({
          authenticated: false,
          domain_strategy: 'custom',
          ui: { show_version: true },
        });

        const { showPoweredBy } = anchor(true, true);

        expect(showPoweredBy.value).toBe(true);
      });

      it('anchors normally on canonical and subdomain strategies', () => {
        const bootstrapStore = useBootstrapStore();
        bootstrapStore.$patch({
          authenticated: false,
          domain_strategy: 'subdomain',
          ui: { show_version: true },
        });

        const { isCustomDomain, showPoweredBy } = anchor();

        expect(isCustomDomain.value).toBe(false);
        expect(showPoweredBy.value).toBe(true);
      });
    });

    // hasAnchor drives the bar's justification. `justify-between` only makes
    // sense with two occupants; where the white-label guard withholds the
    // fallback, the bar centers the toggle cluster instead of stranding it
    // against a bare edge.
    describe('hasAnchor (bar justification predicate)', () => {
      it('is true when the version occupies the cell', () => {
        const bootstrapStore = useBootstrapStore();
        bootstrapStore.$patch({
          authenticated: true,
          ui: { show_version: true },
        });

        const { hasAnchor } = anchor();

        expect(hasAnchor.value).toBe(true);
      });

      it('is true when the fallback attribution occupies the cell', () => {
        const bootstrapStore = useBootstrapStore();
        bootstrapStore.$patch({
          authenticated: false,
          ui: { show_version: true },
        });

        const { showVersion, hasAnchor } = anchor();

        expect(showVersion.value).toBe(false);
        expect(hasAnchor.value).toBe(true);
      });

      it('is FALSE for an anonymous visitor on a custom domain', () => {
        // The one genuinely empty cell: the guard withholds the attribution
        // and there is no version. This is a real surface — a tenant's
        // /signin, which src/apps/session/routes.ts leaves at App.vue's
        // displayPoweredBy: false.
        const bootstrapStore = useBootstrapStore();
        bootstrapStore.$patch({
          authenticated: false,
          domain_strategy: 'custom',
          ui: { show_version: true },
        });

        const { showVersion, showPoweredBy, hasAnchor } = anchor();

        expect(showVersion.value).toBe(false);
        expect(showPoweredBy.value).toBe(false);
        expect(hasAnchor.value).toBe(false);
      });

      it('is true on a custom domain once the version is permitted', () => {
        const bootstrapStore = useBootstrapStore();
        bootstrapStore.$patch({
          authenticated: true,
          domain_strategy: 'custom',
          ui: { show_version: true },
        });

        const { hasAnchor } = anchor();

        expect(hasAnchor.value).toBe(true);
      });

      it('is true on a custom domain when attribution is opted into', () => {
        const bootstrapStore = useBootstrapStore();
        bootstrapStore.$patch({
          authenticated: false,
          domain_strategy: 'custom',
          ui: { show_version: true },
        });

        const { hasAnchor } = anchor(true, true);

        expect(hasAnchor.value).toBe(true);
      });
    });

    describe('reactivity', () => {
      it('hands the cell from the attribution to the version on sign-in', () => {
        const bootstrapStore = useBootstrapStore();
        bootstrapStore.$patch({
          authenticated: false,
          ui: { show_version: true },
        });

        const { showVersion, showPoweredBy } = anchor();
        expect(showVersion.value).toBe(false);
        expect(showPoweredBy.value).toBe(true);

        bootstrapStore.$patch({ authenticated: true });

        expect(showVersion.value).toBe(true);
        expect(showPoweredBy.value).toBe(false);
      });

      it('tracks ref/getter-backed props (how the footers pass them)', () => {
        const bootstrapStore = useBootstrapStore();
        bootstrapStore.$patch({
          authenticated: true,
          ui: { show_version: true },
        });

        // The footers hand over `() => props.displayVersion`; a ref exercises
        // the same MaybeRefOrGetter contract without a component mount.
        const displayVersion = ref(true);
        const { showVersion, showPoweredBy } = useFooterAnchor({
          displayVersion,
          displayPoweredBy: () => false,
        });

        expect(showVersion.value).toBe(true);
        expect(showPoweredBy.value).toBe(false);

        displayVersion.value = false;

        // Version gone -> the attribution anchors the cell instead.
        expect(showVersion.value).toBe(false);
        expect(showPoweredBy.value).toBe(true);
      });
    });
  });
});
