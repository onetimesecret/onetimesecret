// src/tests/utils/sessionTransition.spec.ts
//
// #4461: one session transition produces exactly one user-facing message.

import {
  consumeSessionTransition,
  parkSessionTransition,
  SESSION_TRANSITION_KEY,
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
});
