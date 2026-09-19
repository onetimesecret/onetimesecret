// src/tests/apps/workspace/dashboard/passiveRefresh.spec.ts
//
// Which dashboard requests declare themselves passive (RISK-2026-09-19-04).
//
// DashboardRecent and RecentSecretsTable both load the receipt list when the
// person arrives (navigation: an ordinary request) and then keep it fresh on a
// 5-minute timer and on tab-visibility changes (nobody asked: passive). The
// real components, composables, store and request interceptor run here, and
// the assertion is the header on the outgoing request.

import RecentSecretsTable from '@/apps/secret/components/RecentSecretsTable.vue';
import DashboardRecent from '@/apps/workspace/dashboard/DashboardRecent.vue';
import { requestInterceptor, SESSION_ACTIVITY_HEADER } from '@/plugins/axios/interceptors';
import { _resetForTesting } from '@/services/bootstrap.service';
import { BACKGROUND_REFRESH_INTERVAL_MS } from '@/shared/composables/useBackgroundRefresh';
import { useAuthStore } from '@/shared/stores/authStore';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { toWire } from '@/tests/fixtures/bootstrap-wire';
import { authenticatedBootstrap } from '@/tests/fixtures/bootstrap.fixture';
import { mount, type VueWrapper } from '@vue/test-utils';
import type { AxiosInstance } from 'axios';
import type AxiosMockAdapter from 'axios-mock-adapter';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { Component } from 'vue';

import { createTestI18n, setupTestPinia } from '../../../setup';

const RECENT = '/api/v3/receipt/recent';
const BOOTSTRAP_KEY = '__BOOTSTRAP_ME__';

describe('dashboard receipt refreshes: active vs passive', () => {
  let api: AxiosInstance;
  let axiosMock: AxiosMockAdapter;
  let pinia: Awaited<ReturnType<typeof setupTestPinia>>['pinia'];
  let interceptorId: number;
  let wrapper: VueWrapper | null = null;

  /** `X-Session-Activity` of each receipt-list GET so far, in order. */
  const declarations = () =>
    axiosMock.history.get
      .filter((request) => request.url === RECENT)
      .map(
        (request) =>
          (request.headers as Record<string, unknown> | undefined)?.[SESSION_ACTIVITY_HEADER]
      );

  const setVisibility = (state: 'visible' | 'hidden') => {
    Object.defineProperty(document, 'visibilityState', { value: state, configurable: true });
    document.dispatchEvent(new Event('visibilitychange'));
  };

  async function mountAuthenticated(component: Component) {
    wrapper = mount(component, {
      global: {
        plugins: [pinia, createTestI18n()],
        provide: { api },
        stubs: {
          SecretReceiptTable: true,
          SecretLinksTable: true,
          TableSkeleton: true,
          EmptyState: true,
          ErrorDisplay: true,
          InlineToast: true,
          OIcon: true,
        },
      },
    });
    await vi.advanceTimersByTimeAsync(0);
  }

  beforeEach(async () => {
    _resetForTesting();
    (window as unknown as Record<string, unknown>)[BOOTSTRAP_KEY] = toWire(authenticatedBootstrap);

    const setup = await setupTestPinia();
    api = setup.api;
    axiosMock = setup.axiosMock as AxiosMockAdapter;
    pinia = setup.pinia;
    // The harness instance is bare; the app's client carries this interceptor
    // (src/api/index.ts), and it is what writes the header.
    interceptorId = api.interceptors.request.use(requestInterceptor);

    axiosMock.onGet(RECENT).reply(200, { records: [], details: {}, count: 0 });
    Object.defineProperty(document, 'visibilityState', { value: 'visible', configurable: true });

    vi.useFakeTimers(); // before the stores: authStore.init() schedules its interval
    useBootstrapStore();
    expect(useAuthStore().isFullyAuthenticated).toBe(true);
  });

  afterEach(() => {
    wrapper?.unmount();
    wrapper = null;
    useAuthStore().$dispose();
    api.interceptors.request.eject(interceptorId);
    vi.useRealTimers();
    _resetForTesting();
    delete (window as unknown as Record<string, unknown>)[BOOTSTRAP_KEY];
  });

  describe.each([
    ['DashboardRecent (/recent)', DashboardRecent],
    ['RecentSecretsTable (dashboard)', RecentSecretsTable],
  ])('%s', (_name, component) => {
    it('loads on arrival with an ordinary, active request', async () => {
      await mountAuthenticated(component);

      expect(declarations()).toEqual([undefined]);
    });

    it('declares the 5-minute timer refresh passive', async () => {
      await mountAuthenticated(component);

      await vi.advanceTimersByTimeAsync(BACKGROUND_REFRESH_INTERVAL_MS);
      await vi.advanceTimersByTimeAsync(BACKGROUND_REFRESH_INTERVAL_MS);

      expect(declarations()).toEqual([undefined, 'passive', 'passive']);
    });

    it('declares the tab-visibility refresh passive', async () => {
      await mountAuthenticated(component);

      setVisibility('hidden');
      setVisibility('visible');
      await vi.advanceTimersByTimeAsync(0);

      expect(declarations()).toEqual([undefined, 'passive']);
    });

    it('sends nothing from a hidden tab', async () => {
      await mountAuthenticated(component);
      setVisibility('hidden');

      await vi.advanceTimersByTimeAsync(BACKGROUND_REFRESH_INTERVAL_MS * 3);

      expect(declarations()).toEqual([undefined]);
    });

    it('stops when the component unmounts', async () => {
      await mountAuthenticated(component);
      wrapper?.unmount();
      wrapper = null;

      await vi.advanceTimersByTimeAsync(BACKGROUND_REFRESH_INTERVAL_MS * 2);

      expect(declarations()).toEqual([undefined]);
    });
  });

  it('a later arrival is active again: the declaration does not stick', async () => {
    await mountAuthenticated(DashboardRecent);
    await vi.advanceTimersByTimeAsync(BACKGROUND_REFRESH_INTERVAL_MS);
    wrapper?.unmount();

    await mountAuthenticated(RecentSecretsTable);

    expect(declarations()).toEqual([undefined, 'passive', undefined]);
  });
});
