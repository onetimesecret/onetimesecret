// src/tests/composables/useSecretConcealer.spec.ts

import { useSecretConcealer } from '@/shared/composables/useSecretConcealer';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { useSecretStore, type ApiMode } from '@/shared/stores/secretStore';
import { Router, useRouter } from 'vue-router';
import { createPinia, setActivePinia } from 'pinia';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { nextTick } from 'vue';

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

// Mock authStore to control authentication state. Typed boolean | null to
// match the real authStore.isAuthenticated (see authStore.ts) - null is the
// genuine "uncertain/initial" state, exercised below.
const mockAuthStore: { isAuthenticated: boolean | null } = {
  isAuthenticated: true,
};
vi.mock('@/shared/stores/authStore', () => ({
  useAuthStore: () => mockAuthStore,
  // ADR-046#rejection-disposition: useAsyncHandler reads this off the error; specs that don't
  // exercise 401s still touch the import graph, so a null-returning stub is
  // enough.
  readCoordinatorDisposition: () => null,
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
      // Partial<ReturnType<...>>, not a bare literal: useSecretStore is a
      // Pinia setup store, so its real return type carries every state ref,
      // getter and action plus Pinia's own instance methods. Typing the mock
      // this way lets the object literal include just what each test needs
      // while still keeping the mockReturnValue() call itself checked below.
      const store: Partial<ReturnType<typeof useSecretStore>> = {
        conceal: vi.fn().mockResolvedValue({ record: { receipt: { key: 'test' } } }),
        generate: vi.fn().mockResolvedValue({ record: { receipt: { key: 'test' } } }),
        setApiMode: vi.fn(),
      };
      vi.mocked(useSecretStore).mockReturnValue(store as ReturnType<typeof useSecretStore>);
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
        receipt: {
          identifier: 'test-receipt-key',
        },
      },
    };

    beforeEach(() => {
      const store: Partial<ReturnType<typeof useSecretStore>> = {
        conceal: vi.fn().mockResolvedValue(mockResponse),
        generate: vi.fn().mockResolvedValue(mockResponse),
        setApiMode: vi.fn(),
      };
      vi.mocked(useSecretStore).mockReturnValue(store as ReturnType<typeof useSecretStore>);
    });

    it.skip('handles successful secret sharing', async () => {
      const { submit, isSubmitting } = useSecretConcealer({
        onSuccess: async (response) => {
          mockRouter.push({
            name: 'Receipt link',
            params: { receiptIdentifier: response.record.receipt.identifier },
          });
        },
      });

      // Execute
      await submit('conceal');

      // Verify
      expect(isSubmitting.value).toBe(false);
      expect(mockRouter.push).toHaveBeenCalledWith({
        name: 'Receipt link',
        params: { receiptIdentifier: 'test-receipt-key' },
      });
    });

    it('handles validation errors', async () => {
      const store: Partial<ReturnType<typeof useSecretStore>> = {
        conceal: vi.fn().mockRejectedValue(new Error('Validation failed')),
        generate: vi.fn().mockRejectedValue(new Error('Validation failed')),
        setApiMode: vi.fn(),
      };
      vi.mocked(useSecretStore).mockReturnValue(store as ReturnType<typeof useSecretStore>);

      const { submit, isSubmitting } = useSecretConcealer();

      await submit('conceal');

      expect(isSubmitting.value).toBe(false);
      expect(mockRouter.push).not.toHaveBeenCalled();
    });
  });

  describe('form mode handling', () => {
    beforeEach(() => {
      const store: Partial<ReturnType<typeof useSecretStore>> = {
        conceal: vi.fn().mockResolvedValue({ record: { receipt: { key: 'test' } } }),
        generate: vi.fn().mockResolvedValue({ record: { receipt: { key: 'test' } } }),
        setApiMode: vi.fn(),
      };
      vi.mocked(useSecretStore).mockReturnValue(store as ReturnType<typeof useSecretStore>);
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

    it('sends the form display_type with a conceal payload', async () => {
      const store: Partial<ReturnType<typeof useSecretStore>> = {
        conceal: vi.fn().mockResolvedValue({ record: { receipt: { key: 'test' } } }),
        generate: vi.fn(),
        setApiMode: vi.fn(),
      };
      vi.mocked(useSecretStore).mockReturnValue(store as ReturnType<typeof useSecretStore>);

      const { operations, submit } = useSecretConcealer();
      operations.updateField('secret', '# hello');
      operations.updateField('display_type', 'markdown');

      await submit('conceal');

      expect(store.conceal).toHaveBeenCalledWith(
        expect.objectContaining({ kind: 'conceal', secret: '# hello', display_type: 'markdown' })
      );
    });

    it('defaults display_type to text on conceal', async () => {
      const store: Partial<ReturnType<typeof useSecretStore>> = {
        conceal: vi.fn().mockResolvedValue({ record: { receipt: { key: 'test' } } }),
        generate: vi.fn(),
        setApiMode: vi.fn(),
      };
      vi.mocked(useSecretStore).mockReturnValue(store as ReturnType<typeof useSecretStore>);

      const { form, operations, submit } = useSecretConcealer();
      expect(form.display_type).toBe('text');
      operations.updateField('secret', 'hello');

      await submit('conceal');

      expect(store.conceal).toHaveBeenCalledWith(expect.objectContaining({ display_type: 'text' }));
    });

    it('does not send display_type with a generate payload', async () => {
      const store: Partial<ReturnType<typeof useSecretStore>> = {
        conceal: vi.fn(),
        generate: vi.fn().mockResolvedValue({ record: { receipt: { key: 'test' } } }),
        setApiMode: vi.fn(),
      };
      vi.mocked(useSecretStore).mockReturnValue(store as ReturnType<typeof useSecretStore>);

      const { operations, submit } = useSecretConcealer();
      operations.updateField('display_type', 'markdown');

      await submit('generate');

      expect(store.generate).toHaveBeenCalledTimes(1);
      const payload = vi.mocked(store.generate!).mock.calls[0][0] as Record<string, unknown>;
      expect(payload.kind).toBe('generate');
      expect('display_type' in payload).toBe(false);
    });

    it('puts display_type back to text when a refresh turns Markdown off', async () => {
      const bootstrapStore = useBootstrapStore();
      bootstrapStore.$patch({ features: { markdown: true } });

      const { form, operations } = useSecretConcealer();
      operations.updateField('display_type', 'markdown');
      await nextTick();
      expect(form.display_type).toBe('markdown');

      bootstrapStore.$patch({ features: { markdown: false } });
      await nextTick();

      expect(form.display_type).toBe('text');
    });

    it.each(['conceal', 'generate'] as const)(
      'applies the selected organization to %s, including a switch while editing',
      async kind => {
        const bootstrap = useBootstrapStore();
        bootstrap.$patch({
          authenticated: true,
          organization: { objid: 'a', extid: 'on-a', display_name: 'A', is_default: true },
          secret_options: { default_ttl: 2592000, ttl_options: [60, 604800, 2592000] },
        });
        const organizations = useOrganizationStore();
        const original = organizations.currentOrganization!;
        const { form, operations, submit, validation } = useSecretConcealer();
        operations.updateField('secret', 'content');
        operations.updateField('recipient', 'one@sub.example.com');
        organizations.setCurrentOrganization({
          ...original, objid: 'b', extid: 'on-b', sharing_policy: {
            passphrase_required: true, max_ttl: 604800,
            recipient_email_mode: 'restricted', recipient_email_domains: ['example.com'],
          },
        });
        expect(form.ttl).toBe(604800);
        operations.updateField('passphrase', '   ');
        await submit(kind);
        expect(validation.errors.has('passphrase')).toBe(true);
        expect(validation.errors.has('recipient')).toBe(true);
        expect(useSecretStore()[kind]).not.toHaveBeenCalled();

        operations.updateField('passphrase', 'some passphrase');
        operations.updateField('recipient', 'first@example.com, second@example.com');
        await submit(kind);
        expect(validation.errors.has('recipient')).toBe(true);
        expect(useSecretStore()[kind]).not.toHaveBeenCalled();

        operations.updateField('recipient', 'one@EXAMPLE.com');
        await submit(kind);
        expect(useSecretStore()[kind]).toHaveBeenCalledWith(expect.objectContaining({
          recipient: 'one@EXAMPLE.com', ttl: 604800,
        }));
        organizations.setCurrentOrganization({
          ...original, sharing_policy: {
            passphrase_required: false, max_ttl: 60,
            recipient_email_mode: 'disabled', recipient_email_domains: [],
          },
        });
        expect(form.ttl).toBe(60);
        expect(form.recipient).toBe('');
      }
    );

    it('rejects generate submission with a malformed recipient email', async () => {
      const store: Partial<ReturnType<typeof useSecretStore>> = {
        conceal: vi.fn(),
        generate: vi.fn(),
        setApiMode: vi.fn(),
      };
      vi.mocked(useSecretStore).mockReturnValue(store as ReturnType<typeof useSecretStore>);

      const { form, operations, submit } = useSecretConcealer();
      operations.updateField('recipient', 'not-an-email');

      await submit('generate');

      expect(form.recipient).toBe('not-an-email');
      expect(store.generate).not.toHaveBeenCalled();
    });

    // useSecretForm checks the typed address against the selected policy:
    // the text after the last "@", lower-cased, must equal a listed domain.
    // The server sends the listed domains already normalized (lower-case
    // A-labels). The error message tells the policy check from the schema's
    // email check, which runs first and suppresses the policy check.
    describe('recipient domain restriction', () => {
      // The i18n mock renders keys.
      const restricted = 'web.secrets.error_recipient_restricted';
      const submitted = 'submitted';
      const invalidEmail = 'invalid email';

      function selectPolicy(mode: 'restricted' | 'disabled' | 'unrestricted', domains: string[] = []) {
        const bootstrap = useBootstrapStore();
        bootstrap.$patch({
          authenticated: true,
          organization: { objid: 'a', extid: 'on-a', display_name: 'A', is_default: true },
          secret_options: { default_ttl: 3600, ttl_options: [60, 3600] },
        });
        const organizations = useOrganizationStore();
        organizations.setCurrentOrganization({
          ...organizations.currentOrganization!, sharing_policy: {
            passphrase_required: false, max_ttl: null,
            recipient_email_mode: mode, recipient_email_domains: domains,
          },
        });
      }

      async function outcome(kind: 'conceal' | 'generate', recipient: string) {
        const { operations, submit, validation } = useSecretConcealer();
        operations.updateField('secret', 'content');
        operations.updateField('recipient', recipient);
        await submit(kind);
        const store = useSecretStore();
        if (vi.mocked(store[kind]).mock.calls.length) {
          expect(store[kind]).toHaveBeenCalledWith(expect.objectContaining({ recipient }));
          return submitted;
        }
        const message = validation.errors.get('recipient');
        return message === restricted ? restricted : message ? invalidEmail : 'no recipient error';
      }

      describe.each(['conceal', 'generate'] as const)('%s', kind => {
        it.each([
          [['example.com'], 'user@example.com', submitted],
          [['example.com'], 'USER@Example.COM', submitted],
          [['example.com'], 'user@eng.example.com', restricted],
          [['example.com'], 'user@notexample.com', restricted],
          [['eng.example.com'], 'user@eng.example.com', submitted],
          [['eng.example.com'], 'user@example.com', restricted],
          [['example.com', 'eng.example.com'], 'user@eng.example.com', submitted],
          [['example.com', 'eng.example.com'], 'user@ops.example.com', restricted],
          [['xn--bcher-kva.example'], 'user@xn--bcher-kva.example', submitted],
          [['xn--bcher-kva.example'], 'user@XN--BCHER-KVA.example', submitted],
          [['xn--bcher-kva.example'], 'user@bucher.example', restricted],
          // Malformed addresses fail the schema email check before the policy.
          [['example.com'], 'a@b@example.com', invalidEmail],
          [['example.com'], '@example.com', invalidEmail],
          [['example.com'], 'user@', invalidEmail],
          [['example.com'], 'user@example.com.', invalidEmail],
          [['example.com'], 'user@-bad.example.com', invalidEmail],
          [['example.com'], 'userexample.com', invalidEmail],
        ])('restricted to %j: %s is %s', async (domains, recipient, expected) => {
          selectPolicy('restricted', domains);
          expect(await outcome(kind, recipient)).toBe(expected);
        });

        // The server accepts the Unicode spelling of a listed IDN (its
        // comparison key is the stored A-label). The frontend refuses it
        // as an invalid email before the policy check runs. Reported as a
        // frontend/server divergence; remove .fails once they agree.
        it.fails('restricted to an IDN: the Unicode spelling is submitted', async () => {
          selectPolicy('restricted', ['xn--bcher-kva.example']);
          expect(await outcome(kind, 'user@bücher.example')).toBe(submitted);
        });

        it('refuses any address when recipient email is disabled', async () => {
          selectPolicy('disabled');
          expect(await outcome(kind, 'user@example.com')).toBe(restricted);
        });

        it('allows any valid address when unrestricted', async () => {
          selectPolicy('unrestricted');
          expect(await outcome(kind, 'user@unlisted.test')).toBe(submitted);
          vi.mocked(useSecretStore()[kind]).mockClear();
          expect(await outcome(kind, 'a@b@example.com')).toBe(invalidEmail);
        });
      });
    });
  });

  describe('API mode selection', () => {
    let mockSetApiMode: ReturnType<typeof vi.fn<(mode: ApiMode) => void>>;

    beforeEach(() => {
      mockSetApiMode = vi.fn<(mode: ApiMode) => void>();
      const store: Partial<ReturnType<typeof useSecretStore>> = {
        conceal: vi.fn().mockResolvedValue({ record: { receipt: { key: 'test' } } }),
        generate: vi.fn().mockResolvedValue({ record: { receipt: { key: 'test' } } }),
        setApiMode: mockSetApiMode,
      };
      vi.mocked(useSecretStore).mockReturnValue(store as ReturnType<typeof useSecretStore>);
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
