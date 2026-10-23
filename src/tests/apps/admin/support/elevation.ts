// src/tests/apps/admin/support/elevation.ts

import {
  __resetColonelElevationState,
  useColonelElevation,
} from '@/apps/admin/composables/useColonelElevation';

/**
 * Start a spec from a LIVE step-up window (#4327), as an operator who already
 * elevated.
 *
 * Tier-1 openers call `ensureElevated()` before their confirmation dialog, so
 * a spec about the dialog itself (typed token, reason, server errors) needs a
 * live window or the sudo prompt opens instead. Specs about the pre-prompt
 * call `__resetColonelElevationState()` instead and stay unelevated.
 *
 * Sets the shared refs directly, so no countdown timer starts. The calling
 * spec must mock `@/shared/composables/useApi`: useColonelElevation injects it
 * on first use.
 */
export function startElevated(seconds = 600): void {
  __resetColonelElevationState();
  const elevation = useColonelElevation();
  elevation.elevated.value = true;
  elevation.expiresAt.value = Math.floor(Date.now() / 1000) + seconds;
  elevation.secondsRemaining.value = seconds;
}
