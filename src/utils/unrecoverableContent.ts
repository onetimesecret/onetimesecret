// src/utils/unrecoverableContent.ts
//
// A page that shows a value the server will not serve again registers here
// while the value is on screen: a revealed secret (the reveal request destroys
// it, apps/api/v2/logic/secrets/reveal_secret.rb) or the one-time display of a
// generated value on the receipt page (consumed by claim_secret_value_display!
// in show_receipt.rb).
// Reloading such a page shows "viewed or expired", and the copy in the tab was
// the only one. attemptForcedPageLoad (src/utils/forcedPageLoad.ts) refuses
// every automatic reload while a mark is active: a failed chunk leaves its
// import to fail (src/utils/preloadError.ts), and an ended or replaced session
// stays in the stale-session notice. The user can still reload by hand.

let active = 0;

/**
 * Marks the page as showing unrecoverable content. Returns the release
 * function; releasing twice is a no-op.
 */
export function markUnrecoverableContent(): () => void {
  active += 1;
  let released = false;
  return () => {
    if (released) return;
    released = true;
    active -= 1;
  };
}

/** True while at least one mark is active. */
export function hasUnrecoverableContent(): boolean {
  return active > 0;
}
