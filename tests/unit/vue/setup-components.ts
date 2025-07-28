// tests/unit/vue/setup-components.ts

import { config } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { vi } from 'vitest';

// Create a test i18n instance
const i18n = createI18n({
  legacy: false,
  locale: 'en',
  fallbackLocale: 'en',
  messages: {
    en: {
      // Add minimal translations for component tests
      'toggle-dark-mode': 'Toggle dark mode',
      'switch-to-blank-mode': 'Switch to light mode',
      'blank-mode-enabled': 'Light mode enabled',
      'dark-mode-enabled': 'Dark mode enabled',
      theme: {
        toggle: 'Toggle theme',
        dark: 'Dark mode',
        light: 'Light mode',
      },
      common: {
        loading: 'Loading...',
        submit: 'Submit',
        cancel: 'Cancel',
      },
    },
  },
});

// Configure Vue Test Utils global options
config.global.plugins = [i18n];

// Mock localStorage for theme and other component needs
Object.defineProperty(window, 'localStorage', {
  value: {
    getItem: vi.fn(() => null),
    setItem: vi.fn(),
    removeItem: vi.fn(),
    clear: vi.fn(),
  },
  writable: true,
});

// Mock matchMedia for theme detection
Object.defineProperty(window, 'matchMedia', {
  writable: true,
  value: vi.fn().mockImplementation((query) => ({
    matches: false,
    media: query,
    onchange: null,
    addListener: vi.fn(), // deprecated
    removeListener: vi.fn(), // deprecated
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
    dispatchEvent: vi.fn(),
  })),
});
