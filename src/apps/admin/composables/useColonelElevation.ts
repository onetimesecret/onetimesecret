// src/apps/admin/composables/useColonelElevation.ts

import type { AxiosInstance } from 'axios';
import { computed, ref, type ComputedRef, type Ref } from 'vue';

import {
  colonelElevationGrantResponseSchema,
  colonelElevationStatusResponseSchema,
} from '@/schemas/api/internal/responses/colonel-elevation';
import { classifyError } from '@/schemas/errors';
import { useApi } from '@/shared/composables/useApi';
import { gracefulParse } from '@/utils/schemaValidation';

const ELEVATION_URL = '/api/colonel/elevation';

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
  promptOpen: Ref<boolean>;
  refresh: () => Promise<void>;
  elevate: (factor: string, password?: string) => Promise<boolean>;
  drop: () => Promise<boolean>;
  /** Open the sudo prompt and resolve once the operator elevates or cancels. */
  requestElevation: () => Promise<boolean>;
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
    promptOpen,
    refresh,
    elevate,
    drop,
    requestElevation,
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
}
