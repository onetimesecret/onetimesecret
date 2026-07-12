// src/tests/apps/admin/useAdminMutation.spec.ts

import { AxiosError } from 'axios';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { useAdminMutation } from '@/apps/admin/composables/useAdminMutation';

/** Build a real AxiosError so the shared classifier extracts `data.error`. */
function axiosError(status: number, data: unknown, message = 'Request failed'): AxiosError {
  const err = new AxiosError(message);
  err.response = { status, data, statusText: '', headers: {}, config: {} as never };
  return err;
}

describe('useAdminMutation (guarded-mutation request half — CONTRACT 3)', () => {
  beforeEach(() => vi.clearAllMocks());
  afterEach(() => vi.clearAllMocks());

  it('starts idle', () => {
    const m = useAdminMutation(async () => undefined);
    expect(m.loading.value).toBe(false);
    expect(m.error.value).toBeNull();
  });

  it('runs the mutation, forwards args, and resolves true on success', async () => {
    const perform = vi.fn().mockResolvedValue({ ok: true });
    const m = useAdminMutation(perform);

    const ok = await m.run('customer', 'staff');

    expect(perform).toHaveBeenCalledWith('customer', 'staff');
    expect(ok).toBe(true);
    expect(m.error.value).toBeNull();
    expect(m.loading.value).toBe(false);
  });

  it('flips loading true during the call and false after', async () => {
    let loadingDuring = false;
    const m = useAdminMutation(() => {
      loadingDuring = m.loading.value;
      return Promise.resolve();
    });

    await m.run();

    expect(loadingDuring).toBe(true);
    expect(m.loading.value).toBe(false);
  });

  it('resolves false and captures the backend error message on failure (never throws)', async () => {
    // Axios 422 with the user-facing message in the `error` field.
    const m = useAdminMutation(async () => {
      throw axiosError(422, { error: "Invalid role 'wizard'." });
    });

    const ok = await m.run();

    expect(ok).toBe(false);
    expect(m.error.value).toBe("Invalid role 'wizard'.");
    expect(m.loading.value).toBe(false);
  });

  it('clears a prior error on the next run', async () => {
    const perform = vi
      .fn()
      .mockRejectedValueOnce(axiosError(500, {}))
      .mockResolvedValueOnce(undefined);
    const m = useAdminMutation(perform);

    await m.run();
    expect(m.error.value).not.toBeNull();

    await m.run();
    expect(m.error.value).toBeNull();
  });

  it('reset() clears loading + error', async () => {
    const m = useAdminMutation(async () => {
      throw axiosError(500, {});
    });
    await m.run();
    expect(m.error.value).not.toBeNull();

    m.reset();
    expect(m.error.value).toBeNull();
    expect(m.loading.value).toBe(false);
  });
});
