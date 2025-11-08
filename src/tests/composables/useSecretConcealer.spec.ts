// src/tests/composables/useSecretConcealer.spec.ts

import { useSecretConcealer } from '@/composables/useSecretConcealer';
import { useSecretStore } from '@/stores/secretStore';
import { Router, useRouter } from 'vue-router';
import { createPinia, setActivePinia } from 'pinia';
import { beforeEach, describe, expect, it, vi } from 'vitest';

vi.mock('@/stores/secretStore');
vi.mock('vue-router');

const mockRouter = {
  push: vi.fn(),
} as unknown as Router; // Use `unknown` as an intermediate type to bypass
vi.mocked(useRouter).mockReturnValue(mockRouter);

describe('useSecretConcealer', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
  });

  describe('lifecycle', () => {
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
      };
      vi.mocked(useSecretStore).mockReturnValue(store);

      const { submit, isSubmitting } = useSecretConcealer();

      await submit('conceal');

      expect(isSubmitting.value).toBe(false);
      expect(mockRouter.push).not.toHaveBeenCalled();
    });
  });

  describe('form mode handling', () => {
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
});
