// tests/unit/vue/fixtures/clipboard.fixture.ts

import { vi } from 'vitest';

/**
 * Mocks navigator.clipboard.writeText for testing copy functionality.
 * Returns the mock function so tests can assert on it.
 */
export function mockClipboard() {
  const writeText = vi.fn().mockResolvedValue(undefined);

  Object.defineProperty(navigator, 'clipboard', {
    value: { writeText },
    writable: true,
    configurable: true,
  });

  return writeText;
}
