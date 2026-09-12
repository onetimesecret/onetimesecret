// src/tests/services/impersonation.service.spec.ts

import { AxiosError } from 'axios';
import { beforeEach, describe, expect, it, vi } from 'vitest';

const { mockPost } = vi.hoisted(() => ({ mockPost: vi.fn() }));

vi.mock('@/api', () => ({
  createApi: () => ({ post: mockPost }),
}));

import {
  IMPERSONATION_STOP_FALLBACK_PATH,
  IMPERSONATION_STOP_PATH,
  stopImpersonation,
} from '@/services/impersonation.service';

describe('impersonation.service', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockPost.mockReset();
  });

  it('pins the stop path OUTSIDE /api/colonel (blocked while impersonating)', () => {
    expect(IMPERSONATION_STOP_PATH).toBe('/api/account/impersonation/stop');
    expect(IMPERSONATION_STOP_PATH.startsWith('/api/colonel')).toBe(false);
    expect(IMPERSONATION_STOP_FALLBACK_PATH).toBe('/colonel');
  });

  it('POSTs the stop endpoint with no body and returns the server redirect', async () => {
    mockPost.mockResolvedValueOnce({
      data: {
        record: { stopped: true, target_extid: 'ur_bob', redirect: '/colonel/customers/ur_bob' },
      },
    });

    await expect(stopImpersonation()).resolves.toBe('/colonel/customers/ur_bob');
    expect(mockPost).toHaveBeenCalledWith(IMPERSONATION_STOP_PATH);
  });

  it('falls back to the console when the ack names no redirect', async () => {
    mockPost.mockResolvedValueOnce({
      data: { record: { stopped: true, target_extid: 'ur_bob', redirect: null } },
    });

    await expect(stopImpersonation()).resolves.toBe(IMPERSONATION_STOP_FALLBACK_PATH);
  });

  it('falls back rather than throwing on an unreadable ack — the 2xx ENDED it', async () => {
    mockPost.mockResolvedValueOnce({ data: { nonsense: true } });

    await expect(stopImpersonation()).resolves.toBe(IMPERSONATION_STOP_FALLBACK_PATH);
  });

  describe('rejected requests', () => {
    /** Mock-adapter-shaped rejection: NOT an AxiosError, but carries .response. */
    function httpError(status: number, data: unknown = {}): Error {
      const err = new Error(`Request failed with status ${status}`);
      Object.assign(err, { response: { status, data } });
      return err;
    }

    it('treats 404 as ALREADY ENDED and returns the fallback, not an error', async () => {
      // The endpoint 404s when there is no marker to stop (expired, or already
      // cleared). Retrying would offer to end a session that is already over.
      mockPost.mockRejectedValueOnce(httpError(404, { error: 'Not Found' }));

      await expect(stopImpersonation()).resolves.toBe(IMPERSONATION_STOP_FALLBACK_PATH);
    });

    it('reads the status off a real AxiosError too', async () => {
      const err = new AxiosError('Request failed');
      err.response = { status: 404, data: {}, statusText: '', headers: {}, config: {} as never };
      mockPost.mockRejectedValueOnce(err);

      await expect(stopImpersonation()).resolves.toBe(IMPERSONATION_STOP_FALLBACK_PATH);
    });

    it.each([
      ['403 read-only refusal', 403],
      ['500 server error', 500],
    ])('propagates a %s: the marker is presumed still active', async (_label, status) => {
      const err = httpError(status);
      mockPost.mockRejectedValueOnce(err);

      await expect(stopImpersonation()).rejects.toThrow(err);
    });

    it('propagates a network error with no response at all', async () => {
      mockPost.mockRejectedValueOnce(new Error('Network Error'));

      await expect(stopImpersonation()).rejects.toThrow('Network Error');
    });
  });

  it('uses a caller-supplied axios instance when given one', async () => {
    const post = vi.fn().mockResolvedValue({
      data: { record: { stopped: true, target_extid: 'ur_bob', redirect: '/colonel' } },
    });

    await stopImpersonation({ post } as never);

    expect(post).toHaveBeenCalledWith(IMPERSONATION_STOP_PATH);
    expect(mockPost).not.toHaveBeenCalled();
  });
});
