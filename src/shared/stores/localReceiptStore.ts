// src/shared/stores/localReceiptStore.ts

import {
  secretDisplayTypeSchema,
  type SecretDisplayType,
} from '@/schemas/contracts/secret';
import {
  guestReceiptsResponseSchema,
  storedLocalReceiptSchema,
  storedLocalReceiptsArraySchema,
  type LocalReceipt,
  type StoredLocalReceipt,
} from '@/schemas/ui/local-receipt';
import { loggingService } from '@/services/logging.service';
import { useApi } from '@/shared/composables/useApi';
import { useAuthStore } from '@/shared/stores/authStore';
import { defineStore, PiniaCustomProperties } from 'pinia';
import { computed, ref, watch } from 'vue';

/**
 * Type definition for LocalReceiptStore.
 */
export type LocalReceiptStore = {
  // State
  _initialized: boolean;
  localReceipts: LocalReceipt[];
  workspaceMode: boolean;
  preferredTtl: number | null;
  preferredDisplayType: SecretDisplayType | null;

  // Getters
  isInitialized: boolean;
  hasReceipts: boolean;

  // Actions
  init: () => { isInitialized: boolean };
  addReceipt: (receipt: LocalReceipt) => void;
  updateMemo: (id: string, memo: string) => void;
  markAsPreviewed: (secretExtid: string) => void;
  markAsRevealed: (secretExtid: string) => void;
  markAsBurned: (secretExtid: string) => void;
  refreshReceiptStatuses: () => Promise<boolean>;
  clearReceipts: () => void;
  setWorkspaceMode: (enabled: boolean) => void;
  toggleWorkspaceMode: () => void;
  setPreferredTtl: (ttl: number) => void;
  setPreferredDisplayType: (displayType: SecretDisplayType) => void;
  $reset: () => void;
} & PiniaCustomProperties;

// Local storage key for persisting receipts when not authenticated. It's
// actually session storage. Uses pascalCase convention (unlike cookies
// which use dot notation).
const STORAGE_KEY = 'onetimeReceiptCache';
const WORKSPACE_MODE_KEY = 'onetimeWorkspaceMode';
const PREFERRED_TTL_KEY = 'onetimePreferredTtl';
const PREFERRED_DISPLAY_TYPE_KEY = 'onetimePreferredDisplayType';
const MAX_STORED_RECEIPTS = 25;

/** Whether the receipt's secret is still within its TTL. */
function isUnexpired(receipt: StoredLocalReceipt, now: number): boolean {
  return receipt.createdAt + receipt.ttl * 1000 > now;
}

/**
 * The sessionStorage form of the in-memory list (RISK-2026-08-14-M10):
 * unexpired entries only, reduced to the stored schema. Parsing strips the
 * secret identifier, which stays on the in-memory record for the page that
 * created it, and any other field outside the schema.
 */
function toStoredReceipts(receipts: LocalReceipt[]): StoredLocalReceipt[] {
  const now = Date.now();
  return receipts.flatMap((receipt) => {
    const result = storedLocalReceiptSchema.safeParse(receipt);
    return result.success && isUnexpired(result.data, now) ? [result.data] : [];
  });
}

/** Write the stored form. No receipts means no key, not an empty array. */
function writeStoredReceipts(receipts: StoredLocalReceipt[]): void {
  if (receipts.length === 0) {
    sessionStorage.removeItem(STORAGE_KEY);
  } else {
    sessionStorage.setItem(STORAGE_KEY, JSON.stringify(receipts));
  }
}

/**
 * Rewrite storage when loading changed it: parsing dropped a field (an older
 * version's secret identifier) or an entry expired (RISK-2026-08-14-M10).
 * Best effort: a failed rewrite keeps the loaded list; the next change retries.
 */
function rewriteIfChanged(receipts: StoredLocalReceipt[], stored: string): void {
  if (JSON.stringify(receipts) === stored) return;
  try {
    writeStoredReceipts(receipts);
  } catch (error) {
    loggingService.error(new Error(`Failed to rewrite local receipts: ${error}`));
  }
}

/**
 * Remove a cache that cannot be loaded. Its raw text may be a previous
 * release's entries, secret identifiers included (RISK-2026-08-14-M10).
 */
function discardStoredReceipts(): void {
  try {
    sessionStorage.removeItem(STORAGE_KEY);
  } catch (error) {
    loggingService.error(new Error(`Failed to clear local receipts from storage: ${error}`));
  }
}

/** Parse a stored cache; null when it is not JSON or not in the stored form. */
function parseStoredReceipts(raw: string): StoredLocalReceipt[] | null {
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch (error) {
    loggingService.warn(`Unreadable local receipts in storage, clearing: ${error}`);
    return null;
  }
  const result = storedLocalReceiptsArraySchema.safeParse(parsed);
  if (!result.success) {
    loggingService.warn(`Invalid local receipts in storage, clearing: ${result.error.message}`);
    return null;
  }
  return result.data;
}

/**
 * Loads local receipts from sessionStorage with schema validation.
 * Gracefully handles corrupted, tampered, or version-mismatched data: a cache
 * that does not parse is removed, not left in place.
 * Entries written by older versions carry a secret identifier; parsing drops
 * it, and storage is rewritten at once so it does not linger until the next
 * change.
 */
function loadFromStorage(): LocalReceipt[] {
  let stored: string | null;
  try {
    stored = sessionStorage.getItem(STORAGE_KEY);
  } catch (error) {
    loggingService.error(new Error(`Failed to load local receipts from storage: ${error}`));
    return [];
  }
  if (!stored) return [];

  const entries = parseStoredReceipts(stored);
  if (!entries) {
    discardStoredReceipts();
    return [];
  }

  // Filter out expired entries (createdAt + ttl has passed)
  const now = Date.now();
  const receipts = entries.filter((r) => isUnexpired(r, now));
  rewriteIfChanged(receipts, stored);
  return receipts;
}

/**
 * Loads workspace mode preference from localStorage
 * Uses localStorage (not sessionStorage) so preference persists across sessions
 */
function loadWorkspaceModePreference(): boolean {
  try {
    const stored = localStorage.getItem(WORKSPACE_MODE_KEY);
    return stored === 'true';
  } catch (error) {
    loggingService.error(new Error(`Failed to load workspace mode preference: ${error}`));
  }
  return false;
}

/**
 * Loads the last-used TTL preference from localStorage
 * Uses localStorage (not sessionStorage) so preference persists across sessions.
 * Returns null when unset or invalid so callers fall back to the configured default.
 */
function loadPreferredTtl(): number | null {
  try {
    const stored = localStorage.getItem(PREFERRED_TTL_KEY);
    if (stored === null) return null;
    const parsed = Number(stored);
    return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
  } catch (error) {
    loggingService.error(new Error(`Failed to load preferred TTL: ${error}`));
  }
  return null;
}

/**
 * Loads the last-used display type (the Markdown toggle) from localStorage.
 * Same persistence as the TTL preference: localStorage so it survives the
 * session, null when unset or not a type this build knows so callers fall
 * back to plain text.
 */
function loadPreferredDisplayType(): SecretDisplayType | null {
  try {
    const stored = localStorage.getItem(PREFERRED_DISPLAY_TYPE_KEY);
    if (stored === null) return null;
    const result = secretDisplayTypeSchema.safeParse(stored);
    return result.success ? result.data : null;
  } catch (error) {
    loggingService.error(new Error(`Failed to load preferred display type: ${error}`));
  }
  return null;
}

/**
 * Store for managing local receipt records during a guest session.
 * Receipts created during the session stay listed across navigation and
 * browser refreshes. Only the receipt side is persisted: the share link's
 * secret identifier is kept in memory, so after a refresh the list links to
 * each receipt page (which shows the share link) instead (RISK-2026-08-14-M10).
 */
// eslint-disable-next-line max-lines-per-function
export const useLocalReceiptStore = defineStore('localReceipt', () => {
  const $api = useApi();
  const authStore = useAuthStore();

  // State
  const _initialized = ref(false);
  const localReceipts = ref<LocalReceipt[]>(loadFromStorage());
  const workspaceMode = ref(loadWorkspaceModePreference());
  const preferredTtl = ref<number | null>(loadPreferredTtl());
  const preferredDisplayType = ref<SecretDisplayType | null>(loadPreferredDisplayType());

  // Getters
  const isInitialized = computed(() => _initialized.value);
  const hasReceipts = computed(() => localReceipts.value.length > 0);

  // Watch for changes to receipts and save to sessionStorage
  watch(
    localReceipts,
    (receipts) => {
      try {
        writeStoredReceipts(toStoredReceipts(receipts));
      } catch (error) {
        loggingService.error(new Error(`Failed to save local receipts to storage: ${error}`));
      }
    },
    { deep: true }
  );

  // Watch for changes to workspaceMode and save to localStorage
  watch(workspaceMode, (enabled) => {
    try {
      localStorage.setItem(WORKSPACE_MODE_KEY, String(enabled));
    } catch (error) {
      loggingService.error(new Error(`Failed to save workspace mode preference: ${error}`));
    }
  });

  // Watch for changes to preferredTtl and save to localStorage
  watch(preferredTtl, (ttl) => {
    try {
      if (ttl === null) {
        localStorage.removeItem(PREFERRED_TTL_KEY);
      } else {
        localStorage.setItem(PREFERRED_TTL_KEY, String(ttl));
      }
    } catch (error) {
      loggingService.error(new Error(`Failed to save preferred TTL: ${error}`));
    }
  });

  // Watch for changes to preferredDisplayType and save to localStorage
  watch(preferredDisplayType, (displayType) => {
    try {
      if (displayType === null) {
        localStorage.removeItem(PREFERRED_DISPLAY_TYPE_KEY);
      } else {
        localStorage.setItem(PREFERRED_DISPLAY_TYPE_KEY, displayType);
      }
    } catch (error) {
      loggingService.error(new Error(`Failed to save preferred display type: ${error}`));
    }
  });

  // Guest receipts, and the secret identifiers held in memory for them, do
  // not outlive sign-in (RISK-2026-08-14-M10). Sign-in is an in-app
  // navigation, so this runs whether or not a list is mounted, and
  // immediately for a page that loads signed in. isFullyAuthenticated is the
  // test useRecentSecrets lists by: while MFA is pending the list is still
  // local, so the receipts stay until the second factor completes.
  watch(
    () => authStore.isFullyAuthenticated,
    (signedIn) => {
      if (signedIn) clearReceipts();
    },
    { immediate: true, flush: 'sync' }
  );

  /**
   * Initializes the local receipt store.
   * Idempotent - subsequent calls have no effect if already initialized.
   *
   * @param options Optional store options
   * @returns Object containing initialization status
   */
  function init() {
    if (_initialized.value) return { isInitialized };


    _initialized.value = true;
    return { isInitialized };
  }

  /**
   * Adds a new local receipt to the store.
   * New receipts are added to the beginning of the list.
   * Enforces maximum storage limit.
   *
   * A no-op for a signed-in user: their recent secrets come from the API
   * (useRecentSecrets), so a local copy would only park capability
   * identifiers in sessionStorage (RISK-2026-08-14-M10).
   *
   * @param receipt The local receipt to add
   */
  function addReceipt(receipt: LocalReceipt) {
    if (authStore.isFullyAuthenticated) return;
    // Remove any existing receipt with same ID
    const filtered = localReceipts.value.filter((r) => r.id !== receipt.id);
    // Add new receipt at beginning, enforce max limit
    localReceipts.value = [receipt, ...filtered].slice(0, MAX_STORED_RECEIPTS);
  }

  /**
   * Updates the memo for a specific receipt.
   * Empty string removes the memo.
   *
   * @param id The receipt ID to update
   * @param memo The new memo value
   */
  function updateMemo(id: string, memo: string) {
    const index = localReceipts.value.findIndex((r) => r.id === id);
    if (index !== -1) {
      const trimmed = memo.trim();
      if (trimmed) {
        localReceipts.value[index].memo = trimmed;
      } else {
        delete localReceipts.value[index].memo;
      }
      // Trigger reactivity by replacing the array
      localReceipts.value = [...localReceipts.value];
    }
  }

  /**
   * Marks a secret as previewed (link accessed, confirmation shown).
   * Called when the recipient accesses the secret link.
   *
   * @param secretExtid The secret external ID to mark as previewed
   */
  function markAsPreviewed(secretExtid: string) {
    const index = localReceipts.value.findIndex((r) => r.secretExtid === secretExtid);
    if (index !== -1) {
      localReceipts.value[index].isPreviewed = true;
      // Trigger reactivity by replacing the array
      localReceipts.value = [...localReceipts.value];
    }
  }

  /**
   * Marks a secret as revealed (content decrypted/consumed).
   * Called when the secret content is actually revealed to the recipient.
   * Entries restored from sessionStorage have no secretExtid and never match
   * here; refreshReceiptStatuses picks up their state from the server.
   *
   * @param secretExtid The secret external ID to mark as revealed
   */
  function markAsRevealed(secretExtid: string) {
    const index = localReceipts.value.findIndex((r) => r.secretExtid === secretExtid);
    if (index !== -1) {
      localReceipts.value[index].isRevealed = true;
      // Trigger reactivity by replacing the array
      localReceipts.value = [...localReceipts.value];
    }
  }

  /**
   * Marks a secret as burned (manually destroyed before being revealed).
   * Called when the creator burns the secret from the receipt page.
   *
   * @param secretExtid The secret external ID to mark as burned
   */
  function markAsBurned(secretExtid: string) {
    const index = localReceipts.value.findIndex((r) => r.secretExtid === secretExtid);
    if (index !== -1) {
      localReceipts.value[index].isBurned = true;
      // Trigger reactivity by replacing the array
      localReceipts.value = [...localReceipts.value];
    }
  }

  /**
   * Refreshes the status of all stored receipts from the server.
   * Calls POST /api/v3/guest/receipts with receipt identifiers to get current status.
   * Updates local storage with server state (isPreviewed, isRevealed, isBurned).
   *
   * @returns true if refresh succeeded, false if it failed (stale data shown)
   */
  async function refreshReceiptStatuses(): Promise<boolean> {
    if (localReceipts.value.length === 0) return true;

    // Send full receipt identifiers (receiptExtid) - backend uses Receipt.load_multi
    const identifiers = localReceipts.value.map((r) => r.receiptExtid);

    try {
      const response = await $api.post('/api/v3/guest/receipts', {
        identifiers,
      });

      // Validate API response with schema
      const parseResult = guestReceiptsResponseSchema.safeParse(response.data);
      if (!parseResult.success) {
        loggingService.error(
          new Error(`Invalid API response from guest/receipts: ${parseResult.error.message}`)
        );
        return false;
      }

      const { records } = parseResult.data;
      let hasUpdates = false;

      // Update local receipts with server status
      // Match on full receipt identifier (returned as 'identifier' in safe_dump)
      for (const serverRecord of records) {
        const localIndex = localReceipts.value.findIndex(
          (r) => r.receiptExtid === serverRecord.identifier
        );
        if (localIndex === -1) continue;

        const local = localReceipts.value[localIndex];
        // Only update if status changed
        if (serverRecord.is_previewed && !local.isPreviewed) {
          localReceipts.value[localIndex].isPreviewed = true;
          hasUpdates = true;
        }
        if (serverRecord.is_revealed && !local.isRevealed) {
          localReceipts.value[localIndex].isRevealed = true;
          hasUpdates = true;
        }
        if (serverRecord.is_burned && !local.isBurned) {
          localReceipts.value[localIndex].isBurned = true;
          hasUpdates = true;
        }
      }

      // Trigger reactivity if any updates occurred
      if (hasUpdates) {
        localReceipts.value = [...localReceipts.value];
      }
      return true;
    } catch (error) {
      loggingService.error(new Error(`Failed to refresh receipt statuses: ${error}`));
      return false;
    }
  }

  /**
   * Clears all local receipts from the store and sessionStorage.
   */
  function clearReceipts() {
    localReceipts.value = [];
    try {
      sessionStorage.removeItem(STORAGE_KEY);
    } catch (error) {
      loggingService.error(new Error(`Failed to clear local receipts from storage: ${error}`));
    }
  }

  /**
   * Sets the workspace mode preference.
   * When enabled, form stays on page after creation instead of navigating to receipt.
   *
   * @param enabled Whether workspace mode should be enabled
   */
  function setWorkspaceMode(enabled: boolean) {
    workspaceMode.value = enabled;
  }

  /**
   * Toggles the workspace mode preference.
   */
  function toggleWorkspaceMode() {
    workspaceMode.value = !workspaceMode.value;
  }

  /**
   * Sets the last-used TTL preference so the secret form restores it on reload.
   *
   * @param ttl The TTL value in seconds
   */
  function setPreferredTtl(ttl: number) {
    preferredTtl.value = ttl;
  }

  /**
   * Sets the last-used display type (Markdown toggle) so the secret forms
   * restore it on the next page load, the way the TTL is restored.
   *
   * @param displayType One of the known secret display types
   */
  function setPreferredDisplayType(displayType: SecretDisplayType) {
    preferredDisplayType.value = displayType;
  }

  /**
   * Reset store state to initial values.
   * Implementation of $reset() for setup stores since it's not automatically available.
   * Also clears sessionStorage.
   */
  function $reset() {
    clearReceipts();
    workspaceMode.value = false;
    preferredTtl.value = null;
    preferredDisplayType.value = null;
    _initialized.value = false;
  }

  return {
    // State
    _initialized,
    localReceipts,
    workspaceMode,
    preferredTtl,
    preferredDisplayType,

    // Getters
    isInitialized,
    hasReceipts,

    // Actions
    init,
    addReceipt,
    updateMemo,
    markAsPreviewed,
    markAsRevealed,
    markAsBurned,
    refreshReceiptStatuses,
    clearReceipts,
    setWorkspaceMode,
    toggleWorkspaceMode,
    setPreferredTtl,
    setPreferredDisplayType,
    $reset,
  };
});
