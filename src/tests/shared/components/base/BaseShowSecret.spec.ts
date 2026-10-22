// src/tests/shared/components/base/BaseShowSecret.spec.ts
//
// The skeleton is for the secret fetch, not the reveal. It used to replace the
// whole page whenever a request was in flight, so every reveal unmounted the
// confirmation form: the form's is-submitting state (disabled button,
// "Submitting...") could never render, and each failed reveal handed back a
// freshly mounted form.

import BaseShowSecret from '@/shared/components/base/BaseShowSecret.vue';
import { useSecretStore } from '@/shared/stores/secretStore';
import { createTestingPinia } from '@pinia/testing';
import { flushPromises, mount } from '@vue/test-utils';
import { defineComponent, h, onMounted } from 'vue';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { captureAppLogs } from '@/tests/utils/appLogs';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (key: string) => key }),
}));

vi.mock('vue-router', async (importOriginal) => ({
  ...(await importOriginal<typeof import('vue-router')>()),
  onBeforeRouteUpdate: vi.fn(),
}));

const record = { identifier: 'abc123', has_passphrase: false, verification: true };
const details = { show_secret: false, is_owner: false };

let formMounts = 0;

// Stands in for SecretConfirmationForm: counts its mounts and exposes the
// slot props the real form binds to.
const FormProbe = defineComponent({
  props: { isLoading: Boolean, error: { type: String, default: '' } },
  emits: ['confirm'],
  setup(props, { emit }) {
    onMounted(() => formMounts++);
    return () =>
      h('div', [
        h('button', {
          'data-testid': 'probe-submit',
          disabled: props.isLoading,
          onClick: () => emit('confirm'),
        }),
        props.error ? h('p', { 'data-testid': 'probe-error' }, props.error) : null,
      ]);
  },
});

function deferred() {
  let reject!: (e: unknown) => void;
  // A reveal that is only ever rejected here: never resolves to a value.
  const promise = new Promise<never>((_resolve, rej) => {
    reject = rej;
  });
  return { promise, reject };
}

async function mountLoaded() {
  const wrapper = mount(BaseShowSecret, {
    props: { secretIdentifier: 'abc123', siteHost: 'example.com' },
    global: {
      plugins: [createTestingPinia({ createSpy: vi.fn, stubActions: true })],
      stubs: { SecretSkeleton: { template: '<div data-testid="skeleton" />' } },
    },
    slots: {
      confirmation: ({ isLoading, error, onConfirm }: Record<string, any>) =>
        h(FormProbe, { isLoading, error, onConfirm: () => onConfirm('') }),
    },
  });
  const store = useSecretStore();
  // The fetch on mount has already started against the stubbed action; settle
  // it, then load the record the way the real fetch would.
  await flushPromises();
  store.record = record as never;
  store.details = details as never;
  await flushPromises();
  return { wrapper, store };
}

describe('BaseShowSecret while a reveal is in flight', () => {
  beforeEach(() => {
    formMounts = 0;
    captureAppLogs();
  });

  it('shows the skeleton while the secret itself is loading', () => {
    // Asserted before the stubbed fetch settles: loading, and no record yet.
    const wrapper = mount(BaseShowSecret, {
      props: { secretIdentifier: 'abc123', siteHost: 'example.com' },
      global: {
        plugins: [createTestingPinia({ createSpy: vi.fn, stubActions: true })],
        stubs: { SecretSkeleton: { template: '<div data-testid="skeleton" />' } },
      },
    });

    expect(wrapper.find('[data-testid="skeleton"]').exists()).toBe(true);
  });

  it('keeps the form mounted and disabled during the reveal, and shows the error on it', async () => {
    const { wrapper, store } = await mountLoaded();
    expect(formMounts).toBe(1);

    const pending = deferred();
    store.reveal = vi.fn(() => pending.promise);
    await wrapper.find('[data-testid="probe-submit"]').trigger('click');

    expect(store.reveal).toHaveBeenCalledTimes(1);
    expect(wrapper.find('[data-testid="skeleton"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="probe-submit"]').attributes('disabled')).toBeDefined();

    pending.reject(new Error('Cannot verify when logged in'));
    await flushPromises();

    expect(formMounts).toBe(1);
    expect(wrapper.find('[data-testid="probe-submit"]').attributes('disabled')).toBeUndefined();
    expect(wrapper.find('[data-testid="probe-error"]').exists()).toBe(true);
  });
});
