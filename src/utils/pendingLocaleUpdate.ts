import { z } from 'zod';

const pendingLocaleUpdateSchema = z.object({
  id: z.string().min(1),
  locale: z.string().min(1),
  accountExtid: z.string().min(1).nullable(),
  createdAt: z.number().finite(),
});

export type PendingLocaleUpdate = z.infer<typeof pendingLocaleUpdateSchema>;

// Recovery is for the next page load, not a preference queued for a later visit.
const MAX_AGE_MS = 5 * 60_000;
const key = (selectionKey: string) => `${selectionKey}.pending-update`;

/** Returns an ownership token so an older switch cannot clear a newer one. */
export function storePendingLocaleUpdate(
  selectionKey: string,
  locale: string,
  accountExtid: string | null
): string | null {
  try {
    const token = JSON.stringify({
      id: crypto.randomUUID(),
      locale,
      accountExtid,
      createdAt: Date.now(),
    } satisfies PendingLocaleUpdate);
    sessionStorage.setItem(key(selectionKey), token);
    return token;
  } catch {
    // A blocked storage API must not prevent an ordinary language switch.
    return null;
  }
}

export function clearPendingLocaleUpdate(selectionKey: string, token?: string | null): void {
  try {
    const storageKey = key(selectionKey);
    if (token === undefined || (token !== null && sessionStorage.getItem(storageKey) === token)) {
      sessionStorage.removeItem(storageKey);
    }
  } catch {
    // Recovery remains optional when browser storage is unavailable.
  }
}

/** Consume before awaiting anything: a failed recovery is never queued again. */
export function takePendingLocaleUpdate(selectionKey: string): PendingLocaleUpdate | null {
  try {
    const stored = sessionStorage.getItem(key(selectionKey));
    if (!stored) return null;
    sessionStorage.removeItem(key(selectionKey));
    const parsed = pendingLocaleUpdateSchema.safeParse(JSON.parse(stored));
    if (!parsed.success) return null;
    const age = Date.now() - parsed.data.createdAt;
    return age >= 0 && age <= MAX_AGE_MS ? parsed.data : null;
  } catch {
    return null;
  }
}
