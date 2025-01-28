// tests/unit/vue/composables/useTheme.spec.ts

import { useTheme } from '@/composables/useTheme';
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { nextTick } from 'vue';

describe('useTheme', () => {
  beforeEach(() => {
    localStorage.clear();
    document.documentElement.classList.remove('dark');
  });

  it('initializes theme based on localStorage', async () => {
    localStorage.setItem('restMode', 'true');
    const { initializeTheme, isDarkMode } = useTheme();
    initializeTheme();
    await nextTick();
    expect(isDarkMode.value).toBe(true);
    expect(document.documentElement.classList.contains('dark')).toBe(true);
  });

  it('toggles dark mode', async () => {
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
    expect(listener).toHaveBeenCalledWith(false);

    toggleDarkMode();
    await nextTick();
    expect(listener).toHaveBeenCalledWith(true);
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
});
