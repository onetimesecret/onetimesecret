// src/shared/composables/useDurationFormat.ts

import { useI18n } from 'vue-i18n';

export type DurationUnit = 'day' | 'hour' | 'minute' | 'second';

export interface DurationPart {
  unit: DurationUnit;
  count: number;
}

const DAY = 86400;
const HOUR = 3600;
const MINUTE = 60;

/**
 * Splits a number of seconds into the parts shown for a duration. The parts
 * always add up to exactly `seconds`: the display never rounds.
 *
 * - A whole number of one unit is a single part in the largest such unit:
 *   3600 is 1 hour, 90000 is 25 hours, 604800 is 7 days.
 * - Anything else is an exact compound of hours, minutes and seconds with
 *   zero parts left out: 3602 is 1 hour 2 seconds, 90540 is 25 hours
 *   9 minutes. Days appear only for a whole number of days, so a compound
 *   leads with hours.
 * - A value that is not a positive whole number of seconds is returned as a
 *   single part in seconds, unchanged.
 */
export function durationParts(seconds: number): DurationPart[] {
  if (!Number.isInteger(seconds) || seconds < 1) {
    return [{ unit: 'second', count: seconds }];
  }

  if (seconds % DAY === 0) {
    return [{ unit: 'day', count: seconds / DAY }];
  }

  const candidates: DurationPart[] = [
    { unit: 'hour', count: Math.floor(seconds / HOUR) },
    { unit: 'minute', count: Math.floor((seconds % HOUR) / MINUTE) },
    { unit: 'second', count: seconds % MINUTE },
  ];
  return candidates.filter((part) => part.count > 0);
}

/**
 * Formats a duration in seconds for display with the pluralized
 * `web.UNITS.ttl.*` keys. See durationParts for the rule. Display only: the
 * value itself is never changed.
 */
export function useDurationFormat() {
  const { t } = useI18n();

  const formatPart = ({ unit, count }: DurationPart): string =>
    t('web.UNITS.ttl.duration', {
      count,
      unit: t(`web.UNITS.ttl.time.${unit}`, count),
    });

  const formatDuration = (seconds: number): string =>
    durationParts(seconds)
      .map(formatPart)
      .reduce((head, tail) => t('web.UNITS.ttl.duration_compound', { head, tail }));

  return { formatDuration };
}
