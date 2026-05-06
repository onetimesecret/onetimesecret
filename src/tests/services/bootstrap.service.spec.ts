// src/tests/services/bootstrap.service.spec.ts

/**
 * Direct unit tests for bootstrap.service.ts.
 *
 * The store-level spec (bootstrapStore.spec.ts) mocks the service, so the
 * service's own behavior — window consumption, snapshot merging, and the
 * interaction between updateBootstrapSnapshot() and consumeBootstrapData() —
 * needs coverage here.
 *
 * Issue #3083 (PR review): updateBootstrapSnapshot() must not lock out
 * server-injected window state by flipping `consumed` before the window
 * has been read.
 *
 * Run:
 *   pnpm test src/tests/services/bootstrap.service.spec.ts
 */

import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import {
  consumeBootstrapData,
  getBootstrapSnapshot,
  getBootstrapValue,
  isBootstrapConsumed,
  updateBootstrapSnapshot,
  _resetForTesting,
} from '@/services/bootstrap.service';
import type { BootstrapPayload } from '@/schemas/contracts/bootstrap';

const BOOTSTRAP_KEY = '__BOOTSTRAP_ME__';

function setWindowState(state: Partial<BootstrapPayload> | true | undefined): void {
  if (state === undefined) {
    delete (window as unknown as Record<string, unknown>)[BOOTSTRAP_KEY];
    return;
  }
  (window as unknown as Record<string, unknown>)[BOOTSTRAP_KEY] = state;
}

beforeEach(() => {
  _resetForTesting();
  setWindowState(undefined);
});

afterEach(() => {
  _resetForTesting();
  setWindowState(undefined);
});

describe('consumeBootstrapData', () => {
  it('reads window state, replaces it with a true marker, and flips consumed', () => {
    setWindowState({ authenticated: true, locale: 'fr' });

    const snapshot = consumeBootstrapData();

    expect(snapshot).toEqual({ authenticated: true, locale: 'fr' });
    expect(isBootstrapConsumed()).toBe(true);
    expect((window as unknown as Record<string, unknown>)[BOOTSTRAP_KEY]).toBe(true);
  });

  it('returns the cached snapshot on subsequent calls', () => {
    setWindowState({ authenticated: true });
    const first = consumeBootstrapData();
    // Mutate window after first consumption — service must not re-read it.
    setWindowState({ authenticated: false });

    const second = consumeBootstrapData();

    expect(second).toEqual(first);
    expect(second?.authenticated).toBe(true);
  });

  it('returns null when window state is missing', () => {
    expect(consumeBootstrapData()).toBeNull();
    expect(isBootstrapConsumed()).toBe(true);
  });
});

describe('getBootstrapValue', () => {
  it('reads from window before consumption', () => {
    setWindowState({ locale: 'de' });

    expect(getBootstrapValue('locale')).toBe('de');
    // Reading a value should not consume the snapshot.
    expect(isBootstrapConsumed()).toBe(false);
  });

  it('reads from snapshot after consumption', () => {
    setWindowState({ locale: 'es' });
    consumeBootstrapData();

    expect(getBootstrapValue('locale')).toBe('es');
  });

  it('returns undefined when no state and not consumed', () => {
    expect(getBootstrapValue('locale')).toBeUndefined();
  });
});

describe('getBootstrapSnapshot', () => {
  it('consumes window state on first call when not yet consumed', () => {
    setWindowState({ authenticated: true });

    const snapshot = getBootstrapSnapshot();

    expect(snapshot).toEqual({ authenticated: true });
    expect(isBootstrapConsumed()).toBe(true);
  });

  it('returns the cached snapshot when already consumed', () => {
    setWindowState({ authenticated: true });
    consumeBootstrapData();

    expect(getBootstrapSnapshot()).toEqual({ authenticated: true });
  });
});

describe('updateBootstrapSnapshot', () => {
  it('merges values into an existing snapshot', () => {
    setWindowState({ authenticated: false, locale: 'en' });
    consumeBootstrapData();

    updateBootstrapSnapshot({ authenticated: true, has_password: true });

    expect(getBootstrapSnapshot()).toEqual({
      authenticated: true,
      locale: 'en',
      has_password: true,
    });
  });

  it('skips undefined values without overwriting existing keys', () => {
    setWindowState({ authenticated: true, locale: 'en' });
    consumeBootstrapData();

    updateBootstrapSnapshot({
      authenticated: false,
      locale: undefined as unknown as string,
    });

    const snapshot = getBootstrapSnapshot();
    expect(snapshot?.authenticated).toBe(false);
    expect(snapshot?.locale).toBe('en');
  });

  it('consumes window state first when called before consumeBootstrapData', () => {
    // Regression for PR #3083 review feedback: calling update before consume
    // previously locked the window read out by flipping `consumed` with an
    // empty snapshot. Server-injected values must survive an early update.
    setWindowState({ authenticated: false, locale: 'en', has_password: false });

    updateBootstrapSnapshot({ authenticated: true, has_password: true });

    const snapshot = getBootstrapSnapshot();
    expect(snapshot).toEqual({
      authenticated: true,
      locale: 'en',
      has_password: true,
    });
    expect(isBootstrapConsumed()).toBe(true);
    expect((window as unknown as Record<string, unknown>)[BOOTSTRAP_KEY]).toBe(true);
  });

  it('initializes an empty snapshot when no window state and not consumed', () => {
    updateBootstrapSnapshot({ authenticated: true });

    expect(getBootstrapSnapshot()).toEqual({ authenticated: true });
    expect(isBootstrapConsumed()).toBe(true);
  });

  it('initializes an empty snapshot when consumed but window had no state', () => {
    consumeBootstrapData();
    expect(isBootstrapConsumed()).toBe(true);

    updateBootstrapSnapshot({ authenticated: true });

    expect(getBootstrapSnapshot()).toEqual({ authenticated: true });
  });

  it('preserves falsy-but-defined values (false, 0, empty string)', () => {
    setWindowState({ authenticated: true, has_password: true });
    consumeBootstrapData();

    updateBootstrapSnapshot({
      authenticated: false,
      has_password: false,
    });

    const snapshot = getBootstrapSnapshot();
    expect(snapshot?.authenticated).toBe(false);
    expect(snapshot?.has_password).toBe(false);
  });

  it('accumulates across multiple sequential calls', () => {
    setWindowState({ authenticated: false, locale: 'en' });
    consumeBootstrapData();

    updateBootstrapSnapshot({ authenticated: true });
    updateBootstrapSnapshot({ has_password: true });
    updateBootstrapSnapshot({ email: 'user@example.com' });

    expect(getBootstrapSnapshot()).toEqual({
      authenticated: true,
      locale: 'en',
      has_password: true,
      email: 'user@example.com',
    });
  });

  it('only consumes window once even when called repeatedly before consume', () => {
    // Guards against `consumed` failing to latch — a second update must not
    // re-read a now-stale window that may have been replaced or mutated.
    setWindowState({ authenticated: false, locale: 'en' });

    updateBootstrapSnapshot({ authenticated: true });
    // Mutate the window after the first update; if `consumed` failed to
    // latch, the second update would pick this up and corrupt state.
    setWindowState({ authenticated: false, locale: 'fr' });

    updateBootstrapSnapshot({ has_password: true });

    expect(getBootstrapSnapshot()).toEqual({
      authenticated: true,
      locale: 'en',
      has_password: true,
    });
    // Window marker should remain `true` (set by the single consume call),
    // not the new state we wrote between updates.
    expect((window as unknown as Record<string, unknown>)[BOOTSTRAP_KEY]).toEqual({
      authenticated: false,
      locale: 'fr',
    });
  });
});
