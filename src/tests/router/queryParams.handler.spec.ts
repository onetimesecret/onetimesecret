// src/tests/router/queryParams.handler.spec.ts
//
// processQueryParams (src/router/queryParams.handler.ts): runs each handler
// whose parameter is present and valid, waits for all of them, and reports
// one result per handler that ran. It never rejects; the route guard decides
// what a failed locale means.

import { beforeEach, describe, expect, it, vi } from 'vitest';

const state = vi.hoisted(() => ({
  supported: ['en', 'bg', 'it_IT'],
  setCurrentLocale: vi.fn(),
  setTheme: vi.fn(),
}));

vi.mock('@/shared/stores/languageStore', () => ({
  useLanguageStore: () => ({
    // Normalizes like the store does for the cases used here.
    resolveSupportedLocale: (locale: string) => {
      const normalized = locale.replaceAll('-', '_');
      return (
        state.supported.find((code) => code.toLowerCase() === normalized.toLowerCase()) ?? null
      );
    },
    setCurrentLocale: state.setCurrentLocale,
  }),
}));

vi.mock('@/shared/composables/useTheme', () => ({
  useTheme: () => ({ setTheme: state.setTheme }),
}));

import { processQueryParams } from '@/router/queryParams.handler';

describe('processQueryParams', () => {
  beforeEach(() => {
    state.setCurrentLocale.mockReset().mockImplementation(async (locale: string) => locale);
    state.setTheme.mockReset();
  });

  it('runs nothing and resolves empty without known parameters', async () => {
    await expect(processQueryParams({ utm_source: 'mail' })).resolves.toEqual([]);

    expect(state.setCurrentLocale).not.toHaveBeenCalled();
    expect(state.setTheme).not.toHaveBeenCalled();
  });

  it('waits for the locale to be activated before resolving', async () => {
    let finish!: () => void;
    state.setCurrentLocale.mockImplementation(
      () => new Promise<void>((resolve) => (finish = resolve))
    );
    let settled = false;

    const results = processQueryParams({ locale: 'bg' }).then((value) => {
      settled = true;
      return value;
    });
    await Promise.resolve();
    expect(settled).toBe(false);

    finish();
    await expect(results).resolves.toEqual([{ key: 'locale', ok: true }]);
    expect(state.setCurrentLocale).toHaveBeenCalledWith('bg');
  });

  it('passes a supported locale through in the form the URL gave it', async () => {
    await processQueryParams({ locale: 'it-IT' });

    // setCurrentLocale normalizes; the handler does not.
    expect(state.setCurrentLocale).toHaveBeenCalledWith('it-IT');
  });

  it.each([
    ['an unsupported locale', 'sw'],
    ['a malformed locale', '<script>'],
    ['an empty value', ''],
  ])('ignores %s, as the server does', async (_label, locale) => {
    await expect(processQueryParams({ locale })).resolves.toEqual([]);

    expect(state.setCurrentLocale).not.toHaveBeenCalled();
  });

  it('ignores a repeated parameter (an array in the router query)', async () => {
    await expect(processQueryParams({ locale: ['bg', 'it_IT'] })).resolves.toEqual([]);

    expect(state.setCurrentLocale).not.toHaveBeenCalled();
  });

  it('reports a locale that did not load instead of rejecting', async () => {
    const failure = new Error('messages for bg did not load');
    state.setCurrentLocale.mockRejectedValue(failure);

    await expect(processQueryParams({ locale: 'bg' })).resolves.toEqual([
      { key: 'locale', ok: false, error: failure },
    ]);
  });

  it('reports a handler that throws synchronously instead of rejecting', async () => {
    const failure = new Error('theme storage unavailable');
    state.setTheme.mockImplementation(() => {
      throw failure;
    });

    await expect(processQueryParams({ theme: 'dark' })).resolves.toEqual([
      { key: 'theme', ok: false, error: failure },
    ]);
  });

  it('runs every valid handler and reports each', async () => {
    await expect(processQueryParams({ locale: 'bg', theme: 'dark' })).resolves.toEqual([
      { key: 'locale', ok: true },
      { key: 'theme', ok: true },
    ]);

    expect(state.setTheme).toHaveBeenCalledWith('dark');
  });

  it('skips an invalid theme but still runs the locale', async () => {
    await expect(processQueryParams({ locale: 'bg', theme: 'purple' })).resolves.toEqual([
      { key: 'locale', ok: true },
    ]);

    expect(state.setTheme).not.toHaveBeenCalled();
  });
});
