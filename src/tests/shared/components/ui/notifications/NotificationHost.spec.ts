// src/tests/shared/components/ui/notifications/NotificationHost.spec.ts
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

import { NotificationHost, NotificationPill } from '@/shared/components/ui/notifications';
import { useNotificationsStore } from '@/shared/stores/notificationsStore';
import { mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { nextTick } from 'vue';
import { createTestI18n } from '@tests/setup';

// Mock OIcon — keeps the DOM lean and avoids icon library lookups
vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-icon="name" />',
    props: ['collection', 'name', 'class'],
  },
}));

const i18n = createTestI18n();

describe('NotificationHost (auto-dismiss)', () => {
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
    mount(NotificationHost, {
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

  // Forwarding: the store owns `duration`; NotificationHost binds it onto the
  // teleported variant component (`:duration="notifications.duration"`). A
  // distinctive value (2000, not the 5000 default that every link in the
  // chain falls back to) is required — a broken binding would let the child's
  // own `withDefaults` 5000 mask the failure.
  describe('Duration forwarding to child component', () => {
    it('forwards the store duration onto the rendered variant', async () => {
      wrapper = mountComponent();

      notifications.show('first', 'success', undefined, 2000);
      await nextTick();

      const pill = wrapper.findComponent(NotificationPill);
      expect(pill.exists()).toBe(true);
      expect(notifications.duration).toBe(2000);
      expect(pill.props('duration')).toBe(2000);
    });

    it('forwards the default duration when none is supplied', async () => {
      wrapper = mountComponent();

      notifications.show('first', 'success');
      await nextTick();

      const pill = wrapper.findComponent(NotificationPill);
      expect(notifications.duration).toBe(5000);
      expect(pill.props('duration')).toBe(5000);
    });
  });
});
