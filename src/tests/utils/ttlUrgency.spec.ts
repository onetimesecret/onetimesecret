// src/tests/utils/ttlUrgency.spec.ts

import { describe, expect, it } from 'vitest';

import { TTL_URGENCY_REFERENCE_SECONDS, ttlPercentage } from '@/utils/ttlUrgency';

describe('ttlPercentage', () => {
  it('measures against a fixed 7-day reference', () => {
    expect(TTL_URGENCY_REFERENCE_SECONDS).toBe(7 * 86400);
    expect(ttlPercentage(7 * 86400)).toBe(100);
  });

  // The secret lists mark a row urgent at 25% or less: 42 hours.
  it.each([
    [42 * 3600, 25],
    [42 * 3600 + 1, 25],
    [43 * 3600, 25],
    [44 * 3600, 26],
    [3600, 0],
    [0, 0],
  ])('floors %i seconds to %i%%', (seconds, percentage) => {
    expect(ttlPercentage(seconds)).toBe(percentage);
  });

  it('exceeds 100 for a secret with more than 7 days left', () => {
    expect(ttlPercentage(30 * 86400)).toBe(428);
  });

  it('is negative for the -1 a revealed secret carries', () => {
    expect(ttlPercentage(-1)).toBe(-1);
  });
});
