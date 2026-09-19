// src/tests/components/UnsavedInputGuardAdoption.spec.ts
//
// #4465: views whose input a forced page load could discard register the
// shared beforeunload guard ONLY while that input exists (ADR-046).

import SecretForm from '@/apps/secret/components/form/SecretForm.vue';
import DomainBrand from '@/apps/workspace/domains/DomainBrand.vue';
import { createTestingPinia } from '@pinia/testing';
import { mount, shallowMount } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { nextTick, reactive, ref } from 'vue';

const secretForm = reactive({ secret: '', passphrase: '', ttl: 300, share_domain: '', recipient: '' });
const hasUnsavedChanges = ref(false);

vi.mock('@/shared/composables/useSecretConcealer', () => ({
  useSecretConcealer: vi.fn(() => ({
    form: secretForm,
    validation: { errors: new Map() },
    operations: { updateField: vi.fn(), reset: vi.fn() },
    isSubmitting: false,
    submit: vi.fn(),
  })),
}));

vi.mock('@/shared/composables/useDomainContext', () => ({
  useDomainContext: vi.fn(() => ({
    currentContext: { value: { domain: 'example.com', displayName: 'example.com', isCanonical: true } },
    isContextActive: { value: false },
    availableDomains: { value: [] },
    hasMultipleContexts: { value: false },
    setContext: vi.fn(),
    resetContext: vi.fn(),
  })),
}));

vi.mock('@/shared/composables/usePrivacyOptions', () => ({
  usePrivacyOptions: vi.fn(() => ({
    state: { passphraseVisibility: false },
    lifetimeOptions: { value: [] },
    updatePassphrase: vi.fn(),
    updateTtl: vi.fn(),
    updateRecipient: vi.fn(),
    togglePassphraseVisibility: vi.fn(),
  })),
}));

vi.mock('@/shared/composables/useBranding', () => ({
  useBranding: vi.fn(() => ({
    isLoading: ref(false),
    error: ref(null),
    brandSettings: ref({}),
    logoImage: ref(null),
    faviconImage: ref(null),
    previewI18n: ref(null),
    hasUnsavedChanges,
    isInitialized: ref(false),
    initialize: vi.fn(),
    saveBranding: vi.fn(),
    handleLogoUpload: vi.fn(),
    removeLogo: vi.fn(),
    refreshFavicon: vi.fn(),
    handleFaviconUpload: vi.fn(),
    removeFavicon: vi.fn(),
  })),
}));

vi.mock('@/shared/composables/useDomain', () => ({
  useDomain: vi.fn(() => ({ domain: ref(null), initialize: vi.fn() })),
}));

vi.mock('vue-router', () => ({
  useRouter: vi.fn(() => ({ push: vi.fn() })),
  useRoute: vi.fn(() => ({ params: {}, query: {} })),
  onBeforeRouteLeave: vi.fn(),
}));

vi.mock('vue-i18n', async (importOriginal) => ({
  ...(await importOriginal<typeof import('vue-i18n')>()),
  useI18n: vi.fn(() => ({ t: (key: string) => key })),
}));

describe('beforeunload guard adoption (#4465)', () => {
  let add: ReturnType<typeof vi.spyOn>;
  let remove: ReturnType<typeof vi.spyOn>;

  const registered = () =>
    add.mock.calls.filter(([type]) => type === 'beforeunload').length -
    remove.mock.calls.filter(([type]) => type === 'beforeunload').length;

  const pinia = () =>
    createTestingPinia({
      createSpy: vi.fn,
      initialState: {
        bootstrap: {
          ui: { capabilities: {} },
          secret_options: {
            passphrase: { required: false, minimum_length: 8, enforce_complexity: false },
          },
        },
      },
    });

  beforeEach(() => {
    secretForm.secret = '';
    hasUnsavedChanges.value = false;
    add = vi.spyOn(window, 'addEventListener');
    remove = vi.spyOn(window, 'removeEventListener');
  });

  afterEach(() => vi.restoreAllMocks());

  describe('secret creation form', () => {
    it('has no listener while the secret is empty or whitespace', async () => {
      const wrapper = mount(SecretForm, { props: { enabled: true }, global: { plugins: [pinia()] } });
      expect(registered()).toBe(0);

      secretForm.secret = '   \n';
      await nextTick();

      expect(registered()).toBe(0);
      wrapper.unmount();
    });

    it('registers while content is typed and removes it once submitted or cleared', async () => {
      const wrapper = mount(SecretForm, { props: { enabled: true }, global: { plugins: [pinia()] } });

      secretForm.secret = 'hunter2';
      expect(registered()).toBe(1);

      // What operations.reset() does after a successful submit.
      secretForm.secret = '';
      expect(registered()).toBe(0);
      wrapper.unmount();
    });

    it('removes it when the form unmounts with content still in it', () => {
      const wrapper = mount(SecretForm, { props: { enabled: true }, global: { plugins: [pinia()] } });
      secretForm.secret = 'hunter2';

      wrapper.unmount();

      expect(registered()).toBe(0);
    });
  });

  describe('DomainBrand (moved onto the shared guard)', () => {
    const mountBrand = () =>
      shallowMount(DomainBrand, {
        props: { extid: 'dm-1', orgid: 'on-1' },
        global: { plugins: [pinia()] },
      });

    it('no longer installs a standing listener on mount', () => {
      const wrapper = mountBrand();

      expect(registered()).toBe(0);
      wrapper.unmount();
    });

    it('registers only while there are unsaved changes', () => {
      const wrapper = mountBrand();

      hasUnsavedChanges.value = true;
      expect(registered()).toBe(1);

      hasUnsavedChanges.value = false;
      expect(registered()).toBe(0);
      wrapper.unmount();
    });
  });
});
