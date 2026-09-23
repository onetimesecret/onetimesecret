// src/tests/api/passiveRequest.spec.ts
//
// The passive-request wire contract (ADR-048, RISK-2026-09-19-04), asserted on
// the REAL client: createApi() with its real request interceptor.
//
// `{ passive: true }` on a GET or HEAD sends exactly `X-Session-Activity:
// passive`, which the server (Onetime::SessionActivity) reads so that a timer
// or tab-visibility refresh does not move the inactivity clock. Everything else
// here guards the ways that goes wrong: a header that sticks to the instance
// would sign active users out; a header on a write would suggest a write can
// be passive.

import { createApi } from '@/api';
import {
  SESSION_ACTIVITY_HEADER,
  SESSION_ACTIVITY_PASSIVE,
} from '@/plugins/axios/interceptors';
import AxiosMockAdapter from 'axios-mock-adapter';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { setupTestPinia } from '../setup';

describe('createApi — passive request declaration', () => {
  let api: ReturnType<typeof createApi>;
  let mock: AxiosMockAdapter;

  const sentHeader = (request: { headers?: unknown }): unknown =>
    (request.headers as Record<string, unknown> | undefined)?.[SESSION_ACTIVITY_HEADER];

  beforeEach(async () => {
    await setupTestPinia(); // the interceptor reads the csrf/language/org stores
    api = createApi();
    mock = new AxiosMockAdapter(api);
    mock.onAny().reply(200, {});
  });

  afterEach(() => {
    mock.restore();
  });

  it('spells the header the server reads', () => {
    // Onetime::SessionActivity::HEADER / PASSIVE
    expect(SESSION_ACTIVITY_HEADER).toBe('X-Session-Activity');
    expect(SESSION_ACTIVITY_PASSIVE).toBe('passive');
  });

  it('sends the header on a passive GET', async () => {
    await api.get('/api/v3/receipt/recent', { passive: true });

    expect(sentHeader(mock.history.get[0])).toBe('passive');
  });

  it('sends the header on a passive HEAD', async () => {
    await api.head('/api/v3/receipt/recent', { passive: true });

    expect(sentHeader(mock.history.head[0])).toBe('passive');
  });

  it('sends no header on an ordinary GET', async () => {
    await api.get('/api/v3/receipt/recent');
    await api.get('/api/v3/receipt/recent', { passive: false });

    expect(sentHeader(mock.history.get[0])).toBeUndefined();
    expect(sentHeader(mock.history.get[1])).toBeUndefined();
  });

  it('does not stick to the instance after a passive request', async () => {
    await api.get('/api/v3/receipt/recent', { passive: true });
    await api.get('/api/v3/receipt/recent');

    expect(sentHeader(mock.history.get[1])).toBeUndefined();
    expect(JSON.stringify(api.defaults.headers)).not.toContain(SESSION_ACTIVITY_HEADER);
  });

  it.each(['post', 'put', 'patch', 'delete'] as const)(
    'never sends the header on %s, even when asked to',
    async (method) => {
      await api.request({ method, url: '/api/v3/receipt/abc', passive: true });

      expect(sentHeader(mock.history[method][0])).toBeUndefined();
    }
  );
});
