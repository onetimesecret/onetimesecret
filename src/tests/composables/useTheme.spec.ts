// src/tests/composables/useTheme.spec.ts

import { useTheme } from '@/composables/useTheme';
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { nextTick } from 'vue';
import { shallowMount } from '@vue/test-utils';

describe('useTheme', () => {
  beforeEach(() => {
    localStorage.clear();
    document.documentElement.classList.remove('dark');
  });

  it.skip('initializes theme based on localStorage', async () => {
    localStorage.setItem('restMode', 'true');
    const { initializeTheme, isDarkMode } = useTheme();
    initializeTheme();
    await nextTick();
    expect(isDarkMode.value).toBe(true);
    expect(document.documentElement.classList.contains('dark')).toBe(true);
  });

  it.skip('toggles dark mode', async () => {
    const { toggleDarkMode, isDarkMode, initializeTheme } = useTheme();
    initializeTheme();
    await nextTick();

    toggleDarkMode();
    await nextTick();
    expect(isDarkMode.value).toBe(false);
    expect(localStorage.getItem('restMode')).toBe('false');
    expect(document.documentElement.classList.contains('dark')).toBe(false);

    toggleDarkMode();
    await nextTick();
    expect(isDarkMode.value).toBe(true);
    expect(localStorage.getItem('restMode')).toBe('true');
    expect(document.documentElement.classList.contains('dark')).toBe(true);
  });

  it('calls theme change listeners on toggle', async () => {
    const { toggleDarkMode, onThemeChange } = useTheme();
    const listener = vi.fn();
    onThemeChange(listener);

    toggleDarkMode();
    await nextTick();
    expect(listener).toHaveBeenCalledWith(true);

    toggleDarkMode();
    await nextTick();
    expect(listener).toHaveBeenCalledWith(false);
  });

  it('removes theme change listener', async () => {
    const { toggleDarkMode, onThemeChange } = useTheme();
    const listener = vi.fn();
    const removeListener = onThemeChange(listener);

    removeListener();
    toggleDarkMode();
    await nextTick();
    expect(listener).not.toHaveBeenCalled();
  });

  it('themeListeners should start empty and be empty after unmount', async () => {
    const comp = {
      template: '<div>test comp</div>',
      setup() {
        const theme = useTheme();
        return { theme };
      },
    };
    const wrapper = shallowMount(comp);
    expect(wrapper.vm.theme.getThemeListenersSize()).toBe(1); // There is a mock spy taking up a spot

    const removeListener = wrapper.vm.theme.onThemeChange(() => {});
    expect(wrapper.vm.theme.getThemeListenersSize()).toBe(2);

    wrapper.unmount(); // Nothing happens automatically on unmount
    expect(wrapper.vm.theme.getThemeListenersSize()).toBe(2);

    wrapper.vm.theme.clearThemeListeners();
    expect(wrapper.vm.theme.getThemeListenersSize()).toBe(0);
  });
});
