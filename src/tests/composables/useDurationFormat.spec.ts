// src/tests/composables/useDurationFormat.spec.ts

/**
 * useDurationFormat — how a lifetime in seconds is shown.
 *
 * The display must never obscure the real value: a duration that is not a
 * whole number of one unit is shown as an exact compound, never rounded.
 */

import { describe, expect, it, vi } from 'vitest';

// Renders keys and params, not English: a unit is `<count>~<key>#<plural n>`
// and a compound is `[head + tail]`.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key: string, arg?: unknown) => {
      if (typeof arg === 'number') return `${key}#${arg}`;
      const params = (arg ?? {}) as Record<string, unknown>;
      if (key === 'web.UNITS.ttl.duration') return `${params.count}~${params.unit}`;
      if (key === 'web.UNITS.ttl.duration_compound') return `[${params.head} + ${params.tail}]`;
      return key;
    },
  }),
}));

import { durationParts, useDurationFormat } from '@/shared/composables/useDurationFormat';

const unit = (name: string, count: number) => `${count}~web.UNITS.ttl.time.${name}#${count}`;

describe('durationParts', () => {
  it.each([
    [3600, [{ unit: 'hour', count: 1 }]],
    [90000, [{ unit: 'hour', count: 25 }]],
    [604800, [{ unit: 'day', count: 7 }]],
    [86400, [{ unit: 'day', count: 1 }]],
    [1209600, [{ unit: 'day', count: 14 }]],
    [2592000, [{ unit: 'day', count: 30 }]],
    [300, [{ unit: 'minute', count: 5 }]],
    [45, [{ unit: 'second', count: 45 }]],
  ])('shows %i seconds as a single part in the largest whole unit', (seconds, parts) => {
    expect(durationParts(seconds)).toEqual(parts);
  });

  it.each([
    [3602, [{ unit: 'hour', count: 1 }, { unit: 'second', count: 2 }]],
    [90540, [{ unit: 'hour', count: 25 }, { unit: 'minute', count: 9 }]],
    [61, [{ unit: 'minute', count: 1 }, { unit: 'second', count: 1 }]],
    [90, [{ unit: 'minute', count: 1 }, { unit: 'second', count: 30 }]],
    [
      93784,
      [
        { unit: 'hour', count: 26 },
        { unit: 'minute', count: 3 },
        { unit: 'second', count: 4 },
      ],
    ],
  ])('shows %i seconds as an exact compound with zero parts left out', (seconds, parts) => {
    expect(durationParts(seconds)).toEqual(parts);
  });

  it('never uses days in a compound, so the parts lead with hours', () => {
    // 1 day + 1 second
    expect(durationParts(86401)).toEqual([
      { unit: 'hour', count: 24 },
      { unit: 'second', count: 1 },
    ]);
  });

  it('always adds up to the exact value', () => {
    const size = { day: 86400, hour: 3600, minute: 60, second: 1 };
    for (const seconds of [1, 59, 60, 61, 3599, 3600, 3602, 86399, 86400, 90000, 90540, 604799]) {
      const total = durationParts(seconds).reduce((sum, p) => sum + p.count * size[p.unit], 0);
      expect(total).toBe(seconds);
    }
  });

  it.each([0, -5, 1.5])('returns %d unchanged, in seconds', (seconds) => {
    expect(durationParts(seconds)).toEqual([{ unit: 'second', count: seconds }]);
  });
});

describe('useDurationFormat', () => {
  const { formatDuration } = useDurationFormat();

  it('formats a whole number of one unit with the pluralized unit key', () => {
    expect(formatDuration(3600)).toBe(unit('hour', 1));
    expect(formatDuration(90000)).toBe(unit('hour', 25));
    expect(formatDuration(604800)).toBe(unit('day', 7));
  });

  it('joins compound parts with the compound key, in order', () => {
    expect(formatDuration(3602)).toBe(`[${unit('hour', 1)} + ${unit('second', 2)}]`);
    expect(formatDuration(90540)).toBe(`[${unit('hour', 25)} + ${unit('minute', 9)}]`);
    expect(formatDuration(61)).toBe(`[${unit('minute', 1)} + ${unit('second', 1)}]`);
    expect(formatDuration(93784)).toBe(
      `[[${unit('hour', 26)} + ${unit('minute', 3)}] + ${unit('second', 4)}]`
    );
  });

  it('does not round 3602 down to an hour', () => {
    expect(formatDuration(3602)).not.toBe(formatDuration(3600));
  });
});
