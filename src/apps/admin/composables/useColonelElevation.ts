// src/apps/admin/composables/useColonelElevation.ts

import type { AxiosInstance } from 'axios';
import { computed, ref, type ComputedRef, type Ref } from 'vue';

import {
  colonelElevationGrantResponseSchema,
  colonelElevationStatusResponseSchema,
} from '@/schemas/api/internal/responses/colonel-elevation';
import { colonelReauthenticateResponseSchema } from '@/schemas/api/internal/responses/colonel-reauthenticate';
import { classifyError } from '@/schemas/errors';
import { useApi } from '@/shared/composables/useApi';
import { useAuthStore, type RefreshReason } from '@/shared/stores/authStore';
import { gracefulParse } from '@/utils/schemaValidation';

import {
  adminSessionExpired,
  clearAdminSessionExpired,
  noteAdminSessionExpiry,
} from '../utils/adminSessionExpiry';

const ELEVATION_URL = '/api/colonel/elevation';
const REAUTHENTICATE_URL = '/api/colonel/reauthenticate';

/**
 * The colonel step-up (sudo) window, as the console sees it (#4327).
 *
 * MODULE-LEVEL state, deliberately: the banner in AdminLayout, the sudo prompt,
 * and every destructive mutation across the console must share ONE view of
 * elevation. A per-component composable would let a mutation believe it is
 * unelevated while the banner counts down beside it.
 *
 * ## It does not poll, and nothing here may start a timer that makes a request
 *
 * `Onetime::Operations::Sessions::TrackMetadata` runs from
 * `Onetime::Session#write_session` on essentially every authenticated request
 * and unconditionally advances `last_activity_at` — which is exactly the value
 * the admin idle timeout (#4331) reads. A banner polling GET /api/colonel/elevation
 * would re-stamp it forever, so the idle timeout could never fire while an admin
 * tab was open: dead on arrival in the only configuration that matters.
 *
 * So: {@link refresh} runs on admin mount, after every elevate/drop, and when a
 * 403 `elevation_required` arrives. The countdown between those is computed
 * CLIENT-SIDE from `expiresAt` by a `setInterval` that issues NO HTTP and, at
 * zero, flips `elevated` to false locally.
 *
 * There is no other timer anywhere under `src/apps/admin/`, so an idle admin tab
 * genuinely makes no requests. That is a load-bearing property of a shipped
 * security control, not a style preference. Do not add one.
 *
 * ## A granted window comes with a new session id
 *
 * The server moves the session to a new id when it grants the window (#4466,
 * `ColonelAPI::Logic::Colonel::ElevateSession`), and the response sets the new
 * cookie. The CSRF token is carried across, so nothing changes for the next
 * API call. The bootstrap snapshot epoch is derived from the id (ADR-046), so
 * {@link elevate} asks the auth store for one snapshot as an authentication
 * mutation, which adopts the new epoch in place. Left to the next ordinary
 * refresh, the new epoch would read as a session replaced elsewhere and force
 * a page load. That is one request per granted window, not a timer.
 *
 * ## Elevate before the dialog, not after the refusal
 *
 * A tier-1 verb's opener calls {@link ensureElevated} BEFORE its confirmation
 * dialog opens (see useAdminDestructiveMutation), so the operator proves the
 * credential first and fills in the reason and typed token once. The 403
 * `elevation_required` loop stays as the fallback for a window that lapses
 * while the dialog is open; {@link noteElevationRequired} lets that 403
 * overrule a local countdown that still reads live.
 *
 * ## Recovering an expired admin session by password
 *
 * {@link reauthenticate} posts the operator's password to the one /api/colonel
 * route exempt from the admin session bound (#4331). It is an operator
 * gesture, never a timer, and it does not grant a step-up window.
 */

// ─── Module-level singleton state ────────────────────────────────────────────

const elevated = ref(false);
const expiresAt = ref<number | null>(null);
const secondsRemaining = ref(0);
const enabled = ref(true);
const window_ = ref(600);
const reauthGrace = ref(0);
const graceAvailable = ref(false);
const passwordAvailable = ref(true);
const factors = ref<string[]>(['password']);
/** The factor the LIVE window was minted with, when this tab minted it. */
const activeFactor = ref<string | null>(null);
const loading = ref(false);
const error = ref<string | null>(null);

/**
 * Expired-session re-authentication (#4331). Separate from `loading`/`error`:
 * those belong to the sudo prompt, and the elevation status refresh clears
 * `error` on every run.
 */
const reauthLoading = ref(false);
const reauthError = ref<string | null>(null);

/** Prompt state, shared so ONE ElevationPrompt instance can serve the console. */
const promptOpen = ref(false);
let promptResolve: ((elevated: boolean) => void) | null = null;

let countdownTimer: ReturnType<typeof setInterval> | null = null;
let api: AxiosInstance | null = null;

function stopCountdown(): void {
  if (countdownTimer === null) return;
  clearInterval(countdownTimer);
  countdownTimer = null;
}

/**
 * Recompute `secondsRemaining` from `expiresAt` locally. Issues no HTTP — see
 * the module doc block for why that is mandatory rather than an optimisation.
 */
function tick(): void {
  if (expiresAt.value === null) {
    secondsRemaining.value = 0;
    elevated.value = false;
    stopCountdown();
    return;
  }
  const remaining = Math.max(0, expiresAt.value - Math.floor(Date.now() / 1000));
  secondsRemaining.value = remaining;
  if (remaining === 0) {
    elevated.value = false;
    expiresAt.value = null;
    activeFactor.value = null;
    stopCountdown();
  }
}

function startCountdown(): void {
  stopCountdown();
  if (!elevated.value || expiresAt.value === null) return;
  countdownTimer = setInterval(tick, 1000);
}

interface ElevationRecordLike {
  elevated: boolean;
  expires_at: number | null;
  seconds_remaining: number;
}

function applyRecord(record: ElevationRecordLike): void {
  elevated.value = record.elevated;
  expiresAt.value = record.expires_at;
  secondsRemaining.value = record.seconds_remaining;
  if (record.elevated) startCountdown();
  else {
    stopCountdown();
    activeFactor.value = null;
  }
}

/**
 * The Axios instance, injected once by the first {@link useColonelElevation}
 * call inside a component. Module-level like the state it serves.
 */
function client(): AxiosInstance {
  if (!api) throw new Error('useColonelElevation(): call it from a component before using it.');
  return api;
}

/** GET the current window and this account's capability. */
async function refresh(): Promise<void> {
  loading.value = true;
  error.value = null;
  try {
    const response = await client().get(ELEVATION_URL);
    const parsed = gracefulParse(
      colonelElevationStatusResponseSchema,
      response.data,
      'ColonelElevationStatusResponse'
    );
    if (!parsed.ok) return;

    const { record, details } = parsed.data;
    if (record) applyRecord(record);
    if (!details) return;

    enabled.value = details.enabled;
    window_.value = details.window;
    reauthGrace.value = details.reauth_grace;
    graceAvailable.value = details.grace_available;
    passwordAvailable.value = details.password_available;
    factors.value = details.factors;
  } catch (err) {
    // This is the FIRST request the console makes on entry, so it is usually
    // where an expired admin window (#4331) is discovered.
    noteAdminSessionExpiry(err);
    error.value = classifyError(err).message;
  } finally {
    loading.value = false;
  }
}

/**
 * Mint a window. Returns false on failure with the server's remediation message
 * in {@link error} — that message distinguishes "wrong password" from "this
 * account cannot use that factor", which is what the prompt renders.
 */
async function elevate(factor: string, password?: string): Promise<boolean> {
  loading.value = true;
  error.value = null;
  try {
    const response = await client().post(ELEVATION_URL, { factor, password: password ?? '' });
    const parsed = gracefulParse(
      colonelElevationGrantResponseSchema,
      response.data,
      'ColonelElevationGrantResponse'
    );
    if (parsed.ok) {
      if (parsed.data.record) applyRecord(parsed.data.record);
      activeFactor.value = parsed.data.details?.factor ?? factor;
    }
    await adoptRenewedSession('elevation');
    return true;
  } catch (err) {
    error.value = classifyError(err).message;
    return false;
  } finally {
    loading.value = false;
    // A 2xx already told us the truth, but schema drift must not leave a stale
    // window on screen. No refresh on the failure path: nothing changed.
    if (!error.value) await refresh();
  }
}

/**
 * Adopt the session id the server moved this session to on a granted window
 * or a re-authentication (see the module doc). `refresh()` reports its own
 * failures through its outcome; a throw here (no active Pinia) must not turn a
 * success into an error in the prompt.
 */
async function adoptRenewedSession(
  reason: Extract<RefreshReason, 'elevation' | 'reauth'>
): Promise<void> {
  try {
    await useAuthStore().refresh({ kind: 'auth-mutation', reason });
  } catch {
    // The next ordinary refresh still reconciles, by a page load.
  }
}

async function drop(): Promise<boolean> {
  loading.value = true;
  error.value = null;
  try {
    await client().delete(ELEVATION_URL);
    applyRecord({ elevated: false, expires_at: null, seconds_remaining: 0 });
    return true;
  } catch (err) {
    error.value = classifyError(err).message;
    return false;
  } finally {
    loading.value = false;
    await refresh();
  }
}

/**
 * Re-authenticate an expired admin session with the account password (#4331).
 *
 * POST /api/colonel/reauthenticate is the one console route exempt from the
 * admin session bound, so it answers while every other call 401s. On success
 * the server has moved the session to a new id and re-stamped
 * `authenticated_at`; it does NOT grant a step-up window.
 *
 * Returns false with the server's message in {@link reauthError} on failure
 * (a wrong password is a 403 `reauthentication_failed`). On success it
 * reloads the page and does not return in practice.
 */
async function reauthenticate(password: string): Promise<boolean> {
  reauthLoading.value = true;
  reauthError.value = null;
  try {
    const response = await client().post(REAUTHENTICATE_URL, { password });
    // A 2xx means the server re-stamped the session whatever the ack shape;
    // the parse keeps the contract a live tripwire without failing recovery.
    gracefulParse(
      colonelReauthenticateResponseSchema,
      response.data,
      'ColonelReauthenticateResponse'
    );
  } catch (err) {
    reauthError.value = classifyError(err).message;
    reauthLoading.value = false;
    return false;
  }

  clearAdminSessionExpired();
  // These two leave this tab's state correct on their own: a beforeunload
  // handler can cancel the reload below, and the console must then still hold
  // the new snapshot epoch and the live elevation state.
  await adoptRenewedSession('reauth');
  await refresh();
  reauthLoading.value = false;

  // Every view on screen already failed its load with a 401 and holds that
  // error. A full reload at the current URL re-runs every loader against the
  // renewed session; re-fetching each one in place would need a registry of
  // loaders that the console does not have.
  window.location.reload();
  return true;
}

/**
 * Open the sudo prompt and wait for the operator.
 *
 * ALWAYS requires an explicit gesture — there is no silent grace-first
 * auto-elevation, even when the server would accept `recent_auth`. Resolves true
 * once a window is live, false if the operator cancelled.
 */
function requestElevation(): Promise<boolean> {
  if (elevated.value) return Promise.resolve(true);

  promptOpen.value = true;
  return new Promise<boolean>((resolve) => {
    promptResolve = resolve;
  });
}

/**
 * Make sure a window is live BEFORE a tier-1 verb's own confirmation dialog
 * opens, so the operator proves the credential first and then fills in the
 * action (reason, typed confirmation) exactly once. Resolves true at once when
 * step-up is disabled by config (the server will not ask for it) or a window is
 * already live; otherwise opens the prompt and resolves with the operator's
 * answer. The 403 retry loop in useAdminDestructiveMutation stays as the
 * fallback for a window that lapses while the dialog is open.
 */
function ensureElevated(): Promise<boolean> {
  if (!enabled.value) return Promise.resolve(true);
  return requestElevation();
}

/**
 * The server answered 403 `elevation_required`, so no window is live whatever
 * the local countdown says (clock skew, a window dropped in another tab, an
 * identity change). Clear it locally so {@link requestElevation} prompts
 * instead of resolving true and letting the caller retry into the same 403.
 * Issues no HTTP: the prompt refreshes status when it opens.
 */
function noteElevationRequired(): void {
  applyRecord({ elevated: false, expires_at: null, seconds_remaining: 0 });
}

/** Called by the prompt when the operator finishes or dismisses it. */
function resolvePrompt(didElevate: boolean): void {
  promptOpen.value = false;
  const resolve = promptResolve;
  promptResolve = null;
  resolve?.(didElevate);
}

// Nothing the operator can do from the browser: no password to re-enter and no
// grace configured. The prompt renders the remediation, not an input.
const unsatisfiable = computed(
  () => !passwordAvailable.value && !factors.value.includes('recent_auth')
);

export interface UseColonelElevation {
  elevated: Ref<boolean>;
  expiresAt: Ref<number | null>;
  secondsRemaining: Ref<number>;
  enabled: Ref<boolean>;
  window: Ref<number>;
  reauthGrace: Ref<number>;
  graceAvailable: Ref<boolean>;
  passwordAvailable: Ref<boolean>;
  factors: Ref<string[]>;
  activeFactor: Ref<string | null>;
  loading: Ref<boolean>;
  error: Ref<string | null>;
  /** True when the operator has no factor they can satisfy from the browser. */
  unsatisfiable: ComputedRef<boolean>;
  /**
   * The admin API surface has expired this session (#4331). Re-exported here,
   * not re-implemented: the banner needs ONE object holding every reason the
   * console is currently unable to act, and an expired window outranks every
   * elevation state.
   */
  adminSessionExpired: Ref<boolean>;
  /** True while a password re-authentication of the expired session is in flight. */
  reauthLoading: Ref<boolean>;
  /** The server's message for the last failed re-authentication, or null. */
  reauthError: Ref<string | null>;
  promptOpen: Ref<boolean>;
  refresh: () => Promise<void>;
  elevate: (factor: string, password?: string) => Promise<boolean>;
  drop: () => Promise<boolean>;
  /** Re-authenticate an expired admin session by password, then reload the page. */
  reauthenticate: (password: string) => Promise<boolean>;
  /** Open the sudo prompt and resolve once the operator elevates or cancels. */
  requestElevation: () => Promise<boolean>;
  /** Resolve true when elevated (or step-up is disabled), prompting first if needed. */
  ensureElevated: () => Promise<boolean>;
  /** A 403 `elevation_required` arrived: drop any window the local countdown still shows. */
  noteElevationRequired: () => void;
  /** Called by the prompt when the operator finishes or dismisses it. */
  resolvePrompt: (didElevate: boolean) => void;
}

export function useColonelElevation(): UseColonelElevation {
  // Injected lazily: useApi() needs an active component instance, and this
  // module's state outlives any one of them.
  if (!api) api = useApi();

  return {
    elevated,
    expiresAt,
    secondsRemaining,
    enabled,
    window: window_,
    reauthGrace,
    graceAvailable,
    passwordAvailable,
    factors,
    activeFactor,
    loading,
    error,
    unsatisfiable,
    adminSessionExpired,
    reauthLoading,
    reauthError,
    promptOpen,
    refresh,
    elevate,
    drop,
    reauthenticate,
    requestElevation,
    ensureElevated,
    noteElevationRequired,
    resolvePrompt,
  };
}

/** Test seam: reset the module-level singleton between specs. */
export function __resetColonelElevationState(): void {
  stopCountdown();
  api = null;
  promptResolve = null;
  promptOpen.value = false;
  elevated.value = false;
  expiresAt.value = null;
  secondsRemaining.value = 0;
  enabled.value = true;
  window_.value = 600;
  reauthGrace.value = 0;
  graceAvailable.value = false;
  passwordAvailable.value = true;
  factors.value = ['password'];
  activeFactor.value = null;
  loading.value = false;
  error.value = null;
  reauthLoading.value = false;
  reauthError.value = null;
  clearAdminSessionExpired();
}
