// src/shared/composables/useDomainContext.ts

/**
 * Domain Context Composable
 *
 * Provides workspace-level domain context for managing secrets
 * across multiple custom domains. Domain context is a session-level filter
 * that determines which domain context is active for the current workspace.
 *
 * Domains are scoped to the currently active organization - when the user
 * switches organizations, the available domains list updates accordingly.
 *
 * @see docs/product/interaction-modes.md - Domain Context concept
 */

import { loggingService } from '@/services/logging.service';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { useDomainsStore } from '@/shared/stores/domainsStore';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import type { AxiosInstance } from 'axios';
import { computed, inject, ref, watch } from 'vue';

export interface DomainContext {
  /** The domain hostname (e.g., "acme.example.com" or "onetimesecret.com") */
  domain: string;
  /** The external ID for API calls (e.g., "cd1234abcdef") - undefined for canonical domain */
  extid: string | undefined;
  /** Display-friendly name for the context */
  displayName: string;
  /** Whether this is the canonical (default) domain */
  isCanonical: boolean;
}

// Shared state for domain context across components
const currentDomain = ref('');
const isInitialized = ref(false);
const isLoadingDomains = ref(false);

// AbortController for cancelling in-flight domain fetches during rapid org switches
let currentFetchController: AbortController | null = null;

// Track whether module-level watcher has been set up (only do once)
let watcherInitialized = false;

// Bootstrap store reference - initialized on first composable use
let bootstrapStoreInstance: ReturnType<typeof useBootstrapStore> | null = null;

/** Get bootstrap store instance (lazy singleton) */
function getBootstrapStore(): ReturnType<typeof useBootstrapStore> {
  if (!bootstrapStoreInstance) {
    bootstrapStoreInstance = useBootstrapStore();
  }
  return bootstrapStoreInstance;
}

/** Get config values from bootstrap store (reads current values) */
function getConfig() {
  const store = getBootstrapStore();
  return {
    domainsEnabled: store.domains_enabled,
    canonicalDomain: store.site_host,
    displayDomain: store.display_domain,
    serverDomainContext: store.domain_context,
    domainStrategy: store.domain_strategy,
    customDomains: store.custom_domains ?? [],
  };
}

/** Get display name for a given domain */
function getDomainDisplayName(domain: string): string {
  const { canonicalDomain, displayDomain } = getConfig();
  const isCanonical = domain === canonicalDomain;
  const defaultDisplay = displayDomain || canonicalDomain || 'onetimesecret.com';
  return isCanonical ? defaultDisplay : domain;
}

/** Build available domains list from store */
function buildAvailableDomains(storeDomains: Array<{ display_domain: string }>): string[] {
  const { canonicalDomain } = getConfig();
  const domainNames = storeDomains.map((d) => d.display_domain);
  if (canonicalDomain && !domainNames.includes(canonicalDomain)) {
    domainNames.push(canonicalDomain);
  }
  return domainNames;
}

/** Get the preferred default domain (custom domain preferred over canonical) */
function getPreferredDomain(available: string[]): string {
  const { canonicalDomain } = getConfig();
  // Prefer first custom domain (non-canonical) if available
  const customDomain = available.find((d) => d !== canonicalDomain);
  return customDomain || available[0] || canonicalDomain || '';
}

/** Find extid for a given display_domain from store domains */
function findExtidByDomain(
  storeDomains: Array<{ display_domain: string; extid: string }>,
  domain: string
): string | undefined {
  return storeDomains.find((d) => d.display_domain === domain)?.extid;
}

/** Find display_domain for a given extid from store domains */
function findDomainByExtid(
  storeDomains: Array<{ display_domain: string; extid: string }>,
  extid: string
): string | undefined {
  return storeDomains.find((d) => d.extid === extid)?.display_domain;
}

/** Sync domain context to backend (fire-and-forget) */
async function syncDomainContextToServer(
  $api: AxiosInstance | undefined,
  domain: string
): Promise<void> {
  if (!$api) return;
  try {
    await $api.post('/api/account/update-domain-context', { domain });
  } catch (error) {
    console.warn('[useDomainContext] Failed to sync to server:', error);
  }
}

/** Persist domain selection: custom domains sync to server + sessionStorage; others clear session */
async function persistDomainContext(
  $api: AxiosInstance | undefined,
  domain: string,
  skipBackendSync: boolean
): Promise<void> {
  const { customDomains } = getConfig();
  if (customDomains.includes(domain)) {
    sessionStorage.setItem('domainContext', domain);
    if (!skipBackendSync) await syncDomainContextToServer($api, domain);
  } else {
    sessionStorage.removeItem('domainContext');
  }
}

/** Create domain fetcher for an organization store */
function createDomainFetcher(
  organizationStore: ReturnType<typeof useOrganizationStore>,
  domainsStore: ReturnType<typeof useDomainsStore>
) {
  return async (): Promise<boolean> => {
    const { domainsEnabled } = getConfig();
    if (!domainsEnabled) return true;
    const orgId = organizationStore.currentOrganization?.id;
    if (!orgId) {
      console.debug('[useDomainContext] Skipping fetch: no currentOrganization set yet');
      return false;
    }

    // Cancel any in-flight fetch before starting a new one
    if (currentFetchController) {
      currentFetchController.abort();
    }
    const controller = new AbortController();
    currentFetchController = controller;

    isLoadingDomains.value = true;
    try {
      await domainsStore.fetchList(orgId);
      // Return true only if this fetch wasn't aborted
      return !controller.signal.aborted;
    } catch (error) {
      // Ignore abort errors, log others
      if (error instanceof Error && error.name !== 'AbortError') {
        console.warn('[useDomainContext] Failed to fetch domains:', error);
      }
      return false;
    } finally {
      // Only clear loading state if this is still the current controller
      if (currentFetchController === controller) {
        isLoadingDomains.value = false;
        currentFetchController = null;
      }
    }
  };
}

/**
 * Select the best domain from available options.
 * Priority: server preference > sessionStorage > preferred domain (first custom or canonical)
 */
function selectBestDomain(available: string[]): string {
  const { serverDomainContext } = getConfig();
  const localContext = sessionStorage.getItem('domainContext');

  if (serverDomainContext && available.includes(serverDomainContext)) {
    // Server-side preference takes priority
    sessionStorage.setItem('domainContext', serverDomainContext); // Sync sessionStorage
    return serverDomainContext;
  } else if (localContext && available.includes(localContext)) {
    // Fall back to sessionStorage if valid
    return localContext;
  } else {
    // Fall back to preferred domain (first custom domain or canonical)
    return getPreferredDomain(available);
  }
}

// Guard flag to prevent concurrent initialization attempts
let isInitializing = false;

/** Initialize domain context on module load (runs once). Returns promise for awaiting. */
async function initializeDomainContext(
  fetchFn: () => Promise<boolean | void>,
  getAvailable: () => string[]
): Promise<void> {
  if (isInitialized.value || isInitializing) return;

  isInitializing = true;
  const { domainsEnabled, canonicalDomain } = getConfig();

  try {
    if (domainsEnabled) {
      const fetchSucceeded = await fetchFn();
      if (fetchSucceeded) {
        // Only select domain if fetch succeeded (org was available)
        currentDomain.value = selectBestDomain(getAvailable());
        isInitialized.value = true;
      }
      // If fetch failed (no org yet), don't mark initialized - let watcher handle it
    } else {
      currentDomain.value = canonicalDomain || '';
      isInitialized.value = true;
    }
  } catch {
    // On error, don't mark initialized - allow retry via watcher
    console.warn('[useDomainContext] Initialization failed, will retry when org is available');
  } finally {
    // Only release the lock if initialization didn't complete (allow watcher retry)
    if (!isInitialized.value) {
      isInitializing = false;
    }
  }
}

/**
 * Composable for managing domain context in the workspace.
 * Domains are scoped to the current organization.
 */
export function useDomainContext() {
  const $api = inject('api') as AxiosInstance | undefined;
  const domainsStore = useDomainsStore();
  const organizationStore = useOrganizationStore();

  const availableDomains = computed<string[]>(() => buildAvailableDomains(domainsStore.domains || []));

  const fetchDomainsForOrganization = createDomainFetcher(organizationStore, domainsStore);

  // Set up module-level watcher ONCE to prevent multiple watchers racing
  if (!watcherInitialized) {
    watcherInitialized = true;
    watch(
      () => organizationStore.currentOrganization?.id,
      async (newOrgId, oldOrgId) => {
        if (newOrgId && newOrgId !== oldOrgId) {
          const isCurrentRequest = await fetchDomainsForOrganization();
          if (!isCurrentRequest) return;
          if (!isInitialized.value) {
            currentDomain.value = selectBestDomain(availableDomains.value);
            isInitialized.value = true;
          } else if (currentDomain.value && !availableDomains.value.includes(currentDomain.value)) {
            currentDomain.value = getPreferredDomain(availableDomains.value);
          }
        }
      }
    );
  }

  const initPromise = initializeDomainContext(
    fetchDomainsForOrganization,
    () => availableDomains.value
  );

  const currentContext = computed<DomainContext>(() => {
    const { canonicalDomain } = getConfig();
    const domain = currentDomain.value || canonicalDomain || '';
    const isCanonical = domain === canonicalDomain;
    return {
      domain,
      extid: isCanonical ? undefined : findExtidByDomain(domainsStore.domains || [], domain),
      displayName: getDomainDisplayName(domain),
      isCanonical,
    };
  });

  const setContext = async (domain: string, skipBackendSync = false): Promise<void> => {
    if (!availableDomains.value.includes(domain)) return;
    currentDomain.value = domain;
    await persistDomainContext($api, domain, skipBackendSync);
  };

  /** Reverse lookup: find display_domain for a given extid */
  const getDomainByExtid = (extid: string): string | undefined =>
    findDomainByExtid(domainsStore.domains || [], extid);

  /** Set domain context by extid (route param). Skips backend sync by default. */
  const setContextByExtid = async (extid: string, skipBackendSync = true): Promise<void> => {
    const domain = getDomainByExtid(extid);
    if (domain) await setContext(domain, skipBackendSync);
    else loggingService.debug(
      '[useDomainContext] No domain found for extid',
      { extid }
    );
  };

  return {
    currentContext,
    isContextActive: computed<boolean>(() => getConfig().domainsEnabled),
    hasMultipleContexts: computed<boolean>(() => availableDomains.value.length > 1),
    availableDomains,
    isLoadingDomains: computed(() => isLoadingDomains.value),
    setContext,
    resetContext: () => { currentDomain.value = getConfig().canonicalDomain || ''; sessionStorage.removeItem('domainContext'); },
    refreshDomains: fetchDomainsForOrganization,
    getDomainDisplayName,
    getExtidByDomain: (domain: string) => findExtidByDomain(domainsStore.domains || [], domain),
    getDomainByExtid,
    setContextByExtid,
    initialized: initPromise,
  };
}

/**
 * Reset module-level state for testing purposes.
 * This is necessary because the composable uses singleton state.
 * @internal - Test use only
 */
export function __resetDomainContextForTesting(): void {
  currentDomain.value = '';
  isInitialized.value = false;
  isLoadingDomains.value = false;
  watcherInitialized = false;
  currentFetchController = null;
  bootstrapStoreInstance = null;
}
