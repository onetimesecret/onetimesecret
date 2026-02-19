// src/tests/composables/useIncomingSecret.spec.ts

import { useIncomingSecret } from '@/shared/composables/useIncomingSecret';
import { useIncomingStore } from '@/shared/stores/incomingStore';
import { useNotificationsStore } from '@/shared/stores/notificationsStore';
import { Router, useRouter } from 'vue-router';
import { createPinia, setActivePinia } from 'pinia';
import { beforeEach, describe, expect, it, vi } from 'vitest';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key: string) => key,
  }),
}));

vi.mock('@/shared/stores/incomingStore');
vi.mock('@/shared/stores/notificationsStore');
vi.mock('vue-router');

const mockRouter = {
  push: vi.fn(),
} as unknown as Router;
vi.mocked(useRouter).mockReturnValue(mockRouter);

// Default mock store values, tests can override per-case
const mockIncomingStore = {
  isFeatureEnabled: true,
  memoMaxLength: 50,
  recipients: [],
  isLoading: false,
  configError: null as string | null,
  loadConfig: vi.fn().mockResolvedValue(undefined),
  createIncomingSecret: vi.fn(),
};

const mockNotificationsStore = {
  show: vi.fn(),
};

vi.mocked(useIncomingStore).mockReturnValue(mockIncomingStore as any);
vi.mocked(useNotificationsStore).mockReturnValue(mockNotificationsStore as any);

describe('useIncomingSecret', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
    mockIncomingStore.isFeatureEnabled = true;
    mockIncomingStore.memoMaxLength = 50;
    mockIncomingStore.recipients = [];
    mockIncomingStore.isLoading = false;
    mockIncomingStore.configError = null;
    vi.mocked(useIncomingStore).mockReturnValue(mockIncomingStore as any);
    vi.mocked(useNotificationsStore).mockReturnValue(mockNotificationsStore as any);
  });

  describe('form initialization', () => {
    it('initializes form with empty strings', () => {
      const { form } = useIncomingSecret();

      expect(form.value.memo).toBe('');
      expect(form.value.secret).toBe('');
      expect(form.value.recipientId).toBe('');
    });

    it('initializes errors as empty object', () => {
      const { errors } = useIncomingSecret();

      expect(errors.value).toEqual({});
    });

    it('initializes isSubmitting as false', () => {
      const { isSubmitting } = useIncomingSecret();

      expect(isSubmitting.value).toBe(false);
    });
  });

  describe('isFormValid', () => {
    it('is false when secret is empty', () => {
      const { form, isFormValid } = useIncomingSecret();

      form.value.secret = '';
      form.value.recipientId = 'abc123';

      expect(isFormValid.value).toBe(false);
    });

    it('is false when recipientId is empty', () => {
      const { form, isFormValid } = useIncomingSecret();

      form.value.secret = 'my secret';
      form.value.recipientId = '';

      expect(isFormValid.value).toBe(false);
    });

    it('is false when secret is whitespace only', () => {
      const { form, isFormValid } = useIncomingSecret();

      form.value.secret = '   ';
      form.value.recipientId = 'abc123';

      expect(isFormValid.value).toBe(false);
    });

    it('is true when both secret and recipientId are set', () => {
      const { form, isFormValid } = useIncomingSecret();

      form.value.secret = 'my secret';
      form.value.recipientId = 'abc123';

      expect(isFormValid.value).toBe(true);
    });
  });

  describe('validateMemo', () => {
    it('passes when memo is empty (optional field)', () => {
      const { form, errors, validateMemo } = useIncomingSecret();

      form.value.memo = '';
      const result = validateMemo();

      expect(result).toBe(true);
      expect(errors.value.memo).toBeUndefined();
    });

    it('passes when memo is within max length', () => {
      const { form, errors, validateMemo } = useIncomingSecret();

      form.value.memo = 'A valid memo';
      const result = validateMemo();

      expect(result).toBe(true);
      expect(errors.value.memo).toBeUndefined();
    });

    it('fails when memo exceeds max length', () => {
      const { form, errors, validateMemo } = useIncomingSecret();

      form.value.memo = 'x'.repeat(51); // exceeds default 50
      const result = validateMemo();

      expect(result).toBe(false);
      expect(errors.value.memo).toBeTruthy();
    });

    it('passes when memo is whitespace only (treated as empty)', () => {
      const { form, errors, validateMemo } = useIncomingSecret();

      form.value.memo = '   ';
      const result = validateMemo();

      // Whitespace-only memo trims to empty string, which is valid (optional field)
      expect(result).toBe(true);
      expect(errors.value.memo).toBeUndefined();
    });

    it('clears existing memo error on valid input', () => {
      const { form, errors, validateMemo } = useIncomingSecret();

      // First set an error
      errors.value.memo = 'previous error';
      form.value.memo = 'Valid memo';
      const result = validateMemo();

      expect(result).toBe(true);
      expect(errors.value.memo).toBeUndefined();
    });
  });

  describe('validateSecret', () => {
    it('fails when secret is empty', () => {
      const { form, errors, validateSecret } = useIncomingSecret();

      form.value.secret = '';
      const result = validateSecret();

      expect(result).toBe(false);
      expect(errors.value.secret).toBeTruthy();
    });

    it('fails when secret is whitespace only', () => {
      const { form, errors, validateSecret } = useIncomingSecret();

      form.value.secret = '   ';
      const result = validateSecret();

      expect(result).toBe(false);
      expect(errors.value.secret).toBeTruthy();
    });

    it('passes when secret has content', () => {
      const { form, errors, validateSecret } = useIncomingSecret();

      form.value.secret = 'actual secret content';
      const result = validateSecret();

      expect(result).toBe(true);
      expect(errors.value.secret).toBeUndefined();
    });

    it('clears existing secret error on valid input', () => {
      const { form, errors, validateSecret } = useIncomingSecret();

      errors.value.secret = 'previous error';
      form.value.secret = 'valid secret';
      const result = validateSecret();

      expect(result).toBe(true);
      expect(errors.value.secret).toBeUndefined();
    });
  });

  describe('validateRecipient', () => {
    it('fails when recipientId is empty', () => {
      const { form, errors, validateRecipient } = useIncomingSecret();

      form.value.recipientId = '';
      const result = validateRecipient();

      expect(result).toBe(false);
      expect(errors.value.recipientId).toBeTruthy();
    });

    it('passes when recipientId is set', () => {
      const { form, errors, validateRecipient } = useIncomingSecret();

      form.value.recipientId = 'abc123hash';
      const result = validateRecipient();

      expect(result).toBe(true);
      expect(errors.value.recipientId).toBeUndefined();
    });

    it('clears existing recipient error on valid input', () => {
      const { form, errors, validateRecipient } = useIncomingSecret();

      errors.value.recipientId = 'previous error';
      form.value.recipientId = 'abc123hash';
      const result = validateRecipient();

      expect(result).toBe(true);
      expect(errors.value.recipientId).toBeUndefined();
    });
  });

  describe('validateForm', () => {
    it('validates all fields and returns true when all pass', () => {
      const { form, validateForm } = useIncomingSecret();

      form.value.secret = 'my secret';
      form.value.recipientId = 'abc123';
      form.value.memo = '';

      expect(validateForm()).toBe(true);
    });

    it('returns false when secret is invalid', () => {
      const { form, validateForm } = useIncomingSecret();

      form.value.secret = '';
      form.value.recipientId = 'abc123';

      expect(validateForm()).toBe(false);
    });

    it('returns false when recipient is invalid', () => {
      const { form, validateForm } = useIncomingSecret();

      form.value.secret = 'my secret';
      form.value.recipientId = '';

      expect(validateForm()).toBe(false);
    });

    it('does not short-circuit — validates all fields even if memo fails', () => {
      const { form, errors, validateForm } = useIncomingSecret();

      form.value.memo = 'x'.repeat(51); // invalid memo
      form.value.secret = '';            // invalid secret
      form.value.recipientId = '';       // invalid recipient

      const result = validateForm();

      // All fields should have errors — not short-circuited
      expect(result).toBe(false);
      expect(errors.value.memo).toBeTruthy();
      expect(errors.value.secret).toBeTruthy();
      expect(errors.value.recipientId).toBeTruthy();
    });

    it('does not short-circuit — collects all errors when secret fails', () => {
      const { form, errors, validateForm } = useIncomingSecret();

      form.value.secret = '';       // invalid
      form.value.recipientId = '';  // invalid

      validateForm();

      expect(errors.value.secret).toBeTruthy();
      expect(errors.value.recipientId).toBeTruthy();
    });
  });

  describe('clearValidation', () => {
    it('clears all validation errors', () => {
      const { errors, clearValidation } = useIncomingSecret();

      errors.value = {
        memo: 'memo error',
        secret: 'secret error',
        recipientId: 'recipient error',
      };

      clearValidation();

      expect(errors.value).toEqual({});
    });

    it('is idempotent when errors are already empty', () => {
      const { errors, clearValidation } = useIncomingSecret();

      clearValidation();

      expect(errors.value).toEqual({});
    });
  });

  describe('resetForm', () => {
    it('resets form fields to empty strings', () => {
      const { form, resetForm } = useIncomingSecret();

      form.value.memo = 'some memo';
      form.value.secret = 'some secret';
      form.value.recipientId = 'abc123';

      resetForm();

      expect(form.value.memo).toBe('');
      expect(form.value.secret).toBe('');
      expect(form.value.recipientId).toBe('');
    });

    it('clears validation errors on reset', () => {
      const { form, errors, validateForm, resetForm } = useIncomingSecret();

      // Trigger validation errors first
      form.value.secret = '';
      form.value.recipientId = '';
      validateForm();

      expect(errors.value.secret).toBeTruthy();

      resetForm();

      expect(errors.value).toEqual({});
    });
  });

  describe('computed store properties', () => {
    it('exposes memoMaxLength from store', () => {
      mockIncomingStore.memoMaxLength = 100;
      vi.mocked(useIncomingStore).mockReturnValue(mockIncomingStore as any);

      const { memoMaxLength } = useIncomingSecret();

      expect(memoMaxLength.value).toBe(100);
    });

    it('exposes isFeatureEnabled from store', () => {
      mockIncomingStore.isFeatureEnabled = false;
      vi.mocked(useIncomingStore).mockReturnValue(mockIncomingStore as any);

      const { isFeatureEnabled } = useIncomingSecret();

      expect(isFeatureEnabled.value).toBe(false);
    });

    it('exposes recipients from store', () => {
      const fakeRecipients = [{ hash: 'abc', name: 'Alice' }];
      mockIncomingStore.recipients = fakeRecipients as any;
      vi.mocked(useIncomingStore).mockReturnValue(mockIncomingStore as any);

      const { recipients } = useIncomingSecret();

      expect(recipients.value).toEqual(fakeRecipients);
    });
  });

  describe('submit()', () => {
    const mockSuccessResponse = {
      success: true,
      record: {
        receipt: { key: 'receipt-key-abc123', identifier: 'receipt-id' },
        secret: { key: 'secret-key-xyz', identifier: 'secret-id' },
      },
      details: { memo: 'test memo', recipient: 'hash123' },
    };

    beforeEach(() => {
      mockIncomingStore.isFeatureEnabled = true;
      mockIncomingStore.createIncomingSecret = vi.fn().mockResolvedValue(mockSuccessResponse);
      vi.mocked(useIncomingStore).mockReturnValue(mockIncomingStore as any);
    });

    it('does not call createIncomingSecret when feature is disabled', async () => {
      mockIncomingStore.isFeatureEnabled = false;
      vi.mocked(useIncomingStore).mockReturnValue(mockIncomingStore as any);

      const { form, submit } = useIncomingSecret();
      form.value.secret = 'my secret';
      form.value.recipientId = 'hash123';

      await submit();

      expect(mockIncomingStore.createIncomingSecret).not.toHaveBeenCalled();
    });

    it('does not call createIncomingSecret when form is invalid', async () => {
      const { form, submit } = useIncomingSecret();
      form.value.secret = ''; // invalid
      form.value.recipientId = 'hash123';

      await submit();

      expect(mockIncomingStore.createIncomingSecret).not.toHaveBeenCalled();
    });

    it('calls createIncomingSecret with form data on valid submit', async () => {
      const { form, submit } = useIncomingSecret();
      form.value.secret = 'the secret content';
      form.value.recipientId = 'hash123';
      form.value.memo = 'a memo';

      await submit();

      expect(mockIncomingStore.createIncomingSecret).toHaveBeenCalledWith({
        secret: 'the secret content',
        recipient: 'hash123',
        memo: 'a memo',
      });
    });

    it('navigates to IncomingSuccess with receipt key on successful submit', async () => {
      const { form, submit } = useIncomingSecret();
      form.value.secret = 'the secret';
      form.value.recipientId = 'hash123';

      await submit();

      expect(mockRouter.push).toHaveBeenCalledWith({
        name: 'IncomingSuccess',
        params: { receiptKey: 'receipt-key-abc123' },
      });
    });

    it('calls onSuccess callback instead of router.push when provided', async () => {
      const onSuccess = vi.fn().mockResolvedValue(undefined);
      const { form, submit } = useIncomingSecret({ onSuccess });
      form.value.secret = 'the secret';
      form.value.recipientId = 'hash123';

      await submit();

      expect(onSuccess).toHaveBeenCalledWith(mockSuccessResponse);
      expect(mockRouter.push).not.toHaveBeenCalled();
    });

    it('does not navigate when response.success is false', async () => {
      mockIncomingStore.createIncomingSecret = vi.fn().mockResolvedValue({
        ...mockSuccessResponse,
        success: false,
      });
      vi.mocked(useIncomingStore).mockReturnValue(mockIncomingStore as any);

      const { form, submit } = useIncomingSecret();
      form.value.secret = 'the secret';
      form.value.recipientId = 'hash123';

      await submit();

      expect(mockRouter.push).not.toHaveBeenCalled();
    });

    it('resets isSubmitting to false after successful submit', async () => {
      const { form, isSubmitting, submit } = useIncomingSecret();
      form.value.secret = 'the secret';
      form.value.recipientId = 'hash123';

      await submit();

      expect(isSubmitting.value).toBe(false);
    });

    it('resets isSubmitting to false when submit throws', async () => {
      mockIncomingStore.createIncomingSecret = vi.fn().mockRejectedValue(new Error('API error'));
      vi.mocked(useIncomingStore).mockReturnValue(mockIncomingStore as any);

      const { form, isSubmitting, submit } = useIncomingSecret();
      form.value.secret = 'the secret';
      form.value.recipientId = 'hash123';

      await submit();

      // useAsyncHandler's finally block always resets loading state
      expect(isSubmitting.value).toBe(false);
    });

    it('trims whitespace from memo in the payload', async () => {
      const { form, submit } = useIncomingSecret();
      form.value.secret = 'the secret';
      form.value.recipientId = 'hash123';
      form.value.memo = '  padded memo  ';

      await submit();

      expect(mockIncomingStore.createIncomingSecret).toHaveBeenCalledWith(
        expect.objectContaining({ memo: 'padded memo' })
      );
    });

    it('sends empty string for memo when memo is whitespace only', async () => {
      const { form, submit } = useIncomingSecret();
      form.value.secret = 'the secret';
      form.value.recipientId = 'hash123';
      form.value.memo = '   ';

      await submit();

      expect(mockIncomingStore.createIncomingSecret).toHaveBeenCalledWith(
        expect.objectContaining({ memo: '' })
      );
    });
  });

  describe('loadConfig()', () => {
    it('calls incomingStore.loadConfig', async () => {
      mockIncomingStore.loadConfig = vi.fn().mockResolvedValue(undefined);
      vi.mocked(useIncomingStore).mockReturnValue(mockIncomingStore as any);

      const { loadConfig } = useIncomingSecret();
      await loadConfig();

      expect(mockIncomingStore.loadConfig).toHaveBeenCalled();
    });

    it('sets configError on incomingStore when loadConfig throws', async () => {
      mockIncomingStore.loadConfig = vi.fn().mockRejectedValue(new Error('Network error'));
      vi.mocked(useIncomingStore).mockReturnValue(mockIncomingStore as any);

      const { loadConfig } = useIncomingSecret();
      await loadConfig();

      // configHandlerOptions.onError sets incomingStore.configError = err.message
      expect(mockIncomingStore.configError).toBe('Network error');
    });

    it('does not throw when loadConfig fails (error is handled internally)', async () => {
      mockIncomingStore.loadConfig = vi.fn().mockRejectedValue(new Error('timeout'));
      vi.mocked(useIncomingStore).mockReturnValue(mockIncomingStore as any);

      const { loadConfig } = useIncomingSecret();

      // Should not throw — useAsyncHandler catches and handles it
      await expect(loadConfig()).resolves.not.toThrow();
    });
  });
});
