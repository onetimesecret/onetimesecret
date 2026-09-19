// src/utils/sessionTransition.ts
//
// One session transition, one user-facing message (#4461).
//
// A session that ended or was replaced outside this tab ends in a forced page
// load (ADR-046), which discards every piece of JavaScript state, including
// any message about why. The KIND of transition is therefore parked in
// per-tab sessionStorage just before the reload and consumed exactly once by
// the page that loads next.
//
// The parked value selects a sentence. It is never an authentication
// decision: nothing reads it to decide who is signed in.

export const SESSION_TRANSITION_KEY = 'ots_session_transition';

export const sessionTransitionValues = ['ended', 'replaced'] as const;
export type SessionTransition = (typeof sessionTransitionValues)[number];

/** Best-effort: storage may be unavailable, and the page load happens anyway. */
export function parkSessionTransition(kind: SessionTransition): void {
  try {
    window.sessionStorage.setItem(SESSION_TRANSITION_KEY, kind);
  } catch {
    // Only the one-line explanation is lost.
  }
}

/**
 * Returns the parked kind and removes it, so a second caller (or a second
 * mount) gets null. Unknown values are discarded.
 */
export function consumeSessionTransition(): SessionTransition | null {
  try {
    const raw = window.sessionStorage.getItem(SESSION_TRANSITION_KEY);
    if (raw === null) return null;
    window.sessionStorage.removeItem(SESSION_TRANSITION_KEY);
    return (sessionTransitionValues as ReadonlyArray<string>).includes(raw)
      ? (raw as SessionTransition)
      : null;
  } catch {
    return null;
  }
}
