// src/apps/admin/utils/elevationCountdown.ts

/**
 * The step-up window's remaining time as `m:ss` (#4327).
 *
 * Shared by ElevationBanner and the header ElevationControl so the two read
 * the same figure. Pure formatting: the seconds come from
 * useColonelElevation's local countdown, which issues no HTTP (see that
 * composable's doc block for why no timer here may make a request).
 *
 * @param totalSeconds seconds left; negative or fractional input is clamped
 *   to whole seconds at or above zero
 */
export function formatElevationCountdown(totalSeconds: number): string {
  const total = Math.max(0, Math.floor(totalSeconds));
  const minutes = Math.floor(total / 60);
  const seconds = total % 60;
  return `${minutes}:${String(seconds).padStart(2, '0')}`;
}
