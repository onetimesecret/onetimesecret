// src/tests/composables/useWorkspacePrivacyDefaults.spec.ts

import { beforeEach, describe, expect, it, vi, afterEach } from 'vitest';
import { ref, computed, nextTick } from 'vue';
import type { BrandSettings } from '@/schemas/models/domain';

// Mock formatDuration
const mockFormatDuration = vi.fn((seconds: number) => {
  if (seconds === 3600) return '1 hour';
  if (seconds === 86400) return '1 day';
  if (seconds === 604800) return '7 days';
  return `${seconds} seconds`;
});

// Mock usePrivacyOptions
vi.mock('@/shared/composables/usePrivacyOptions', () => ({
  usePrivacyOptions: () => ({
    formatDuration: mockFormatDuration,
    lifetimeOptions: ref([]),
    state: ref({ passphraseVisibility: false, lifetimeOptions: [] }),
  }),
}));

// Mock WindowService
const mockSecretOptions = {
  default_ttl: 604800, // 7 days
  passphrase: { required: false },
};

vi.mock('@/services/window.service', () => ({
  WindowService: {
    get: vi.fn((key: string) => {
      if (key === 'secret_options') return mockSecretOptions;
      return null;
    }),
  },
}));

import {
  useWorkspacePrivacyDefaults,
  type UseWorkspacePrivacyDefaultsOptions,
} from '@/apps/workspace/composables/useWorkspacePrivacyDefaults';

describe('useWorkspacePrivacyDefaults', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockSecretOptions.default_ttl = 604800;
    mockSecretOptions.passphrase = { required: false };
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  function createOptions(
    overrides: Partial<{
      brandSettings: BrandSettings;
      isCanonical: boolean;
      isLoading: boolean;
    }> = {}
  ): UseWorkspacePrivacyDefaultsOptions {
    const defaultBrandSettings: BrandSettings = {
      primary_color: '#dc4a22',
      font_family: 'sans',
      corner_style: 'rounded',
      button_text_light: false,
      allow_public_homepage: false,
      allow_public_api: false,
      default_ttl: undefined,
      passphrase_required: false,
      notify_enabled: false,
    };

    return {
      brandSettings: ref({
        ...defaultBrandSettings,
        ...overrides.brandSettings,
      }),
      isCanonical: computed(() => overrides.isCanonical ?? false),
      isLoading: ref(overrides.isLoading ?? false),
    };
  }

  describe('canonical domain behavior', () => {
    it('returns global defaults for canonical domain', () => {
      const options = createOptions({ isCanonical: true });
      const { privacyDefaults } = useWorkspacePrivacyDefaults(options);

      expect(privacyDefaults.value.isGlobalDefaults).toBe(true);
      expect(privacyDefaults.value.defaultTtl).toBe(604800);
      expect(privacyDefaults.value.passphraseRequired).toBe(false);
      expect(privacyDefaults.value.notifyEnabled).toBe(false);
    });

    it('marks canonical domain settings as not editable', () => {
      const options = createOptions({ isCanonical: true });
      const { privacyDefaults, isEditable } = useWorkspacePrivacyDefaults(options);

      expect(privacyDefaults.value.isEditable).toBe(false);
      expect(isEditable.value).toBe(false);
    });

    it('ignores brand settings for canonical domain', () => {
      const options = createOptions({
        isCanonical: true,
        brandSettings: {
          default_ttl: 3600,
          passphrase_required: true,
          notify_enabled: true,
        },
      });
      const { privacyDefaults } = useWorkspacePrivacyDefaults(options);

      // Should use global defaults, not brand settings
      expect(privacyDefaults.value.defaultTtl).toBe(604800);
      expect(privacyDefaults.value.passphraseRequired).toBe(false);
      expect(privacyDefaults.value.notifyEnabled).toBe(false);
    });

    it('uses global passphrase required setting when true', () => {
      // Mutate the mock to simulate global passphrase required = true
      mockSecretOptions.passphrase = { required: true };

      const options = createOptions({ isCanonical: true });
      const { privacyDefaults } = useWorkspacePrivacyDefaults(options);

      // Canonical domain should reflect the global passphrase required setting
      expect(privacyDefaults.value.isGlobalDefaults).toBe(true);
      expect(privacyDefaults.value.passphraseRequired).toBe(true);
    });
  });

  describe('custom domain behavior', () => {
    it('returns brand settings for custom domain', () => {
      const options = createOptions({
        isCanonical: false,
        brandSettings: {
          default_ttl: 3600,
          passphrase_required: true,
          notify_enabled: true,
        },
      });
      const { privacyDefaults } = useWorkspacePrivacyDefaults(options);

      expect(privacyDefaults.value.isGlobalDefaults).toBe(false);
      expect(privacyDefaults.value.defaultTtl).toBe(3600);
      expect(privacyDefaults.value.passphraseRequired).toBe(true);
      expect(privacyDefaults.value.notifyEnabled).toBe(true);
    });

    it('marks custom domain settings as editable', () => {
      const options = createOptions({ isCanonical: false });
      const { privacyDefaults, isEditable } = useWorkspacePrivacyDefaults(options);

      expect(privacyDefaults.value.isEditable).toBe(true);
      expect(isEditable.value).toBe(true);
    });

    it('returns null for TTL when not set on custom domain', () => {
      const options = createOptions({
        isCanonical: false,
        brandSettings: { default_ttl: undefined },
      });
      const { privacyDefaults } = useWorkspacePrivacyDefaults(options);

      expect(privacyDefaults.value.defaultTtl).toBeNull();
    });

    it('defaults passphrase and notify to false when not set', () => {
      const options = createOptions({
        isCanonical: false,
        brandSettings: {},
      });
      const { privacyDefaults } = useWorkspacePrivacyDefaults(options);

      expect(privacyDefaults.value.passphraseRequired).toBe(false);
      expect(privacyDefaults.value.notifyEnabled).toBe(false);
    });
  });

  describe('display formatting', () => {
    it('formats TTL using formatDuration for canonical domain', () => {
      const options = createOptions({ isCanonical: true });
      const { ttlDisplay } = useWorkspacePrivacyDefaults(options);

      expect(ttlDisplay.value).toBe('7 days');
      expect(mockFormatDuration).toHaveBeenCalledWith(604800);
    });

    it('formats TTL using formatDuration for custom domain with TTL set', () => {
      const options = createOptions({
        isCanonical: false,
        brandSettings: { default_ttl: 3600 },
      });
      const { ttlDisplay } = useWorkspacePrivacyDefaults(options);

      expect(ttlDisplay.value).toBe('1 hour');
      expect(mockFormatDuration).toHaveBeenCalledWith(3600);
    });

    it('uses global default for TTL display when custom domain has no TTL', () => {
      const options = createOptions({
        isCanonical: false,
        brandSettings: { default_ttl: null },
      });
      const { ttlDisplay } = useWorkspacePrivacyDefaults(options);

      expect(ttlDisplay.value).toBe('7 days');
      expect(mockFormatDuration).toHaveBeenCalledWith(604800);
    });

    it('returns "required" for passphrase display when required', () => {
      const options = createOptions({
        isCanonical: false,
        brandSettings: { passphrase_required: true },
      });
      const { passphraseDisplay } = useWorkspacePrivacyDefaults(options);

      expect(passphraseDisplay.value).toBe('required');
    });

    it('returns "optional" for passphrase display when not required', () => {
      const options = createOptions({
        isCanonical: false,
        brandSettings: { passphrase_required: false },
      });
      const { passphraseDisplay } = useWorkspacePrivacyDefaults(options);

      expect(passphraseDisplay.value).toBe('optional');
    });

    it('returns "enabled" for notify display when enabled', () => {
      const options = createOptions({
        isCanonical: false,
        brandSettings: { notify_enabled: true },
      });
      const { notifyDisplay } = useWorkspacePrivacyDefaults(options);

      expect(notifyDisplay.value).toBe('enabled');
    });

    it('returns "disabled" for notify display when disabled', () => {
      const options = createOptions({
        isCanonical: false,
        brandSettings: { notify_enabled: false },
      });
      const { notifyDisplay } = useWorkspacePrivacyDefaults(options);

      expect(notifyDisplay.value).toBe('disabled');
    });
  });

  describe('hasCustomSettings detection', () => {
    it('returns false for canonical domain regardless of settings', () => {
      const options = createOptions({
        isCanonical: true,
        brandSettings: {
          default_ttl: 3600,
          passphrase_required: true,
          notify_enabled: true,
        },
      });
      const { hasCustomSettings } = useWorkspacePrivacyDefaults(options);

      expect(hasCustomSettings.value).toBe(false);
    });

    it('returns false when custom domain has all defaults', () => {
      const options = createOptions({
        isCanonical: false,
        brandSettings: {
          default_ttl: null,
          passphrase_required: false,
          notify_enabled: false,
        },
      });
      const { hasCustomSettings } = useWorkspacePrivacyDefaults(options);

      expect(hasCustomSettings.value).toBe(false);
    });

    it('returns true when custom TTL is set', () => {
      const options = createOptions({
        isCanonical: false,
        brandSettings: { default_ttl: 3600 },
      });
      const { hasCustomSettings } = useWorkspacePrivacyDefaults(options);

      expect(hasCustomSettings.value).toBe(true);
    });

    it('returns true when passphrase is required', () => {
      const options = createOptions({
        isCanonical: false,
        brandSettings: { passphrase_required: true },
      });
      const { hasCustomSettings } = useWorkspacePrivacyDefaults(options);

      expect(hasCustomSettings.value).toBe(true);
    });

    it('returns true when notifications are enabled', () => {
      const options = createOptions({
        isCanonical: false,
        brandSettings: { notify_enabled: true },
      });
      const { hasCustomSettings } = useWorkspacePrivacyDefaults(options);

      expect(hasCustomSettings.value).toBe(true);
    });

    it('returns true when multiple custom settings are set', () => {
      const options = createOptions({
        isCanonical: false,
        brandSettings: {
          default_ttl: 86400,
          passphrase_required: true,
          notify_enabled: true,
        },
      });
      const { hasCustomSettings } = useWorkspacePrivacyDefaults(options);

      expect(hasCustomSettings.value).toBe(true);
    });
  });

  describe('reactivity', () => {
    it('updates when brand settings change', async () => {
      const brandSettings = ref<BrandSettings>({
        default_ttl: undefined,
        passphrase_required: false,
        notify_enabled: false,
      });

      const { privacyDefaults } = useWorkspacePrivacyDefaults({
        brandSettings,
        isCanonical: computed(() => false),
      });

      expect(privacyDefaults.value.defaultTtl).toBeNull();

      brandSettings.value = {
        ...brandSettings.value,
        default_ttl: 7200,
      };

      await nextTick();

      expect(privacyDefaults.value.defaultTtl).toBe(7200);
    });

    it('updates when isCanonical changes', async () => {
      const isCanonicalRef = ref(false);

      const { privacyDefaults } = useWorkspacePrivacyDefaults({
        brandSettings: ref({ default_ttl: 3600 }),
        isCanonical: computed(() => isCanonicalRef.value),
      });

      expect(privacyDefaults.value.isGlobalDefaults).toBe(false);
      expect(privacyDefaults.value.defaultTtl).toBe(3600);

      isCanonicalRef.value = true;

      await nextTick();

      expect(privacyDefaults.value.isGlobalDefaults).toBe(true);
      expect(privacyDefaults.value.defaultTtl).toBe(604800);
    });
  });

  describe('edge cases', () => {
    it('handles undefined brand settings gracefully', () => {
      const options = createOptions({
        isCanonical: false,
        brandSettings: {} as BrandSettings,
      });
      const { privacyDefaults } = useWorkspacePrivacyDefaults(options);

      expect(privacyDefaults.value.defaultTtl).toBeNull();
      expect(privacyDefaults.value.passphraseRequired).toBe(false);
      expect(privacyDefaults.value.notifyEnabled).toBe(false);
    });

    it('handles explicit false values correctly', () => {
      const options = createOptions({
        isCanonical: false,
        brandSettings: {
          default_ttl: 0,
          passphrase_required: false,
          notify_enabled: false,
        },
      });
      const { privacyDefaults } = useWorkspacePrivacyDefaults(options);

      // TTL of 0 should be treated as set (not null)
      expect(privacyDefaults.value.defaultTtl).toBe(0);
    });
  });
});
