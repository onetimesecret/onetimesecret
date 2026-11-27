// src/tests/composables/useDurationFormat.spec.ts

import { describe, expect, it, vi } from 'vitest';

const UNITS: Record<string, [string, string]> = {
  day: ['day', 'days'],
  hour: ['hour', 'hours'],
  minute: ['minute', 'minutes'],
  second: ['second', 'seconds'],
};

// Resolves the two web.UNITS.ttl keys the formatter uses, so the assertions
// read as English instead of raw keys.
vi.mock('vue-i18n', async () => {
  const { ref } = await import('vue');
  return { useI18n: () => ({
    locale: ref('en'),
    t: (key: string, arg: unknown) => {
      if (key === 'web.UNITS.ttl.duration') {
        const { count, unit } = arg as { count: number; unit: string };
        return `${count} ${unit}`;
      }
      const [one, many] = UNITS[key.split('.').pop() as string];
      return arg === 1 ? one : many;
    },
  }) };
});

import {
  durationParts,
  joinDurationParts,
  useDurationFormat,
} from '@/shared/composables/useDurationFormat';

describe('durationParts', () => {
  it.each([
    [604800, [{ unit: 'day', count: 7 }]],
    [90000, [{ unit: 'hour', count: 25 }]],
    [90540, [{ unit: 'hour', count: 25 }, { unit: 'minute', count: 9 }]],
    [3602, [{ unit: 'hour', count: 1 }, { unit: 'second', count: 2 }]],
    [59, [{ unit: 'second', count: 59 }]],
    [0, []],
  ])('%i -> %j', (seconds, expected) => {
    expect(durationParts(seconds)).toEqual(expected);
  });

  it.each([
    [86400, [{ unit: 'day', count: 1 }]],
    [2592000, [{ unit: 'day', count: 30 }]],
    [300, [{ unit: 'minute', count: 5 }]],
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
  ])('%i -> %j', (seconds, expected) => {
    expect(durationParts(seconds)).toEqual(expected);
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
});

describe('formatDuration', () => {
  const { formatDuration } = useDurationFormat();

  it.each([
    [604800, '7 days'],
    [90000, '25 hours'],
    [90540, '25 hours, 9 minutes'],
    [3602, '1 hour, 2 seconds'],
    [59, '59 seconds'],
    [3600, '1 hour'],
    [0, '0 seconds'],
  ])('%i -> %s', (seconds, expected) => {
    expect(formatDuration(seconds)).toBe(expected);
  });
});

describe('joinDurationParts', () => {
  it('accepts the app\'s underscore locale codes', () => {
    expect(joinDurationParts(['1 a', '2 b'], 'pt_BR')).toBe('1 a e 2 b');
  });

  it('uses English when no locale is known', () => {
    expect(joinDurationParts(['1 a', '2 b'], undefined)).toBe('1 a, 2 b');
  });

  it('falls back to English for a tag Intl rejects', () => {
    expect(joinDurationParts(['1 a', '2 b'], 'not a tag!')).toBe('1 a, 2 b');
  });
});
