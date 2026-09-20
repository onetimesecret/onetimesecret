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
//
// TTL (§5, PR #4497): reload() only requests navigation, so the parked
// message can outlive a cancelled reload (the user hit "Stay") or a
// beforeunload prompt the browser suppressed. The parked value carries its
// own parkedAt timestamp and is discarded on read if older than
// SESSION_TRANSITION_TTL_MS. The auth store also removes the key on a
// successful reconciliation to the same or newer generation (fast-path).

export const SESSION_TRANSITION_KEY = 'ots_session_transition';

/** How long a parked message is considered fresh. A real reload consumes it in ms. */
export const SESSION_TRANSITION_TTL_MS = 60 * 1000;

export const sessionTransitionValues = ['ended', 'replaced'] as const;
export type SessionTransition = (typeof sessionTransitionValues)[number];

interface ParkedTransition {
  cause: SessionTransition;
  parkedAt: number;
}

function isParkedTransition(value: unknown): value is ParkedTransition {
  if (typeof value !== 'object' || value === null) return false;
  const candidate = value as { cause?: unknown; parkedAt?: unknown };
  return (
    typeof candidate.parkedAt === 'number' &&
    typeof candidate.cause === 'string' &&
    (sessionTransitionValues as ReadonlyArray<string>).includes(candidate.cause)
  );
}

/** Best-effort: storage may be unavailable, and the page load happens anyway. */
export function parkSessionTransition(
  kind: SessionTransition,
  now: number = Date.now()
): void {
  try {
    const payload: ParkedTransition = { cause: kind, parkedAt: now };
    window.sessionStorage.setItem(SESSION_TRANSITION_KEY, JSON.stringify(payload));
  } catch {
    // Only the one-line explanation is lost.
  }
}

/**
 * Returns the parked kind and removes it, so a second caller (or a second
 * mount) gets null. Unknown values are discarded, and a stamp older than
 * SESSION_TRANSITION_TTL_MS is treated as stale.
 *
 * Also accepts a legacy plain-string value (pre-TTL park). A legacy value has
 * no parkedAt, so it is honoured but consumed exactly once with no age check
 * — a leftover from a session before this change.
 */
export function consumeSessionTransition(
  now: number = Date.now()
): SessionTransition | null {
  try {
    const raw = window.sessionStorage.getItem(SESSION_TRANSITION_KEY);
    if (raw === null) return null;
    window.sessionStorage.removeItem(SESSION_TRANSITION_KEY);

    // Legacy: a bare string from before the TTL fix. Consume it once.
    if ((sessionTransitionValues as ReadonlyArray<string>).includes(raw)) {
      return raw as SessionTransition;
    }

    let parsed: unknown;
    try {
      parsed = JSON.parse(raw);
    } catch {
      return null;
    }
    if (!isParkedTransition(parsed)) return null;
    if (now - parsed.parkedAt > SESSION_TRANSITION_TTL_MS) return null;
    return parsed.cause;
  } catch {
    return null;
  }
}

/**
 * Removes any parked transition, best-effort. Called from the auth store on a
 * successful reconciliation: if the tab has landed a fresh snapshot without a
 * reload, the parked "your session ended" message is no longer the resolution.
 */
export function clearSessionTransition(): void {
  try {
    window.sessionStorage.removeItem(SESSION_TRANSITION_KEY);
  } catch {
    /* storage unavailable; the TTL will still discard it eventually */
  }
}
