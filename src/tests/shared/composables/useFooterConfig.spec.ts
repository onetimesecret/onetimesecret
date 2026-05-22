// src/tests/shared/composables/useFooterConfig.spec.ts
//
// Tests for useFooterConfig composable behavior:
// - showVersionConfig returns true when ui.show_version is true
// - showVersionConfig returns true when ui.show_version is undefined (default)
// - showVersionConfig returns false when ui.show_version is false

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { setActivePinia, createPinia } from 'pinia';
import { useFooterConfig } from '@/shared/composables/useFooterConfig';
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
});
