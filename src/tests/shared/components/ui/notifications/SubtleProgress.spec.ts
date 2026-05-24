// src/tests/shared/components/ui/notifications/SubtleProgress.spec.ts
//
// Tests for SubtleProgress auto-dismiss timer behavior.
//
// Load-bearing regression: when a new notification message arrives while
// one is already visible, the auto-dismiss timer must be RESET so the new
// message gets its full duration before hiding. Prior behavior watched
// only isVisible, which left the old timer running over the new message.

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
      props: {
        duration: 2000,
        autoDismiss: true,
        loading: false,
        ...props,
      },
      global: { plugins: [i18n] },
      attachTo: document.body,
    });

  describe('Auto-dismiss timer', () => {
    it('hides the notification after the duration elapses', async () => {
      wrapper = mountComponent({ duration: 2000 });
      const hideSpy = vi.spyOn(notifications, 'hide');

      notifications.show('first', 'success');
      await nextTick();

      // Halfway through — still visible
      vi.advanceTimersByTime(1000);
      expect(hideSpy).not.toHaveBeenCalled();

      // Past full duration — timer fires
      vi.advanceTimersByTime(1100);
      expect(hideSpy).toHaveBeenCalled();
    });
  });

  describe('Timer reset on new message (regression)', () => {
    it('resets the auto-dismiss timer when the message changes mid-flight', async () => {
      wrapper = mountComponent({ duration: 2000 });
      const hideSpy = vi.spyOn(notifications, 'hide');

      notifications.show('first', 'success');
      await nextTick();

      // Advance partway through the first timer
      vi.advanceTimersByTime(1500);
      expect(hideSpy).not.toHaveBeenCalled();

      // New message arrives while still visible
      notifications.show('second', 'info');
      await nextTick();

      // Advance past where the *old* timer would have fired (500ms more)
      vi.advanceTimersByTime(600);
      expect(hideSpy).not.toHaveBeenCalled();

      // Advance past the full new duration from the second show
      vi.advanceTimersByTime(1500);
      expect(hideSpy).toHaveBeenCalled();
    });
  });

  describe('Conditions that disable the timer', () => {
    it('does not start a timer when autoDismiss is false', async () => {
      wrapper = mountComponent({ autoDismiss: false, duration: 1000 });
      const hideSpy = vi.spyOn(notifications, 'hide');

      notifications.show('first', 'success');
      await nextTick();

      vi.advanceTimersByTime(5000);
      expect(hideSpy).not.toHaveBeenCalled();
    });

    it('does not start a timer when loading is true', async () => {
      wrapper = mountComponent({ loading: true, duration: 1000 });
      const hideSpy = vi.spyOn(notifications, 'hide');

      notifications.show('first', 'success');
      await nextTick();

      vi.advanceTimersByTime(5000);
      expect(hideSpy).not.toHaveBeenCalled();
    });
  });
});
