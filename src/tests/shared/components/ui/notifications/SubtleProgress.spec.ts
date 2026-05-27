// src/tests/shared/components/ui/notifications/SubtleProgress.spec.ts
//
// Tests for notification auto-dismiss timer behavior.
//
// Auto-dismiss is owned by the store (not the component). Duration is
// passed to `notifications.show(msg, sev, pos, duration)`; the store's
// setTimeout calls the closure `hide` directly, so assertions check
// `isVisible` rather than spying on `notifications.hide`.
//
// Load-bearing regression: when a new notification message arrives while
// one is already visible, the auto-dismiss timer must be RESET so the new
// message gets its full duration before hiding.

import SubtleProgress from '@/shared/components/ui/notifications/SubtleProgress.vue';
import { useNotificationsStore } from '@/shared/stores/notificationsStore';
import { mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { nextTick } from 'vue';
import { createI18n } from 'vue-i18n';

// Mock OIcon — keeps the DOM lean and avoids icon library lookups
vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-icon="name" />',
    props: ['collection', 'name', 'class'],
  },
}));

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {
    en: {
      first: 'First message',
      second: 'Second message',
    },
  },
});

describe('SubtleProgress', () => {
  let wrapper: VueWrapper;
  let notifications: ReturnType<typeof useNotificationsStore>;

  beforeEach(() => {
    vi.useFakeTimers();
    notifications = useNotificationsStore();
    notifications.$reset();
  });

  afterEach(() => {
    if (wrapper) wrapper.unmount();
    vi.useRealTimers();
  });

  const mountComponent = (props: Record<string, unknown> = {}) =>
    mount(SubtleProgress, {
      props,
      global: { plugins: [i18n] },
      attachTo: document.body,
    });

  describe('Auto-dismiss timer', () => {
    it('hides the notification after the duration elapses', async () => {
      wrapper = mountComponent();

      notifications.show('first', 'success', undefined, 2000);
      await nextTick();
      expect(notifications.isVisible).toBe(true);

      // Halfway through — still visible
      vi.advanceTimersByTime(1000);
      expect(notifications.isVisible).toBe(true);

      // Past full duration — timer fires
      vi.advanceTimersByTime(1100);
      expect(notifications.isVisible).toBe(false);
    });
  });

  describe('Timer reset on new message (regression)', () => {
    it('resets the auto-dismiss timer when the message changes mid-flight', async () => {
      wrapper = mountComponent();

      notifications.show('first', 'success', undefined, 2000);
      await nextTick();

      // Advance partway through the first timer
      vi.advanceTimersByTime(1500);
      expect(notifications.isVisible).toBe(true);

      // New message arrives while still visible
      notifications.show('second', 'info', undefined, 2000);
      await nextTick();

      // Advance past where the *old* timer would have fired (500ms more)
      vi.advanceTimersByTime(600);
      expect(notifications.isVisible).toBe(true);

      // Advance past the full new duration from the second show
      vi.advanceTimersByTime(1500);
      expect(notifications.isVisible).toBe(false);
    });
  });

  describe('Conditions that disable the timer', () => {
    it('does not start a timer when duration is 0', async () => {
      wrapper = mountComponent();

      notifications.show('first', 'success', undefined, 0);
      await nextTick();

      vi.advanceTimersByTime(10_000);
      expect(notifications.isVisible).toBe(true);
    });
  });
});
