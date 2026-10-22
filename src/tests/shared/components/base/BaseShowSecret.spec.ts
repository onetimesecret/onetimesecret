// src/tests/shared/components/base/BaseShowSecret.spec.ts
//
// The skeleton is for the secret fetch, not the reveal. It used to replace the
// whole page whenever a request was in flight, so every reveal unmounted the
// confirmation form: the form's is-submitting state (disabled button,
// "Submitting...") could never render, and each failed reveal handed back a
// freshly mounted form.
//
// The secret store is a singleton, so a visitor who opens a second secret link
// in the same tab mounts this component with the first secret's record still
// in the store. The fetch has to put that record out of sight, or the previous
// secret shows under the new URL: until the response arrives, and for good
// when the response is a 404.

import BaseShowSecret from '@/shared/components/base/BaseShowSecret.vue';
import { useSecretStore } from '@/shared/stores/secretStore';
import { createTestingPinia } from '@pinia/testing';
import { flushPromises, mount } from '@vue/test-utils';
import axios from 'axios';
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

const skeletonStub = { SecretSkeleton: { template: '<div data-testid="skeleton" />' } };

const slots = {
  confirmation: ({ isLoading, error, onConfirm }: Record<string, any>) =>
    h(FormProbe, { isLoading, error, onConfirm: () => onConfirm('') }),
  reveal: ({ record }: Record<string, any>) =>
    h('p', { 'data-testid': 'revealed' }, record.identifier),
  unknown: () => h('p', { 'data-testid': 'unknown' }),
};

function deferred<T = never>() {
  let resolve!: (value: T) => void;
  let reject!: (e: unknown) => void;
  const promise = new Promise<T>((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
}

// The 404 the API answers for a consumed, expired or unknown secret.
function notFound() {
  return new axios.AxiosError('Not Found', '404', undefined, undefined, {
    status: 404,
    statusText: 'Not Found',
    data: { error: 'Not Found' },
    headers: {},
    config: {} as any,
  });
}

async function mountLoaded() {
  const wrapper = mount(BaseShowSecret, {
    props: { secretIdentifier: 'abc123', siteHost: 'example.com' },
    global: {
      plugins: [createTestingPinia({ createSpy: vi.fn, stubActions: true })],
      stubs: skeletonStub,
    },
    slots,
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

// Mounts the view for `secretIdentifier` with a previous, revealed secret
// still in the store and its fetch pending. Real store actions, so the fetch
// can clear what the last page left behind; only the request is replaced.
async function mountAfterPrevious(secretIdentifier: string) {
  const pinia = createTestingPinia({ createSpy: vi.fn, stubActions: false });
  const store = useSecretStore(pinia);
  store.record = { ...record, identifier: 'previous' } as never;
  store.details = { show_secret: true, is_owner: false } as never;
  // Typed like the other overrides: a Promise<never> fits any return type.
  // Completion is signalled with resolve(undefined as never) after the test
  // has put the record in the store by hand.
  const fetching = deferred();
  store.fetch = vi.fn(() => fetching.promise);

  const wrapper = mount(BaseShowSecret, {
    props: { secretIdentifier, siteHost: 'example.com' },
    global: { plugins: [pinia], stubs: skeletonStub },
    slots,
  });
  await flushPromises();
  expect(store.fetch).toHaveBeenCalledWith(secretIdentifier);
  return { wrapper, store, fetching };
}

describe('BaseShowSecret while the secret is loading', () => {
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
        stubs: skeletonStub,
      },
    });

    expect(wrapper.find('[data-testid="skeleton"]').exists()).toBe(true);
  });

  it('shows the skeleton, not the previous secret, while another secret loads', async () => {
    const { wrapper, store, fetching } = await mountAfterPrevious('next');

    expect(wrapper.find('[data-testid="revealed"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="probe-submit"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="skeleton"]').exists()).toBe(true);

    store.record = { ...record, identifier: 'next' } as never;
    store.details = details as never;
    fetching.resolve(undefined as never);
    await flushPromises();

    expect(wrapper.find('[data-testid="skeleton"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="revealed"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="probe-submit"]').exists()).toBe(true);
  });

  it('shows the unknown view, not the previous secret, when the other secret is gone', async () => {
    const { wrapper, fetching } = await mountAfterPrevious('gone');

    fetching.reject(notFound());
    await flushPromises();

    expect(wrapper.find('[data-testid="revealed"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="unknown"]').exists()).toBe(true);
  });
});

describe('BaseShowSecret while a reveal is in flight', () => {
  beforeEach(() => {
    formMounts = 0;
    captureAppLogs();
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
