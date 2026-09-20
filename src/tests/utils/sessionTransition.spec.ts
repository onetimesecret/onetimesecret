// src/tests/utils/sessionTransition.spec.ts
//
// #4461: one session transition produces exactly one user-facing message.
// §5, PR #4497 item 16: parked messages carry a TTL so a cancelled reload
// (or a beforeunload prompt the user rejected) cannot leave a stale one-liner
// waiting for the next mount.

import {
  clearSessionTransition,
  consumeSessionTransition,
  parkSessionTransition,
  SESSION_TRANSITION_KEY,
  SESSION_TRANSITION_TTL_MS,
} from '@/utils/sessionTransition';
import { beforeEach, describe, expect, it } from 'vitest';

describe('session transition parking', () => {
  beforeEach(() => sessionStorage.clear());

  it('is consumed exactly once', () => {
    parkSessionTransition('ended');

    expect(consumeSessionTransition()).toBe('ended');
    expect(consumeSessionTransition()).toBeNull();
    expect(sessionStorage.getItem(SESSION_TRANSITION_KEY)).toBeNull();
  });

  it('holds one kind: a later transition replaces an unconsumed one', () => {
    parkSessionTransition('ended');
    parkSessionTransition('replaced');

    expect(consumeSessionTransition()).toBe('replaced');
    expect(consumeSessionTransition()).toBeNull();
  });

  it('discards a value it does not know, and removes it', () => {
    sessionStorage.setItem(SESSION_TRANSITION_KEY, 'authenticated');

    expect(consumeSessionTransition()).toBeNull();
    expect(sessionStorage.getItem(SESSION_TRANSITION_KEY)).toBeNull();
  });

  it('is empty when nothing was parked', () => {
    expect(consumeSessionTransition()).toBeNull();
  });

  // §5 regression: TTL guards a park that outlived its reload attempt.
  describe('TTL (§5, PR #4497)', () => {
    it('discards a park older than SESSION_TRANSITION_TTL_MS', () => {
      const parkedAt = 0;
      parkSessionTransition('ended', parkedAt);

      // A cancelled reload later: consume at t = 65s.
      const later = parkedAt + SESSION_TRANSITION_TTL_MS + 5_000;
      expect(consumeSessionTransition(later)).toBeNull();
      // And the stale entry is removed on read.
      expect(sessionStorage.getItem(SESSION_TRANSITION_KEY)).toBeNull();
    });

    it('is still fresh at exactly the TTL boundary', () => {
      const parkedAt = 1000;
      parkSessionTransition('replaced', parkedAt);
      expect(consumeSessionTransition(parkedAt + SESSION_TRANSITION_TTL_MS)).toBe('replaced');
    });

    it('is consumed within milliseconds on a real reload path', () => {
      const parkedAt = 1000;
      parkSessionTransition('ended', parkedAt);
      // A real reload consumes on the next paint, well inside the window.
      expect(consumeSessionTransition(parkedAt + 5)).toBe('ended');
    });

    it('a legacy bare-string value (pre-TTL) is still honoured once', () => {
      // A leftover from a session before this change: no parkedAt, no age check.
      sessionStorage.setItem(SESSION_TRANSITION_KEY, 'ended');

      expect(consumeSessionTransition()).toBe('ended');
      expect(consumeSessionTransition()).toBeNull();
    });

    it('a malformed JSON value is discarded', () => {
      sessionStorage.setItem(SESSION_TRANSITION_KEY, '{not:json');

      expect(consumeSessionTransition()).toBeNull();
      expect(sessionStorage.getItem(SESSION_TRANSITION_KEY)).toBeNull();
    });

    it('clearSessionTransition removes a parked value (fast-path)', () => {
      parkSessionTransition('ended');
      clearSessionTransition();

      expect(sessionStorage.getItem(SESSION_TRANSITION_KEY)).toBeNull();
      expect(consumeSessionTransition()).toBeNull();
    });
  });
});
