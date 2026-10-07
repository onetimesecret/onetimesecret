// src/tests/stores/notificationsStore.spec.ts

import { setupTestPinia } from '../setup';
import { setupBootstrapMock } from '../setup-bootstrap';
import { baseBootstrap } from '@/tests/fixtures/bootstrap.fixture';

import { useNotificationsStore } from '@/shared/stores/notificationsStore';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { nextTick } from 'vue';

describe('Notifications Store', () => {
  let store: ReturnType<typeof useNotificationsStore>;

  beforeEach(async () => {
    // Real actions (stubActions false) so the timers and the pending queue run.
    await setupTestPinia();
    setupBootstrapMock({ initialState: baseBootstrap });
    vi.useFakeTimers();
    store = useNotificationsStore();
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
  });

  // hide() defers the queue drain to the next tick so the host renders the
  // hidden state; most tests only care about what is visible once it settles.
  async function hideAndDrain() {
    store.hide();
    await nextTick();
  }

  describe('show', () => {
    it('replaces the visible notice immediately and restarts the timer', () => {
      store.show('first', 'info', 'top', 5000);
      vi.advanceTimersByTime(4000);
      store.show('second', 'error', 'bottom', 5000);

      expect(store.message).toBe('second');
      expect(store.severity).toBe('error');
      expect(store.position).toBe('bottom');

      // The first notice's timer was cleared, so 'second' gets its full 5 s.
      vi.advanceTimersByTime(1500);
      expect(store.isVisible).toBe(true);
      vi.advanceTimersByTime(3500);
      expect(store.isVisible).toBe(false);
    });
  });

  describe('enqueue', () => {
    it('shows immediately when nothing is visible', () => {
      store.enqueue('hello', 'success', 'bottom', 2000);

      expect(store.isVisible).toBe(true);
      expect(store.message).toBe('hello');
      expect(store.severity).toBe('success');
      expect(store.position).toBe('bottom');
      expect(store.duration).toBe(2000);
    });

    it('waits while a notice is visible and shows after the timer hides it', async () => {
      store.show('session notice', 'info', 'top', 10000);
      store.enqueue('role notice', 'info', 'top', 10000);

      // Still the first notice; the second did not displace it.
      expect(store.message).toBe('session notice');

      vi.advanceTimersByTime(10000);
      // The hidden state is observable for a tick so the host can run its
      // leave/enter transition instead of swapping the text in place.
      expect(store.isVisible).toBe(false);
      await nextTick();
      expect(store.isVisible).toBe(true);
      expect(store.message).toBe('role notice');
      expect(store.duration).toBe(10000);

      // The queued notice runs its own full timer from the moment it appears.
      vi.advanceTimersByTime(9999);
      expect(store.isVisible).toBe(true);
      vi.advanceTimersByTime(1);
      expect(store.isVisible).toBe(false);
      expect(store.message).toBe('');
    });

    it('shows after an explicit hide()', async () => {
      store.show('visible', 'info');
      store.enqueue('next', 'error', 'bottom');

      store.hide();
      expect(store.isVisible).toBe(false);
      await nextTick();

      expect(store.isVisible).toBe(true);
      expect(store.message).toBe('next');
      expect(store.severity).toBe('error');
      expect(store.position).toBe('bottom');
    });

    it('drains the queue in arrival order across successive hides', async () => {
      store.show('one', 'info');
      store.enqueue('two', 'info');
      store.enqueue('three', 'info');

      await hideAndDrain();
      expect(store.message).toBe('two');
      await hideAndDrain();
      expect(store.message).toBe('three');
      await hideAndDrain();
      expect(store.isVisible).toBe(false);
      expect(store.message).toBe('');
    });

    it('holds the queue behind a sticky notice until hide() is called', async () => {
      store.show('sticky', 'error', 'top', 0);
      store.enqueue('after sticky', 'info');

      vi.advanceTimersByTime(60000);
      expect(store.message).toBe('sticky');

      await hideAndDrain();
      expect(store.message).toBe('after sticky');
    });

    it('skips a message that matches the visible notice', async () => {
      store.show('same text', 'info');
      store.enqueue('same text', 'info');

      await hideAndDrain();
      expect(store.isVisible).toBe(false);
    });

    it('skips a message that is already pending', async () => {
      store.show('visible', 'info');
      store.enqueue('dup', 'info');
      store.enqueue('dup', 'info');

      await hideAndDrain();
      expect(store.message).toBe('dup');
      await hideAndDrain();
      expect(store.isVisible).toBe(false);
    });

    it('refuses the newest entry once three are pending', async () => {
      store.show('visible', 'info');
      store.enqueue('p1', 'info');
      store.enqueue('p2', 'info');
      store.enqueue('p3', 'info');
      store.enqueue('p4', 'info');

      const shown: string[] = [];
      for (let i = 0; i < 4; i++) {
        await hideAndDrain();
        if (store.isVisible) shown.push(store.message);
      }
      expect(shown).toEqual(['p1', 'p2', 'p3']);
      expect(store.isVisible).toBe(false);
    });

    it('accepts a new entry once the queue has drained below the cap', async () => {
      store.show('visible', 'info');
      store.enqueue('p1', 'info');
      store.enqueue('p2', 'info');
      store.enqueue('p3', 'info');

      await hideAndDrain(); // p1 visible, two pending
      store.enqueue('p4', 'info');

      await hideAndDrain();
      await hideAndDrain();
      await hideAndDrain();
      expect(store.message).toBe('p4');
    });

    it('queues behind notices still pending while the drain is in flight', async () => {
      store.show('one', 'info');
      store.enqueue('two', 'info');

      store.hide();
      // Hidden for the tick, but 'two' is on its way: the newcomer waits its turn.
      store.enqueue('three', 'info');
      expect(store.isVisible).toBe(false);

      await nextTick();
      expect(store.message).toBe('two');
      await hideAndDrain();
      expect(store.message).toBe('three');
    });
  });

  describe('show() during a pending queue', () => {
    it('preempts the visible notice and the queue still drains afterwards', async () => {
      store.show('one', 'info');
      store.enqueue('two', 'info');
      store.enqueue('three', 'info');

      store.show('urgent', 'error');
      expect(store.message).toBe('urgent');

      await hideAndDrain();
      expect(store.message).toBe('two');
      await hideAndDrain();
      expect(store.message).toBe('three');
      await hideAndDrain();
      expect(store.isVisible).toBe(false);
    });

    it('preempts a drain in flight without losing the queued notice', async () => {
      store.show('one', 'info');
      store.enqueue('two', 'info');

      store.hide();
      store.show('urgent', 'error');

      await nextTick();
      // The deferred drain yields to the notice that arrived in between.
      expect(store.message).toBe('urgent');

      await hideAndDrain();
      expect(store.message).toBe('two');
    });
  });

  describe('$reset', () => {
    it('clears the pending queue along with the visible notice', async () => {
      store.show('one', 'info');
      store.enqueue('two', 'info');
      store.enqueue('three', 'info');

      store.$reset();
      expect(store.isVisible).toBe(false);
      expect(store.message).toBe('');

      // Nothing left to drain: a later hide() shows nothing.
      await hideAndDrain();
      expect(store.isVisible).toBe(false);
      expect(store.message).toBe('');
    });

    it('cancels a drain in flight', async () => {
      store.show('one', 'info');
      store.enqueue('two', 'info');

      store.hide();
      store.$reset();

      await nextTick();
      expect(store.isVisible).toBe(false);
      expect(store.message).toBe('');
    });
  });
});
