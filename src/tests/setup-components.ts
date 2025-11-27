// src/tests/setup-components.ts

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
// Create a functional localStorage mock that actually stores data
const createLocalStorageMock = () => {
  let store: Record<string, string> = {};

  return {
    getItem: vi.fn((key: string) => store[key] || null),
    setItem: vi.fn((key: string, value: string) => {
      store[key] = value.toString();
    }),
    removeItem: vi.fn((key: string) => {
      delete store[key];
    }),
    clear: vi.fn(() => {
      store = {};
    }),
    get length() {
      return Object.keys(store).length;
    },
    key: vi.fn((index: number) => {
      const keys = Object.keys(store);
      return keys[index] || null;
    }),
  };
};

Object.defineProperty(window, 'localStorage', {
  value: createLocalStorageMock(),
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
