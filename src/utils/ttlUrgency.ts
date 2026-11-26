// src/utils/ttlUrgency.ts

/**
 * The lifetime that remaining time is measured against when deciding whether
 * a secret is close to expiring: 7 days.
 *
 * This is a fixed reference, not the configured maximum lifetime. The secret
 * lists mark a row urgent when its remaining time is at most a quarter of
 * this (42 hours). Measuring against the caller's lifetime ceiling instead
 * would move that threshold with the plan: under a 30-day ceiling a new
 * 7-day secret would be urgent from the moment it was created.
 */
export const TTL_URGENCY_REFERENCE_SECONDS = 604800;

/**
 * Remaining lifetime as a whole percentage of the 7-day reference. Above 100
 * for a secret with more than 7 days left.
 */
export function ttlPercentage(ttlSeconds: number): number {
  return Math.floor((ttlSeconds / TTL_URGENCY_REFERENCE_SECONDS) * 100);
}
