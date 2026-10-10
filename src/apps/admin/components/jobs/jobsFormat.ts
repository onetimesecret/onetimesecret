// src/apps/admin/components/jobs/jobsFormat.ts

import type { JobRunStatus } from '@/schemas/api/internal/responses/colonel-jobs';

/**
 * Display helpers shared by the Jobs screen sections (#4343).
 *
 * Every JobRun timestamp is a Unix-SECONDS number written by the scheduler
 * process. Relative ages are computed against an explicit REFERENCE time the
 * caller captures when its data arrives — never against a clock read during
 * render — so a table does not drift while it sits on screen, "3 minutes ago"
 * means three minutes before the data was fetched, and specs can pin it.
 * (AdminSystem's `relativeAge` is anchored to the backup payload's own
 * timestamp and stays local to that view.)
 */

/** Current time as Unix seconds — the reference a section captures on load. */
export function nowSeconds(): number {
  return Math.floor(Date.now() / 1000);
}

/**
 * Relative age of `timestamp` as seen from `reference` ("5 minutes ago",
 * "in 2 hours"). Future timestamps (a next-due time) read forward.
 *
 * @param timestamp Unix seconds, or null when nothing was recorded.
 * @param reference Unix seconds the age is measured from.
 * @returns the localised phrase, or an em dash for a missing timestamp.
 */
export function relativeAge(timestamp: number | null, reference: number): string {
  if (timestamp === null) return '—';
  const delta = timestamp - reference;
  const abs = Math.abs(delta);
  const formatter = new Intl.RelativeTimeFormat(undefined, { numeric: 'auto' });
  if (abs < 60) return formatter.format(delta, 'second');
  if (abs < 3600) return formatter.format(Math.round(delta / 60), 'minute');
  if (abs < 86_400) return formatter.format(Math.round(delta / 3600), 'hour');
  return formatter.format(Math.round(delta / 86_400), 'day');
}

/** Absolute UTC instant for a `title` tooltip beside a relative age. */
export function utcTimestamp(timestamp: number | null): string | undefined {
  return timestamp === null ? undefined : new Date(timestamp * 1000).toISOString();
}

/** A run duration: milliseconds below one second, seconds above. */
export function formatDurationMs(ms: number | null): string {
  if (ms === null) return '—';
  if (ms < 1000) {
    return new Intl.NumberFormat(undefined, {
      style: 'unit',
      unit: 'millisecond',
      unitDisplay: 'short',
    }).format(ms);
  }
  return new Intl.NumberFormat(undefined, {
    style: 'unit',
    unit: 'second',
    unitDisplay: 'short',
    maximumFractionDigits: 1,
  }).format(ms / 1000);
}

const BADGE_NEUTRAL = 'bg-gray-100 text-gray-700 dark:bg-gray-800 dark:text-gray-300';
const BADGE_GOOD = 'bg-green-100 text-green-800 dark:bg-green-900/40 dark:text-green-200';
const BADGE_ACTIVE = 'bg-brand-100 text-brand-800 dark:bg-brand-900/40 dark:text-brand-200';
/**
 * Failures read amber, not red: on this screen red is reserved for the one
 * destructive action (discarding a message), so a red badge never competes
 * with a red button.
 */
const BADGE_ATTENTION = 'bg-amber-100 text-amber-800 dark:bg-amber-900/40 dark:text-amber-200';

/** Badge classes for a last-run status. */
export function runStatusBadgeClass(status: JobRunStatus): string {
  switch (status) {
    case 'success':
      return BADGE_GOOD;
    case 'running':
      return BADGE_ACTIVE;
    case 'error':
      return BADGE_ATTENTION;
    default:
      return BADGE_NEUTRAL;
  }
}

/** Badge classes for a job's registration state on the running scheduler. */
export function jobStateBadgeClass(state: 'scheduled' | 'not_scheduled' | 'unknown'): string {
  switch (state) {
    case 'scheduled':
      return BADGE_GOOD;
    case 'unknown':
      return BADGE_ATTENTION;
    default:
      return BADGE_NEUTRAL;
  }
}
