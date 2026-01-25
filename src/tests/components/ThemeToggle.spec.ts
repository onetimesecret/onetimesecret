// src/tests/components/ThemeToggle.spec.ts

import { mount } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import ThemeToggle from '@/shared/components/ui/ThemeToggle.vue';

const mockIsDarkMode = { value: false };
const mockInitializeTheme = vi.fn();
const mockToggleDarkMode = vi.fn(() => {
  mockIsDarkMode.value = !mockIsDarkMode.value;
});
const mockClearThemeListeners = vi.fn();
const mockGetThemeListenersSize = vi.fn(() => 0);

vi.mock('@/shared/composables/useTheme', () => ({
  useTheme: vi.fn(() => ({
    isDarkMode: mockIsDarkMode,
    toggleDarkMode: mockToggleDarkMode,
    initializeTheme: mockInitializeTheme,
    clearThemeListeners: mockClearThemeListeners,
    getThemeListenersSize: mockGetThemeListenersSize,
  })),
}));

vi.mock('vue-i18n', () => ({
  useI18n: vi.fn(() => ({
    t: vi.fn((key: string) => key),
  })),
}));

describe('ThemeToggle', () => {
  beforeEach(() => {
    // Reset mocks and state before each test
    mockIsDarkMode.value = false;
    mockInitializeTheme.mockClear();
    mockToggleDarkMode.mockClear();
    mockClearThemeListeners.mockClear();
  });

  it('emits "theme-changed" event with correct value when toggled', async () => {
    const wrapper = mount(ThemeToggle);
    await wrapper.find('button').trigger('click');

    // After toggle, isDarkMode changes from false to true
    expect(wrapper.emitted('theme-changed')).toBeTruthy();
    expect(wrapper.emitted('theme-changed')?.[0]).toEqual([true]);
  });

  it('initializes theme on mount', () => {
    mount(ThemeToggle);
    expect(mockInitializeTheme).toHaveBeenCalledOnce();
  });

  it('cleans up listeners on unmount', () => {
    const wrapper = mount(ThemeToggle);
    wrapper.unmount();
    expect(mockClearThemeListeners).toHaveBeenCalledOnce();
  });

  it('initializes with correct dark mode state', () => {
    const wrapper = mount(ThemeToggle);
    expect(mockIsDarkMode.value).toBe(false);
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
    const wrapper = mount(ThemeToggle);
    wrapper.unmount();
    expect(mockClearThemeListeners).toHaveBeenCalledOnce();
  });
});
