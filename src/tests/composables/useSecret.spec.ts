// src/tests/composables/useSecret.spec.ts
//
// #3424 — disambiguating a terminal "not found" from a transient/parse failure.
//
// useSecret now records the failing HTTP status (state.errorCode) so the view can
// tell a genuine 404 (consumed/expired/missing → the terminal "this secret has
// been viewed or expired" screen) apart from a network/5xx/schema-parse failure,
// which must NOT be reported to the recipient as a consumed secret. These tests
// pin that signal; BaseShowSecret branches on it (isNotFound = errorCode === 404).

import { useSecret } from '@/shared/composables/useSecret';
import { useSecretStore } from '@/shared/stores/secretStore';
import { createTestingPinia } from '@pinia/testing';
import { AxiosError } from 'axios';
import { mount } from '@vue/test-utils';
import { defineComponent, h } from 'vue';
import { beforeEach, describe, expect, it, vi } from 'vitest';

// useAsyncHandler calls useI18n() synchronously in setup; stub it so we don't
// need the full i18n plugin for this unit.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (key: string) => key }),
}));

function mountUseSecret() {
  let api: ReturnType<typeof useSecret> | undefined;
  const Comp = defineComponent({
    setup() {
      api = useSecret('abc123');
      return () => h('div');
    },
  });
  mount(Comp, {
    global: { plugins: [createTestingPinia({ createSpy: vi.fn, stubActions: true })] },
  });
  return api!;
}

function httpError(status: number): AxiosError {
  const err = new AxiosError('HTTP Error', String(status));
  // Minimal shape classifyError.classifyHttp reads.
  (err as unknown as { response: unknown }).response = { status, data: {} };
  return err;
}

describe('useSecret — error-code capture (#3424)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('captures a 404 as a terminal not-found code', async () => {
    const api = mountUseSecret();
    const store = useSecretStore();
    store.fetch = vi.fn().mockRejectedValue(httpError(404));

    await api.load();

    expect(api.state.errorCode).toBe(404); // → BaseShowSecret keeps UnknownSecret
    expect(api.record.value).toBeNull();
  });

  it('captures a 500 as a non-not-found code (→ error slot, not "viewed or expired")', async () => {
    const api = mountUseSecret();
    const store = useSecretStore();
    store.fetch = vi.fn().mockRejectedValue(httpError(500));

    await api.load();

    expect(api.state.errorCode).toBe(500);
    expect(api.state.error).toBeTruthy();
  });

  it('captures a schema/parse failure as a non-not-found error (code null)', async () => {
    // secretStore.fetch throws a plain Error on gracefulParse failure; it
    // classifies as a technical error with no HTTP status. This is the case the
    // bug report cared about: a frontend parse failure must not look like a 404.
    const api = mountUseSecret();
    const store = useSecretStore();
    store.fetch = vi
      .fn()
      .mockRejectedValue(new Error('Unable to load secret. Please try again.'));

    await api.load();

    expect(api.state.errorCode).toBeNull(); // not 404 → error slot, not UnknownSecret
    expect(api.state.error).toBeTruthy();
  });

  it('clears a stale error code on a subsequent successful load', async () => {
    const api = mountUseSecret();
    const store = useSecretStore();

    store.fetch = vi.fn().mockRejectedValue(httpError(404));
    await api.load();
    expect(api.state.errorCode).toBe(404);

    store.fetch = vi.fn().mockResolvedValue(undefined);
    await api.load();
    expect(api.state.errorCode).toBeNull();
    expect(api.state.error).toBe('');
  });
});
