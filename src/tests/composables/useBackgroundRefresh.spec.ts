// src/tests/composables/useBackgroundRefresh.spec.ts

import {
  BACKGROUND_REFRESH_INTERVAL_MS,
  BACKGROUND_REFRESH_THROTTLE_MS,
  useBackgroundRefresh,
} from '@/shared/composables/useBackgroundRefresh';
import { mount } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, h } from 'vue';

function setVisibility(state: 'visible' | 'hidden') {
  Object.defineProperty(document, 'visibilityState', { value: state, configurable: true });
  document.dispatchEvent(new Event('visibilitychange'));
}

describe('useBackgroundRefresh', () => {
  const refresh = vi.fn<() => Promise<void>>();

  const mountHost = (autoStart = true) =>
    mount(
      defineComponent({
        setup() {
          const controls = useBackgroundRefresh(refresh);
          if (autoStart) controls.start();
          return () => h('div');
        },
      })
    );

  beforeEach(() => {
    vi.useFakeTimers();
    refresh.mockReset().mockResolvedValue(undefined);
    Object.defineProperty(document, 'visibilityState', { value: 'visible', configurable: true });
  });

  afterEach(() => {
    vi.useRealTimers();
    Object.defineProperty(document, 'visibilityState', { value: 'visible', configurable: true });
  });

  it('does nothing until start() is called', async () => {
    const wrapper = mountHost(false);

    await vi.advanceTimersByTimeAsync(BACKGROUND_REFRESH_INTERVAL_MS * 2);
    setVisibility('visible');

    expect(refresh).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('refreshes once per interval while the tab is visible', async () => {
    const wrapper = mountHost();

    await vi.advanceTimersByTimeAsync(BACKGROUND_REFRESH_INTERVAL_MS - 1);
    expect(refresh).not.toHaveBeenCalled();

    await vi.advanceTimersByTimeAsync(1);
    expect(refresh).toHaveBeenCalledTimes(1);

    await vi.advanceTimersByTimeAsync(BACKGROUND_REFRESH_INTERVAL_MS);
    expect(refresh).toHaveBeenCalledTimes(2);
    wrapper.unmount();
  });

  it('sends nothing while the tab is hidden, and catches up when it is shown', async () => {
    const wrapper = mountHost();
    setVisibility('hidden');

    await vi.advanceTimersByTimeAsync(BACKGROUND_REFRESH_INTERVAL_MS * 3);
    expect(refresh).not.toHaveBeenCalled();

    setVisibility('visible');
    expect(refresh).toHaveBeenCalledTimes(1);
    wrapper.unmount();
  });

  it('throttles rapid tab switching', async () => {
    const wrapper = mountHost();

    setVisibility('visible');
    setVisibility('hidden');
    setVisibility('visible');
    expect(refresh).toHaveBeenCalledTimes(1);

    await vi.advanceTimersByTimeAsync(BACKGROUND_REFRESH_THROTTLE_MS);
    setVisibility('visible');
    expect(refresh).toHaveBeenCalledTimes(2);
    wrapper.unmount();
  });

  it('swallows a failed refresh and keeps going', async () => {
    const debug = vi.spyOn(console, 'debug').mockImplementation(() => {});
    refresh.mockRejectedValueOnce(new Error('network'));
    const wrapper = mountHost();

    await vi.advanceTimersByTimeAsync(BACKGROUND_REFRESH_INTERVAL_MS);
    await vi.advanceTimersByTimeAsync(BACKGROUND_REFRESH_INTERVAL_MS);

    expect(refresh).toHaveBeenCalledTimes(2);
    expect(debug).toHaveBeenCalledTimes(1);
    wrapper.unmount();
    debug.mockRestore();
  });

  it('stops on unmount', async () => {
    const wrapper = mountHost();
    wrapper.unmount();

    await vi.advanceTimersByTimeAsync(BACKGROUND_REFRESH_INTERVAL_MS * 2);
    setVisibility('visible');

    expect(refresh).not.toHaveBeenCalled();
  });

  // Guards async `onMounted` callers whose awaits resolve after the component
  // has already unmounted: a later start() must not resurrect the interval or
  // the visibilitychange listener (which would keep mutating store state).
  it('is a no-op if start() is called after stop()', async () => {
    const setInterval = vi.spyOn(window, 'setInterval');
    const addEventListener = vi.spyOn(document, 'addEventListener');

    const controls = (() => {
      let captured!: ReturnType<typeof useBackgroundRefresh>;
      const wrapper = mount(
        defineComponent({
          setup() {
            captured = useBackgroundRefresh(refresh);
            return () => h('div');
          },
        })
      );
      return { wrapper, captured };
    })();

    controls.captured.stop();
    setInterval.mockClear();
    addEventListener.mockClear();

    controls.captured.start();

    expect(setInterval).not.toHaveBeenCalled();
    expect(addEventListener).not.toHaveBeenCalledWith('visibilitychange', expect.anything());

    // And no ticks fire either.
    await vi.advanceTimersByTimeAsync(BACKGROUND_REFRESH_INTERVAL_MS * 2);
    setVisibility('visible');
    expect(refresh).not.toHaveBeenCalled();

    controls.wrapper.unmount();
    setInterval.mockRestore();
    addEventListener.mockRestore();
  });

  // Belt and braces: a stray in-flight run() (or one that resumes after stop)
  // must not call refresh() again once stopped.
  it('run() is a no-op after stop()', async () => {
    let captured!: ReturnType<typeof useBackgroundRefresh>;
    const wrapper = mount(
      defineComponent({
        setup() {
          captured = useBackgroundRefresh(refresh);
          captured.start();
          return () => h('div');
        },
      })
    );

    captured.stop();
    refresh.mockClear();

    // Attempt to trigger the run path by dispatching visibility events
    // directly (the listener is removed, but this proves defence-in-depth
    // even if it were re-attached somehow).
    setVisibility('hidden');
    setVisibility('visible');
    await vi.advanceTimersByTimeAsync(BACKGROUND_REFRESH_INTERVAL_MS * 2);

    expect(refresh).not.toHaveBeenCalled();
    wrapper.unmount();
  });
});
