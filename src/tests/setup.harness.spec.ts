// src/tests/setup.harness.spec.ts
//
// Pins the wiring `setupTestPinia()` promises, so store specs exercise what the
// app runs (src/plugins/core/appInitializer.ts) rather than a look-alike:
//   - stores run `init()` on creation (the real auto-init plugin),
//   - one axios instance and ONE mock adapter, however a spec reaches them,
//   - Vue's provide/inject is real; only an unprovided 'api' falls back.

import { useIncomingStore } from '@/shared/stores/incomingStore';
import { useLocalReceiptStore } from '@/shared/stores/localReceiptStore';
import { useReceiptListStore } from '@/shared/stores/receiptListStore';
import { mount } from '@vue/test-utils';
import { describe, expect, it } from 'vitest';
import { defineComponent, h, inject, provide } from 'vue';

import { setupTestPinia } from './setup';
import { createSharedApiInstance, getGlobalAxiosMock } from './setup-stores';

const EMPTY_LIST = { records: [], details: {}, count: 0 };

describe('setupTestPinia harness', () => {
  describe('auto-init', () => {
    it('also runs init() under the global pinia, for specs that never call setupTestPinia', () => {
      // setup-stores.ts installs this pinia in a global beforeEach.
      expect(useLocalReceiptStore().isInitialized).toBe(true);
      expect(useIncomingStore().isInitialized).toBe(true);
    });

    it('runs init() on stores created afterwards, as the app does', async () => {
      await setupTestPinia();

      expect(useLocalReceiptStore().isInitialized).toBe(true);
      expect(useIncomingStore().isInitialized).toBe(true);
    });

    it('adds nothing to the store but what the store defines', async () => {
      await setupTestPinia();

      // The former stub plugin leaked an `install` property onto every store.
      expect('install' in useReceiptListStore()).toBe(false);
    });

    it('leaves init() to the spec when autoInit is false', async () => {
      await setupTestPinia({ autoInit: false });

      expect(useLocalReceiptStore().isInitialized).toBe(false);
      expect(useIncomingStore().isInitialized).toBe(false);
    });
  });

  describe('api client', () => {
    it('hands stores the instance it returns', async () => {
      const { api, axiosMock } = await setupTestPinia();
      axiosMock!.onGet('/api/v3/receipt/recent').reply(200, EMPTY_LIST);

      await useReceiptListStore().fetchList();

      expect(api).toBe(createSharedApiInstance());
      expect(axiosMock!.history.get).toHaveLength(1);
    });

    it('returns the same adapter from getGlobalAxiosMock()', async () => {
      const { axiosMock } = await setupTestPinia();

      expect(getGlobalAxiosMock()).toBe(axiosMock);

      // A handler registered through the global accessor is the one a store hits.
      getGlobalAxiosMock().onGet('/api/v3/receipt/recent').reply(200, EMPTY_LIST);
      const store = useReceiptListStore();
      await store.fetchList();
      expect(store.records).toEqual([]);
    });

    it('does not carry handlers or history into the next setup', async () => {
      const first = await setupTestPinia();
      first.axiosMock!.onGet('/api/v3/receipt/recent').reply(200, EMPTY_LIST);
      await useReceiptListStore().fetchList();

      const second = await setupTestPinia();

      expect(second.axiosMock).not.toBe(first.axiosMock);
      expect(second.axiosMock!.history.get).toHaveLength(0);
      await expect(useReceiptListStore().fetchList()).rejects.toMatchObject({
        response: { status: 404 },
      });
    });
  });

  describe('provide / inject', () => {
    const Child = defineComponent({
      setup() {
        const provided = inject<string>('probe');
        const fallback = inject<string>('absent', 'default-value');
        const api = inject<unknown>('api');
        return () => h('div', { 'data-api': String(api === createSharedApiInstance()) }, [
          `${provided}|${fallback}`,
        ]);
      },
    });

    it('resolves a value provided by an ancestor, and honours defaults', () => {
      const Parent = defineComponent({
        setup() {
          provide('probe', 'from-parent');
          return () => h(Child);
        },
      });

      const wrapper = mount(Parent);

      expect(wrapper.text()).toBe('from-parent|default-value');
      // Nothing provides 'api' here: the shared instance stands in.
      expect(wrapper.find('div').attributes('data-api')).toBe('true');
    });

    it("prefers a provided 'api' over the shared fallback", () => {
      const own = { marker: 'own-api' };
      const wrapper = mount(Child, { global: { provide: { api: own, probe: 'x' } } });

      expect(wrapper.find('div').attributes('data-api')).toBe('false');
    });
  });
});
