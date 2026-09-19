// src/shared/stores/authStore.ts

import { PiniaPluginOptions } from '@/plugins/pinia/types';
import {
  bootstrapSchema,
  effectiveAuthStatus,
  type ClientAuthStatus,
} from '@/schemas/contracts/bootstrap';
import { classifyError, errorGuards } from '@/schemas/errors';
import { clearDiagnosticsActorContext } from '@/services/diagnostics.service';
import { loggingService } from '@/services/logging.service';
import { AxiosInstance } from 'axios';
import { defineStore, getActivePinia, PiniaCustomProperties, storeToRefs } from 'pinia';
import { computed, inject, ref } from 'vue';
import { useBootstrapStore } from './bootstrapStore';

/**
 * ═══════════════════════════════════════════════════════════════════════════════
 * AUTHENTICATION ACCESSORS AND THE REFRESH COORDINATOR
 * ═══════════════════════════════════════════════════════════════════════════════
 *
 * ───────────────────────────────────────────────────────────────────────────────
 * ONE AUTHORITY (#4458)
 * ───────────────────────────────────────────────────────────────────────────────
 *
 * This store holds NO authentication state of its own. The client status lives
 * in exactly one writable place, `bootstrapStore.authStatus`, and every
 * accessor exported here (`isAuthenticated`, `isFullyAuthenticated`,
 * `awaitingMfa`, `isUserPresent`) is a computed over it:
 *
 *   checking       nothing verified yet (missing/invalid hydration). Client-only.
 *   authenticated  the server said so, and sent a customer.
 *   mfa_pending    first factor passed, second outstanding.
 *   anonymous      no customer session, including one the server rejected.
 *   unavailable    verification cannot be completed. NOT a sign-out.
 *
 * Only `authenticated` grants anything. The status changes only when a
 * complete, contract-valid snapshot is applied (hydration, or a response this
 * coordinator accepted), on an explicit local sign-out, or when the coordinator
 * withholds authority after repeated failures. Nothing is read from
 * sessionStorage, and `had_valid_session` is not consulted (#4468 removes it).
 *
 * ───────────────────────────────────────────────────────────────────────────────
 * ONE COORDINATOR (#4459, ADR-046 "Refresh coordination")
 * ───────────────────────────────────────────────────────────────────────────────
 *
 * `refresh({ kind, reason })` is the only caller of GET /bootstrap/me. Triggers:
 * authentication mutations; returning to a stale visible tab; the passive
 * interval; a rejection that needs reconciliation; an explicit retry; and the
 * single verification a `checking` page needs. Navigation is NOT a trigger.
 *
 * - Every request takes the next generation. A response whose generation is
 *   no longer current is dropped as a unit.
 * - `ordinary` requests are deduplicated: callers share the one in flight.
 * - An `auth-mutation` request aborts whatever is in flight and starts again,
 *   so a response that began before a login/logout/MFA step cannot land after
 *   it. Local sign-out invalidates the generation too.
 * - A failure (network, timeout, 5xx incl. 503, a payload that fails the
 *   contract, or a snapshot that says `unavailable`) mutates nothing. It is
 *   retried with exponential backoff and full jitter, never sooner than the
 *   server's Retry-After. At MAX_FAILURES the status becomes `unavailable`
 *   and retries continue at the cap. It never signs the user out: a client
 *   that cannot reach the server has learned nothing about the session.
 */
export const AUTH_CHECK_CONFIG = {
  INTERVAL: 15 * 60 * 1000,
  JITTER: 90 * 1000,
  MAX_FAILURES: 3,
  ENDPOINT: '/bootstrap/me',
  /** Backoff: full jitter over min(CAP, BASE * 2^failures), AWS Builders' Library form. */
  BACKOFF_BASE: 2 * 1000,
  BACKOFF_CAP: 60 * 1000,
  /** A retry never fires sooner than this, whatever the jitter draws. */
  BACKOFF_FLOOR: 1000,
  /** Upper bound on a server-supplied Retry-After. */
  RETRY_AFTER_CAP: 5 * 60 * 1000,
} as const;

export type RefreshKind = 'ordinary' | 'auth-mutation';

/** Why a refresh was requested. Diagnostic only; it never changes the outcome. */
export type RefreshReason =
  | 'initial-verification'
  | 'interval'
  | 'visibility'
  | 'rejection'
  | 'retry'
  | 'login'
  | 'mfa'
  | 'signup'
  | 'verify-account'
  | 'invite'
  | 'impersonation'
  | 'account-switch'
  | 'plan-preview'
  | 'password-change'
  | 'csrf'
  | 'check';

export interface RefreshRequest {
  kind: RefreshKind;
  reason: RefreshReason;
}

/**
 * - `applied`    a snapshot of the current generation was accepted and applied.
 * - `failed`     no usable statement was obtained; nothing changed.
 * - `superseded` a later generation started first; this response was dropped.
 */
export type RefreshOutcome = 'applied' | 'failed' | 'superseded';

/**
 * Parses a Retry-After header (delay-seconds or HTTP-date) into milliseconds.
 * Returns 0 when absent or unusable; capped at RETRY_AFTER_CAP.
 */
export function parseRetryAfter(value: unknown, now: number = Date.now()): number {
  if (typeof value !== 'string' && typeof value !== 'number') return 0;
  const text = String(value).trim();
  if (text === '') return 0;

  const ms = /^\d+$/.test(text) ? Number(text) * 1000 : Date.parse(text) - now;
  if (!Number.isFinite(ms) || ms <= 0) return 0;
  return Math.min(ms, AUTH_CHECK_CONFIG.RETRY_AFTER_CAP);
}

/**
 * Delay before the next retry, in milliseconds.
 *
 * @param failures - Consecutive failures so far (>= 1)
 * @param retryAfterMs - Floor demanded by the server, already parsed
 * @param random - Injected for tests; a value in [0, 1)
 */
export function retryDelay(
  failures: number,
  retryAfterMs: number = 0,
  random: () => number = Math.random
): number {
  const exponent = Math.min(Math.max(failures - 1, 0), 16);
  const { BACKOFF_BASE, BACKOFF_CAP, BACKOFF_FLOOR } = AUTH_CHECK_CONFIG;
  const ceiling = Math.min(BACKOFF_CAP, BACKOFF_BASE * 2 ** exponent);
  return Math.max(random() * ceiling, retryAfterMs, BACKOFF_FLOOR);
}

interface StoreOptions extends PiniaPluginOptions {}

/**
 * Type definition for AuthStore.
 */
export type AuthStore = {
  // State
  authCheckTimer: ReturnType<typeof setTimeout> | null;
  failureCount: number | null;
  lastCheckTime: number | null;
  _initialized: boolean;

  // Getters (all derived from bootstrapStore.authStatus)
  authStatus: ClientAuthStatus;
  isAuthenticated: boolean;
  needsCheck: boolean;
  isInitialized: boolean;
  awaitingMfa: boolean;
  isFullyAuthenticated: boolean;
  isUserPresent: boolean;

  // Actions
  init: () => { needsCheck: boolean; isInitialized: boolean };
  refresh: (request: RefreshRequest) => Promise<RefreshOutcome>;
  retryNow: () => Promise<RefreshOutcome>;
  stop: () => void;
  checkWindowStatus: () => Promise<boolean>;
  refreshAuthState: () => Promise<void>;
  setAuthenticated: (value: boolean) => Promise<void>;
  logout: () => Promise<void>;
  logoutMinimal: () => Promise<void>;
  $scheduleNextCheck: () => void;
  $stopAuthCheck: () => Promise<void>;
  $dispose: () => Promise<void>;
  $reset: () => void;
} & PiniaCustomProperties;

/**
 * Stores holding data that belongs to ONE account. Reset when authority is
 * lost or the account changes (#4458). Recipient-facing and browser-local
 * stores (secretStore, incomingStore, localReceiptStore) are deliberately not
 * here: they work without an account.
 *
 * Keyed by store id and loaded on demand. authStore is imported almost
 * everywhere, so it must not import these statically: that would pull every
 * one of them (and their dependencies) into each importer and into the entry
 * chunk, and secretStore -> authStore would become a cycle. A store is only
 * loaded here when its state already exists, i.e. when its module is already
 * in memory, so the import resolves from cache.
 */
type Resettable = () => { $reset: () => void };
const ACCOUNT_SCOPED_STORES: Readonly<Record<string, () => Promise<Resettable>>> = {
  account: () => import('./accountStore').then((m) => m.useAccountStore),
  customer: () => import('./customerStore').then((m) => m.useCustomerStore),
  domains: () => import('./domainsStore').then((m) => m.useDomainsStore),
  entitlements: () => import('./entitlementsStore').then((m) => m.useEntitlementsStore),
  members: () => import('./membersStore').then((m) => m.useMembersStore),
  organization: () => import('./organizationStore').then((m) => m.useOrganizationStore),
  receiptList: () => import('./receiptListStore').then((m) => m.useReceiptListStore),
  receipt: () => import('./receiptStore').then((m) => m.useReceiptStore),
};

/* eslint-disable max-lines-per-function */
export const useAuthStore = defineStore('auth', () => {
  const $api = inject('api') as AxiosInstance;
  const bootstrapStore = useBootstrapStore();

  const { authStatus, cust: bsCust } = storeToRefs(bootstrapStore);

  // State. None of it says who is signed in.
  const authCheckTimer = ref<ReturnType<typeof setTimeout> | null>(null);
  const failureCount = ref<number | null>(null);
  const lastCheckTime = ref<number | null>(null);
  const _initialized = ref(false);

  // Coordinator bookkeeping. Not reactive: nothing renders from it.
  let generation = 0;
  let inFlight: {
    generation: number;
    controller: AbortController;
    promise: Promise<RefreshOutcome>;
  } | null = null;
  let retryTimer: ReturnType<typeof setTimeout> | null = null;
  let visibilityHandler: (() => void) | null = null;

  // Getters
  /** Read-only view of THE client status, for guards and layouts. */
  const status = computed((): ClientAuthStatus => authStatus.value);

  const isAuthenticated = computed((): boolean => authStatus.value === 'authenticated');

  /**
   * Whether the last accepted snapshot is older than the check interval.
   *
   * A plain function, evaluated when asked. It must NOT be a computed:
   * Date.now() is not a reactive dependency, so a computed would cache its
   * first answer and a tab could never become stale by time passing.
   */
  function isStale(): boolean {
    if (!lastCheckTime.value) return true;
    return Date.now() - lastCheckTime.value > AUTH_CHECK_CONFIG.INTERVAL;
  }

  /**
   * @deprecated Reactive only to `lastCheckTime`, not to the clock (see
   * isStale). Kept for existing readers; nothing decides from it.
   */
  const needsCheck = computed((): boolean => isStale());

  const isInitialized = computed(() => _initialized.value);

  /** Password OK, second factor pending. */
  const awaitingMfa = computed((): boolean => authStatus.value === 'mfa_pending');

  /**
   * Whether ALL authentication steps are complete. With one status this is the
   * same statement as isAuthenticated; both names are kept for their callers.
   */
  const isFullyAuthenticated = computed((): boolean => authStatus.value === 'authenticated');

  /**
   * Whether a user is present (MFA-pending or authenticated). For UI decisions
   * (user menu vs sign-in links), never for access control.
   */
  const isUserPresent = computed(
    (): boolean =>
      authStatus.value === 'mfa_pending' || (authStatus.value === 'authenticated' && !!bsCust.value)
  );

  // Actions

  function init(options?: StoreOptions) {
    if (_initialized.value) {
      loggingService.debug('[AuthStore.init] Already initialized, skipping');
      return { needsCheck, isInitialized };
    }

    if (options?.api) loggingService.warn('API instance provided in options, ignoring.');

    // bootstrapStore has already parsed hydration. A verified statement from
    // the server counts as a check; `checking` does not.
    if (authStatus.value !== 'checking') lastCheckTime.value = Date.now();
    if (isAuthenticated.value) $scheduleNextCheck();

    listenForVisibility();
    _initialized.value = true;

    loggingService.debug('[AuthStore.init] Initialization complete:', {
      authStatus: authStatus.value,
      needsCheck: needsCheck.value,
    });

    return { needsCheck, isInitialized };
  }

  /**
   * Returning to a stale visible tab is a refresh trigger. Background tabs
   * throttle timers, so the interval alone cannot be relied on.
   */
  function listenForVisibility() {
    if (typeof document === 'undefined' || visibilityHandler) return;
    visibilityHandler = () => {
      if (document.visibilityState !== 'visible') return;
      if (authStatus.value === 'anonymous' || !isStale()) return;
      void refresh({ kind: 'ordinary', reason: 'visibility' });
    };
    document.addEventListener('visibilitychange', visibilityHandler);
  }

  /**
   * Invalidates every request issued so far. Called by authentication
   * mutations and local sign-out: a response that started before them must
   * never be applied after them.
   */
  function invalidateGeneration() {
    generation += 1;
    inFlight?.controller.abort();
    inFlight = null;
    clearRetry();
  }

  function clearRetry() {
    if (retryTimer !== null) {
      clearTimeout(retryTimer);
      retryTimer = null;
    }
  }

  /**
   * Requests a complete snapshot. The ONLY caller of GET /bootstrap/me.
   */
  function refresh(request: RefreshRequest): Promise<RefreshOutcome> {
    if (request.kind === 'ordinary' && inFlight) {
      loggingService.debug('[AuthStore.refresh] Joined the request in flight', {
        reason: request.reason,
      });
      return inFlight.promise;
    }

    if (request.kind === 'auth-mutation') inFlight?.controller.abort();
    clearRetry();

    generation += 1;
    const mine = generation;
    const controller = new AbortController();
    const promise = run(mine, controller.signal, request).finally(() => {
      if (inFlight?.generation === mine) inFlight = null;
    });
    inFlight = { generation: mine, controller, promise };
    return promise;
  }

  async function run(
    mine: number,
    signal: AbortSignal,
    request: RefreshRequest
  ): Promise<RefreshOutcome> {
    loggingService.debug('[AuthStore.refresh] Requesting snapshot', { ...request, generation: mine });

    let retryAfterMs = 0;
    try {
      const response = await $api.get(AUTH_CHECK_CONFIG.ENDPOINT, { signal });
      if (mine !== generation) return 'superseded';

      // Validate BEFORE anything is mutated. A payload that fails the shared
      // contract reaches no store.
      const parsed = bootstrapSchema.safeParse(response.data);
      if (parsed.success && effectiveAuthStatus(parsed.data) !== 'unavailable') {
        // Epoch/version acceptance (ADR-046, #4464) slots in here: between a
        // current generation and the commit below.
        await commit(parsed.data);
        return 'applied';
      }
      // `unavailable` from the server is a failed verification, not a verdict:
      // applying it would read as "session ended" during an auth-DB outage.
      // Paths only, never values: the payload carries personal data.
      loggingService.warn('[AuthStore.refresh] Snapshot not usable', {
        generation: mine,
        contractValid: parsed.success,
        invalidPaths: parsed.success ? [] : parsed.error.issues.map((issue) => issue.path.join('.')),
      });
    } catch (error) {
      if (mine !== generation) return 'superseded';
      retryAfterMs = parseRetryAfter(retryAfterHeader(error));
      const classified = classifyError(error);
      if (!errorGuards.isOfHumanInterest(classified)) loggingService.error(classified);
    }

    noteFailure(retryAfterMs);
    return 'failed';
  }

  /** Applies an accepted snapshot and clears what no longer belongs. */
  async function commit(snapshot: Parameters<typeof bootstrapStore.applySnapshot>[0]) {
    const priorStatus = authStatus.value;
    const priorAccount = bootstrapStore.custid;

    bootstrapStore.applySnapshot(snapshot);

    const lostAuthority = priorStatus === 'authenticated' && authStatus.value !== 'authenticated';
    const changedAccount = priorAccount !== '' && priorAccount !== bootstrapStore.custid;
    if (lostAuthority || changedAccount) await clearAccountScopedState();

    failureCount.value = 0;
    lastCheckTime.value = Date.now();
    $scheduleNextCheck();
  }

  function noteFailure(retryAfterMs: number) {
    failureCount.value = (failureCount.value ?? 0) + 1;
    // From `checking` there is no verified state to keep serving while we
    // retry, so one failed verification is already `unavailable`. Otherwise
    // the last accepted snapshot stands until MAX_FAILURES.
    const nothingVerified = authStatus.value === 'checking';
    if (nothingVerified || failureCount.value >= AUTH_CHECK_CONFIG.MAX_FAILURES) {
      bootstrapStore.withholdAuthority('unavailable');
    }

    clearRetry();
    const delay = retryDelay(failureCount.value, retryAfterMs);
    retryTimer = setTimeout(() => {
      retryTimer = null;
      void refresh({ kind: 'ordinary', reason: 'retry' });
    }, delay);
  }

  /** Explicit retry: skips the backoff wait, not the rules. */
  function retryNow(): Promise<RefreshOutcome> {
    return refresh({ kind: 'ordinary', reason: 'retry' });
  }

  /** Stops every timer and invalidates what is in flight. */
  function stop() {
    invalidateGeneration();
    void $stopAuthCheck();
  }

  /**
   * Resets the account-scoped stores that exist. A store that was never
   * created holds nothing, and creating it here would run its init (and
   * possibly a fetch) only to reset it.
   */
  async function clearAccountScopedState(): Promise<void> {
    const existing = getActivePinia()?.state.value ?? {};
    const ids = Object.keys(ACCOUNT_SCOPED_STORES).filter((id) => id in existing);
    const stores = await Promise.all(ids.map((id) => ACCOUNT_SCOPED_STORES[id]()));
    for (const useStore of stores) useStore().$reset();
  }

  /**
   * @deprecated Use refresh(). Kept for its callers: verifies with the server
   * unless the status is already a definitive `anonymous`.
   */
  async function checkWindowStatus(): Promise<boolean> {
    if (authStatus.value === 'anonymous') return false;
    await refresh({ kind: 'ordinary', reason: 'check' });
    return isAuthenticated.value;
  }

  /** @deprecated Use refresh(). */
  async function refreshAuthState(): Promise<void> {
    await refresh({ kind: 'ordinary', reason: 'check' });
  }

  /**
   * Passive verification: 15 minutes ± 90 s. The jitter keeps clients from
   * polling in step. Runs only while authenticated.
   */
  function $scheduleNextCheck() {
    $stopAuthCheck();

    if (!isAuthenticated.value) return;

    const jitter = (Math.random() - 0.5) * 2 * AUTH_CHECK_CONFIG.JITTER;
    const nextCheck = AUTH_CHECK_CONFIG.INTERVAL + jitter;

    authCheckTimer.value = setTimeout(() => {
      authCheckTimer.value = null;
      void refresh({ kind: 'ordinary', reason: 'interval' });
    }, nextCheck);
  }

  async function $stopAuthCheck() {
    if (authCheckTimer.value !== null) {
      clearTimeout(authCheckTimer.value);
      authCheckTimer.value = null;
    }
  }

  /**
   * Local (SPA) sign-out: no page navigation follows.
   *
   * Invalidates the generation FIRST, so a refresh already in flight cannot
   * restore the identity being cleared here.
   */
  async function logout() {
    invalidateGeneration();
    await $stopAuthCheck();

    $reset();

    // Resets account state (and the pre-Pinia mirror) to anonymous while
    // preserving server config.
    bootstrapStore.resetForLogout();
    await clearAccountScopedState();

    // The Sentry scopes survive a soft logout; without this every later error
    // in the now-anonymous session would keep the previous session's ref.
    // No-ops when diagnostics are disabled.
    clearDiagnosticsActorContext();

    deleteCookie('locale');

    sessionStorage.clear();
  }

  /**
   * Minimal logout: clears cookies and session storage without resetting
   * reactive Pinia state. Use this when a hard navigation (window.location.href)
   * follows immediately — the page reload discards all in-memory state, and
   * skipping the resets avoids a visual flash where brand-dependent components
   * briefly revert to defaults. The generation is still invalidated, so
   * nothing in flight can land during unload.
   */
  async function logoutMinimal() {
    invalidateGeneration();
    await $stopAuthCheck();

    deleteCookie('locale');
    sessionStorage.clear();
  }

  async function $dispose() {
    stop();
    if (visibilityHandler) {
      document.removeEventListener('visibilitychange', visibilityHandler);
      visibilityHandler = null;
    }
  }

  function $reset() {
    invalidateGeneration();
    authCheckTimer.value = null;
    failureCount.value = null;
    lastCheckTime.value = null;
    _initialized.value = false;
  }

  /**
   * Called after a successful authentication step (login, MFA, SSO link).
   *
   * It does NOT set anything locally: it asks the server, as an
   * authentication mutation, and the answer is the state. `false` is a local
   * sign-out.
   */
  async function setAuthenticated(value: boolean) {
    if (!value) {
      await logout();
      return;
    }
    await refresh({ kind: 'auth-mutation', reason: 'login' });
  }

  return {
    // State
    authCheckTimer,
    failureCount,
    lastCheckTime,
    _initialized,

    // Getters
    authStatus: status,
    isAuthenticated,
    needsCheck,
    isInitialized,
    awaitingMfa,
    isFullyAuthenticated,
    isUserPresent,

    // Actions
    init,
    refresh,
    retryNow,
    stop,
    checkWindowStatus,
    refreshAuthState,
    logout,
    logoutMinimal,
    setAuthenticated,

    $scheduleNextCheck,
    $stopAuthCheck,
    $dispose,
    $reset,
  };
});

/** Reads Retry-After from an axios-shaped error without assuming its class. */
function retryAfterHeader(error: unknown): unknown {
  if (typeof error !== 'object' || error === null || !('response' in error)) return undefined;
  const response = (error as { response?: { headers?: unknown } }).response;
  const headers = response?.headers;
  if (typeof headers !== 'object' || headers === null) return undefined;
  return (headers as Record<string, unknown>)['retry-after'];
}

const deleteCookie = (name: string) => {
  document.cookie = `${name}=; expires=Thu, 01 Jan 1970 00:00:00 UTC; path=/;`;
};
