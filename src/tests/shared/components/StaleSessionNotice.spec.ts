// src/tests/shared/components/StaleSessionNotice.spec.ts

import { createTestingPinia } from '@pinia/testing';
import { createTestI18n } from '@tests/setup';
import { mount, type VueWrapper } from '@vue/test-utils';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { nextTick } from 'vue';

import DomainDns from '@/apps/workspace/domains/DomainDns.vue?raw';
import StaleSessionNotice from '@/shared/components/auth/StaleSessionNotice.vue';
import { useAuthStore } from '@/shared/stores/authStore';

const PROPERTY = '--stale-session-notice-height';
const published = () => document.documentElement.style.getPropertyValue(PROPERTY);

describe('StaleSessionNotice height variable', () => {
  let wrapper: VueWrapper;
  let heightSpy: ReturnType<typeof vi.spyOn> | undefined;

  const mountNotice = () => {
    const pinia = createTestingPinia({ createSpy: vi.fn });
    wrapper = mount(StaleSessionNotice, { global: { plugins: [pinia, createTestI18n()] } });
    return useAuthStore();
  };

  afterEach(() => {
    wrapper?.unmount();
    heightSpy?.mockRestore();
    document.documentElement.style.removeProperty(PROPERTY);
  });

  it('publishes nothing while the notice is not shown', async () => {
    mountNotice();
    await nextTick();
    expect(wrapper.find('[data-testid="stale-session-notice"]').exists()).toBe(false);
    expect(published()).toBe('');
  });

  it('publishes its measured height while shown and removes it when the state clears', async () => {
    // jsdom lays nothing out, so give the notice a height.
    heightSpy = vi.spyOn(HTMLElement.prototype, 'offsetHeight', 'get').mockReturnValue(52);
    const authStore = mountNotice();

    authStore.staleSession = true;
    await nextTick();
    await nextTick();
    expect(wrapper.find('[data-testid="stale-session-notice"]').exists()).toBe(true);
    expect(published()).toBe('52px');

    authStore.staleSession = false;
    await nextTick();
    await nextTick();
    expect(published()).toBe('');
  });

  it('removes the property on unmount', async () => {
    heightSpy = vi.spyOn(HTMLElement.prototype, 'offsetHeight', 'get').mockReturnValue(40);
    const authStore = mountNotice();
    authStore.staleSession = true;
    await nextTick();
    await nextTick();
    expect(published()).toBe('40px');

    wrapper.unmount();
    expect(published()).toBe('');
  });

  it('is consumed by a domain page sticky header, which falls back to 0px', () => {
    expect(DomainDns).toContain('sticky top-[var(--stale-session-notice-height,0px)] z-30');
  });
});
