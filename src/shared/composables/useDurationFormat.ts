// src/shared/composables/useDurationFormat.ts

import { unref } from 'vue';
import { useI18n } from 'vue-i18n';

export type DurationUnit = 'day' | 'hour' | 'minute' | 'second';

export interface DurationPart {
  unit: DurationUnit;
  count: number;
}

const DAY = 86400;

const SUB_DAY_UNITS: ReadonlyArray<[DurationUnit, number]> = [
  ['hour', 3600],
  ['minute', 60],
];

/**
 * Splits a duration into exact parts, largest unit first, with zero parts
 * left out. Nothing is rounded: 3602 is 1 hour and 2 seconds, not 1 hour.
 * Days are used only for a whole number of days; anything else is hours,
 * minutes and seconds (90000 is 25 hours, 90540 is 25 hours and 9 minutes).
 * An empty list means zero seconds.
 */
export function durationParts(seconds: number): DurationPart[] {
  if (seconds >= DAY && Number.isInteger(seconds / DAY)) {
    return [{ unit: 'day', count: seconds / DAY }];
  }
  const parts: DurationPart[] = [];
  let rest = seconds;
  for (const [unit, size] of SUB_DAY_UNITS) {
    const count = Math.floor(rest / size);
    if (count >= 1) {
      parts.push({ unit, count });
      rest -= count * size;
    }
  }
  if (rest > 0) parts.push({ unit: 'second', count: rest });
  return parts;
}

/**
 * Joins already-translated duration parts with the locale's own unit-list
 * pattern (English: "25 hours, 9 minutes"). The app's locale codes use
 * underscores (pt_BR), which Intl does not accept, so they are converted.
 */
export function joinDurationParts(parts: string[], locale: string | undefined): string {
  const tag = (locale || 'en').replace(/_/g, '-');
  try {
    return new Intl.ListFormat(tag, { style: 'long', type: 'unit' }).format(parts);
  } catch {
    return new Intl.ListFormat('en', { style: 'long', type: 'unit' }).format(parts);
  }
}

/**
 * Formats a duration in seconds for display with the web.UNITS.ttl keys.
 */
export function useDurationFormat() {
  const { t, locale } = useI18n();

  const formatPart = (count: number, unit: DurationUnit): string =>
    t('web.UNITS.ttl.duration', {
      count,
      unit: t(`web.UNITS.ttl.time.${unit}`, count),
    });

  const formatDuration = (seconds: number): string => {
    const parts = durationParts(seconds);
    if (parts.length === 0) return formatPart(0, 'second');
    return joinDurationParts(
      parts.map(({ count, unit }) => formatPart(count, unit)),
      unref(locale)
    );
  };

  return { formatDuration };
}
