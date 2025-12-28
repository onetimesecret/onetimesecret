// src/tests/composables/useSecretConcealer.spec.ts

import { useSecretConcealer } from '@/shared/composables/useSecretConcealer';
import { useSecretStore } from '@/shared/stores/secretStore';
import { Router, useRouter } from 'vue-router';
import { createPinia, setActivePinia } from 'pinia';
import { beforeEach, describe, expect, it, vi } from 'vitest';

// Mock vue-i18n for useAsyncHandler dependency
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key: string) => key,
  }),
}));

vi.mock('@/shared/stores/secretStore');
vi.mock('vue-router');

const mockRouter = {
  push: vi.fn(),
} as unknown as Router; // Use `unknown` as an intermediate type to bypass
vi.mocked(useRouter).mockReturnValue(mockRouter);

// Mock authStore to control authentication state
const mockAuthStore = {
  isAuthenticated: true,
};
vi.mock('@/shared/stores/authStore', () => ({
  useAuthStore: () => mockAuthStore,
}));

describe('useSecretConcealer', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
    // Reset auth state to authenticated by default
    mockAuthStore.isAuthenticated = true;
  });

  describe('lifecycle', () => {
    beforeEach(() => {
      const store = {
        conceal: vi.fn().mockResolvedValue({ record: { metadata: { key: 'test' } } }),
        generate: vi.fn().mockResolvedValue({ record: { metadata: { key: 'test' } } }),
        setApiMode: vi.fn(),
      };
      vi.mocked(useSecretStore).mockReturnValue(store);
    });

    it('initializes with empty state', () => {
      const { form, isSubmitting } = useSecretConcealer();

      expect(form.secret).toBe('');
      expect(isSubmitting.value).toBe(false);
    });
  });

  describe('form submission', () => {
    const mockResponse = {
      record: {
        metadata: {
          key: 'test-metadata-key',
        },
      },
    };

    beforeEach(() => {
      const store = {
        conceal: vi.fn().mockResolvedValue(mockResponse),
        generate: vi.fn().mockResolvedValue(mockResponse),
        setApiMode: vi.fn(),
      };
      vi.mocked(useSecretStore).mockReturnValue(store);
    });

    it.skip('handles successful secret sharing', async () => {
      const { submit, isSubmitting } = useSecretConcealer({
        onSuccess: async (response) => {
          mockRouter.push({
            name: 'Metadata link',
            params: { metadataIdentifier: response.record.metadata.identifier },
          });
        },
      });

      // Execute
      await submit('conceal');

      // Verify
      expect(isSubmitting.value).toBe(false);
      expect(mockRouter.push).toHaveBeenCalledWith({
        name: 'Metadata link',
        params: { metadataIdentifier: 'test-metadata-key' },
      });
    });

    it('handles validation errors', async () => {
      const store = {
        conceal: vi.fn().mockRejectedValue(new Error('Validation failed')),
        generate: vi.fn().mockRejectedValue(new Error('Validation failed')),
        setApiMode: vi.fn(),
      };
      vi.mocked(useSecretStore).mockReturnValue(store);

      const { submit, isSubmitting } = useSecretConcealer();

      await submit('conceal');

      expect(isSubmitting.value).toBe(false);
      expect(mockRouter.push).not.toHaveBeenCalled();
    });
  });

  describe('form mode handling', () => {
    beforeEach(() => {
      const store = {
        conceal: vi.fn().mockResolvedValue({ record: { metadata: { key: 'test' } } }),
        generate: vi.fn().mockResolvedValue({ record: { metadata: { key: 'test' } } }),
        setApiMode: vi.fn(),
      };
      vi.mocked(useSecretStore).mockReturnValue(store);
    });

    it('can submit in generate mode', async () => {
      const { submit } = useSecretConcealer();

      await submit('generate');

      expect(vi.mocked(useSecretStore)).toHaveBeenCalled();
    });

    it('can submit in conceal mode', async () => {
      const { submit } = useSecretConcealer();

      await submit('conceal');

      expect(vi.mocked(useSecretStore)).toHaveBeenCalled();
    });
  });

  describe('API mode selection', () => {
    let mockSetApiMode: ReturnType<typeof vi.fn>;

    beforeEach(() => {
      mockSetApiMode = vi.fn();
      const store = {
        conceal: vi.fn().mockResolvedValue({ record: { metadata: { key: 'test' } } }),
        generate: vi.fn().mockResolvedValue({ record: { metadata: { key: 'test' } } }),
        setApiMode: mockSetApiMode,
      };
      vi.mocked(useSecretStore).mockReturnValue(store);
    });

    describe('default behavior (usePublicApi not specified)', () => {
      it('uses authenticated mode when user is authenticated', async () => {
        mockAuthStore.isAuthenticated = true;
        const { submit } = useSecretConcealer();

        await submit('conceal');

        expect(mockSetApiMode).toHaveBeenCalledWith('authenticated');
      });

      it('uses public mode when user is not authenticated', async () => {
        mockAuthStore.isAuthenticated = false;
        const { submit } = useSecretConcealer();

        await submit('conceal');

        expect(mockSetApiMode).toHaveBeenCalledWith('public');
      });

      it('uses public mode when authentication state is null', async () => {
        mockAuthStore.isAuthenticated = null;
        const { submit } = useSecretConcealer();

        await submit('conceal');

        expect(mockSetApiMode).toHaveBeenCalledWith('public');
      });
    });

    describe('usePublicApi option', () => {
      it('forces public mode when usePublicApi is true, even if authenticated', async () => {
        mockAuthStore.isAuthenticated = true;
        const { submit } = useSecretConcealer({ usePublicApi: true });

        await submit('conceal');

        expect(mockSetApiMode).toHaveBeenCalledWith('public');
      });

      it('forces authenticated mode when usePublicApi is false, even if not authenticated', async () => {
        mockAuthStore.isAuthenticated = false;
        const { submit } = useSecretConcealer({ usePublicApi: false });

        await submit('conceal');

        expect(mockSetApiMode).toHaveBeenCalledWith('authenticated');
      });

      it('respects usePublicApi for generate mode', async () => {
        mockAuthStore.isAuthenticated = true;
        const { submit } = useSecretConcealer({ usePublicApi: true });

        await submit('generate');

        expect(mockSetApiMode).toHaveBeenCalledWith('public');
      });
    });
  });
});
