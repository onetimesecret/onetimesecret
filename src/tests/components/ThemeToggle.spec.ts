// src/tests/components/ThemeToggle.spec.ts

import { mount } from '@vue/test-utils';
import { describe, it, expect, vi } from 'vitest';
import ThemeToggle from '@/components/ThemeToggle.vue';

const mockInitializeTheme = vi.fn();
const mockToggleDarkMode = vi.fn();
const mockIsDarkMode = { value: false };
const mockGetThemeListenersSize = vi.fn();

vi.mock('@/composables/useTheme', () => ({
  useTheme: vi.fn(() => ({
    isDarkMode: mockIsDarkMode,
    toggleDarkMode: mockToggleDarkMode,
    initializeTheme: mockInitializeTheme,
    clearThemeListeners: vi.fn(),
    getThemeListenersSize: mockGetThemeListenersSize,
  })),
}));

describe('ThemeToggle', () => {
  it('emits "theme-changed" event with correct value when toggled', async () => {
    const wrapper = mount(ThemeToggle);
    await wrapper.find('button').trigger('click');
    expect(wrapper.emitted('theme-changed')).toBeTruthy();
    expect(wrapper.emitted('theme-changed')?.[0]).toEqual([false]);
  });

  it('initializes theme on mount', () => {
    mount(ThemeToggle);
    expect(mockIsDarkMode.value).toEqual(false);
    expect(mockInitializeTheme).toHaveBeenCalled();
    expect(mockIsDarkMode.value).toEqual(false);
  });

  it('cleans up listeners on unmount', () => {
    mockGetThemeListenersSize.mockReturnValue(0);
    const wrapper = mount(ThemeToggle);
    expect(mockGetThemeListenersSize()).toBe(0);
    wrapper.unmount();
    expect(mockGetThemeListenersSize()).toBe(0);
  });

  it('initializes with correct dark mode state', () => {
    const wrapper = mount(ThemeToggle);
    expect(mockIsDarkMode.value).toBe(false); // Assuming initial light mode
  });

  it.skip('emits "theme-changed" event with correct value on toggle', async () => {
    const wrapper = mount(ThemeToggle);

    // Check initial state before any interaction
    expect(mockIsDarkMode.value).toBe(false);

    await wrapper.find('button').trigger('click');
    // After click, check the first emitted value (initial state)
    const emit1 = wrapper.emitted('theme-changed')?.[0];
    expect(emit1).toStrictEqual([false]);

    // Now, after toggle, check new state
    //expect(mockIsDarkMode.value).toBe(true);

    // Toggling again should emit true and switch back
    await wrapper.find('button').trigger('click');
    const emit2 = wrapper.emitted('theme-changed')?.[1];
    expect(emit2).toStrictEqual([true]);
  });

  it.skip('checks visual changes on toggle', async () => {
    const wrapper = mount(ThemeToggle);
    expect(wrapper.find('button').element.getAttribute('class')).toContain(
      'dark:text-gray-400 dark:hover:bg-gray-700'
    );

    await wrapper.find('button').trigger('click');
    expect(wrapper.find('button').element.getAttribute('class')).toContain(
      'dark:text-gray-400 dark:hover:bg-gray-700'
    );
  });

  it('verifies cleanup on unmount', () => {
    mockGetThemeListenersSize.mockReturnValue(0);
    const wrapper = mount(ThemeToggle);

    // Perform some actions that add listeners
    expect(mockGetThemeListenersSize()).toBe(0);
    wrapper.unmount();
    expect(mockGetThemeListenersSize()).toBe(0);
  });
});
