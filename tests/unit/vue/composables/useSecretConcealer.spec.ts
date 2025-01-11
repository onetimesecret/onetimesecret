// tests/unit/vue/composables/useSecretConcealer.spec.ts
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
      const { secretContent, formKind, isSubmitting, error, success } =
        useSecretConcealer();

      expect(secretContent.value).toBe('');
      expect(formKind.value).toBe('conceal');
      expect(isSubmitting.value).toBe(false);
      expect(error.value).toBeNull();
      expect(success.value).toBeNull();
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

    it('handles successful secret sharing', async () => {
      // Setup form data mock
      const formDataMock = new FormData();
      formDataMock.append('secret', 'test secret');
      formDataMock.append('share_domain', 'example.com');

      const form = document.createElement('form');
      form.id = 'createSecret';
      document.body.appendChild(form);

      const { submitForm, isSubmitting, error } = useSecretConcealer();

      // Execute
      await submitForm();

      // Verify
      expect(isSubmitting.value).toBe(false);
      expect(error.value).toBeNull();
      expect(mockRouter.push).toHaveBeenCalledWith({
        name: 'Metadata link',
        params: { metadataKey: 'test-metadata-key' },
      });
    });

    it('handles validation errors', async () => {
      const store = {
        conceal: vi.fn().mockRejectedValue(new Error('Validation failed')),
      };
      vi.mocked(useSecretStore).mockReturnValue(store);

      const { submitForm, isSubmitting, error } = useSecretConcealer();

      await submitForm();

      expect(isSubmitting.value).toBe(false);
      expect(error.value).toBe('Validation failed');
      expect(mockRouter.push).not.toHaveBeenCalled();
    });
  });

  describe('form mode handling', () => {
    it('updates form kind and triggers submit on button click', async () => {
      const { handleButtonClick, formKind } = useSecretConcealer();

      await handleButtonClick('generate');

      expect(formKind.value).toBe('generate');
    });

    it('maintains share as default form kind', () => {
      const { formKind } = useSecretConcealer();
      expect(formKind.value).toBe('conceal');
    });
  });
});
