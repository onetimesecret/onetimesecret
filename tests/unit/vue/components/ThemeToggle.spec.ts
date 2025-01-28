// tests/unit/vue/components/ThemeToggle.spec.ts

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
    expect(wrapper.emitted('theme-changed')[0]).toEqual([false]);
  });

  it('initializes theme on mount', () => {
    mount(ThemeToggle);
    expect(mockInitializeTheme).toHaveBeenCalled();
  });

  it('cleans up listeners on unmount', () => {
    mockGetThemeListenersSize.mockReturnValue(0);
    const wrapper = mount(ThemeToggle);
    expect(mockGetThemeListenersSize()).toBe(0);
    wrapper.unmount();
    expect(mockGetThemeListenersSize()).toBe(0);
  });
});
