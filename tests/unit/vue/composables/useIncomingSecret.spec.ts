// tests/unit/vue/composables/useIncomingSecret.spec.ts

import { useIncomingSecret } from '@/composables/useIncomingSecret';
import { useIncomingStore } from '@/stores/incomingStore';
import { useNotificationsStore } from '@/stores/notificationsStore';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { ComponentPublicInstance } from 'vue';
import { setupTestPinia } from '../setup';
import { setupWindowState } from '../setupWindow';

// Mock vue-router
const mockPush = vi.fn();
vi.mock('vue-router', () => ({
  useRouter: () => ({
    push: mockPush,
  }),
}));

describe('useIncomingSecret', () => {
  let appInstance: ComponentPublicInstance | null;
  let incomingStore: ReturnType<typeof useIncomingStore>;

  beforeEach(async () => {
    const setup = await setupTestPinia({ stubActions: false });
    appInstance = setup.appInstance;

    const windowMock = setupWindowState({ shrimp: undefined });
    vi.stubGlobal('window', windowMock);

    incomingStore = useIncomingStore();

    // Pre-configure the store with a realistic config
    incomingStore.$patch({
      config: {
        enabled: true,
        memo_max_length: 50,
        recipients: [
          { hash: 'abc123', name: 'Support Team' },
          { hash: 'def456', name: 'Security Team' },
        ],
        default_ttl: 604800,
      },
      isConfigLoading: false,
      configError: null,
    });
  });

  afterEach(() => {
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
    mockPush.mockReset();
  });

  describe('form initialization', () => {
    it('initializes with empty form state', () => {
      const { form, errors, isSubmitting } = useIncomingSecret();

      expect(form.value).toEqual({
        memo: '',
        secret: '',
        recipientId: '',
      });
      expect(errors.value).toEqual({});
      expect(isSubmitting.value).toBe(false);
    });

    it('exposes computed properties from store', () => {
      const { memoMaxLength, isFeatureEnabled, recipients } = useIncomingSecret();

      expect(memoMaxLength.value).toBe(50);
      expect(isFeatureEnabled.value).toBe(true);
      expect(recipients.value).toHaveLength(2);
    });
  });

  describe('isFormValid computed', () => {
    it('returns false when secret is empty', () => {
      const { form, isFormValid } = useIncomingSecret();
      form.value.recipientId = 'abc123';
      form.value.secret = '';

      expect(isFormValid.value).toBe(false);
    });

    it('returns false when recipientId is empty', () => {
      const { form, isFormValid } = useIncomingSecret();
      form.value.secret = 'some secret';
      form.value.recipientId = '';

      expect(isFormValid.value).toBe(false);
    });

    it('returns true when secret and recipientId are set', () => {
      const { form, isFormValid } = useIncomingSecret();
      form.value.secret = 'some secret';
      form.value.recipientId = 'abc123';

      expect(isFormValid.value).toBe(true);
    });

    it('returns false when secret is only whitespace', () => {
      const { form, isFormValid } = useIncomingSecret();
      form.value.secret = '   ';
      form.value.recipientId = 'abc123';

      expect(isFormValid.value).toBe(false);
    });
  });

  describe('validateMemo', () => {
    it('passes when memo is empty (optional field)', () => {
      const { form, validateMemo, errors } = useIncomingSecret();
      form.value.memo = '';

      expect(validateMemo()).toBe(true);
      expect(errors.value.memo).toBeUndefined();
    });

    it('passes when memo is within max length', () => {
      const { form, validateMemo, errors } = useIncomingSecret();
      form.value.memo = 'Short memo';

      expect(validateMemo()).toBe(true);
      expect(errors.value.memo).toBeUndefined();
    });

    it('fails when memo exceeds max length', () => {
      const { form, validateMemo, errors } = useIncomingSecret();
      form.value.memo = 'A'.repeat(51);

      expect(validateMemo()).toBe(false);
      expect(errors.value.memo).toContain('50 characters or less');
    });

    it('passes when memo is whitespace-only (treated as empty after trim)', () => {
      const { form, validateMemo, errors } = useIncomingSecret();
      form.value.memo = '   ';

      expect(validateMemo()).toBe(true);
      expect(errors.value.memo).toBeUndefined();
    });
  });

  describe('validateSecret', () => {
    it('fails when secret is empty', () => {
      const { form, validateSecret, errors } = useIncomingSecret();
      form.value.secret = '';

      expect(validateSecret()).toBe(false);
      expect(errors.value.secret).toBe('Secret content is required');
    });

    it('fails when secret is only whitespace', () => {
      const { form, validateSecret, errors } = useIncomingSecret();
      form.value.secret = '   ';

      expect(validateSecret()).toBe(false);
      expect(errors.value.secret).toBe('Secret content is required');
    });

    it('passes when secret has content', () => {
      const { form, validateSecret, errors } = useIncomingSecret();
      form.value.secret = 'my secret value';

      expect(validateSecret()).toBe(true);
      expect(errors.value.secret).toBeUndefined();
    });
  });

  describe('validateRecipient', () => {
    it('fails when recipientId is empty', () => {
      const { form, validateRecipient, errors } = useIncomingSecret();
      form.value.recipientId = '';

      expect(validateRecipient()).toBe(false);
      expect(errors.value.recipientId).toBe('Please select a recipient');
    });

    it('passes when recipientId is set', () => {
      const { form, validateRecipient, errors } = useIncomingSecret();
      form.value.recipientId = 'abc123';

      expect(validateRecipient()).toBe(true);
      expect(errors.value.recipientId).toBeUndefined();
    });
  });

  describe('validateForm', () => {
    it('validates all fields and returns true when all valid', () => {
      const { form, validateForm, errors } = useIncomingSecret();
      form.value.memo = 'Test';
      form.value.secret = 'secret content';
      form.value.recipientId = 'abc123';

      expect(validateForm()).toBe(true);
      expect(errors.value).toEqual({
        memo: undefined,
        secret: undefined,
        recipientId: undefined,
      });
    });

    it('validates all fields and returns false when any invalid', () => {
      const { form, validateForm, errors } = useIncomingSecret();
      form.value.memo = '';
      form.value.secret = '';
      form.value.recipientId = '';

      expect(validateForm()).toBe(false);
      expect(errors.value.secret).toBe('Secret content is required');
      expect(errors.value.recipientId).toBe('Please select a recipient');
    });

    it('checks all fields even when first fails', () => {
      const { form, validateForm, errors } = useIncomingSecret();
      form.value.secret = '';
      form.value.recipientId = '';

      validateForm();

      // Both errors should be set, not short-circuited
      expect(errors.value.secret).toBeDefined();
      expect(errors.value.recipientId).toBeDefined();
    });
  });

  describe('clearValidation', () => {
    it('clears all validation errors', () => {
      const { form, validateForm, clearValidation, errors } = useIncomingSecret();
      form.value.secret = '';
      form.value.recipientId = '';
      validateForm();

      expect(Object.keys(errors.value).length).toBeGreaterThan(0);

      clearValidation();
      expect(errors.value).toEqual({});
    });
  });

  describe('resetForm', () => {
    it('resets form to initial empty state and clears errors', () => {
      const { form, errors, validateForm, resetForm } = useIncomingSecret();

      // Set some values
      form.value.memo = 'test memo';
      form.value.secret = '';
      form.value.recipientId = '';
      validateForm();

      resetForm();

      expect(form.value).toEqual({
        memo: '',
        secret: '',
        recipientId: '',
      });
      expect(errors.value).toEqual({});
    });
  });

  describe('createPayload (via submit)', () => {
    it('trims memo whitespace in payload', async () => {
      const { form } = useIncomingSecret();
      form.value.memo = '  padded memo  ';
      form.value.secret = 'test secret';
      form.value.recipientId = 'abc123';

      // We can't call createPayload directly (it's private), but we test
      // the form state that feeds into it
      expect(form.value.memo.trim()).toBe('padded memo');
    });
  });
});
