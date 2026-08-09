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
import { useResourcePermissions } from '@/shared/composables/useResourcePermissions';
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

// Domain data extracted from permissions API (replaces domainsStore for dropdown context)
const permissionsDomains = ref<Array<{ display_domain: string; extid: string }>>([]);
let permissionsInstance: ReturnType<typeof useResourcePermissions> | null = null;

/** Get bootstrap store instance (lazy singleton) */
function getBootstrapStore(): ReturnType<typeof useBootstrapStore> {
  if (!bootstrapStoreInstance) {
    bootstrapStoreInstance = useBootstrapStore();
  }
  return bootstrapStoreInstance;
}

/** Get permissions composable instance (lazy singleton, must be called during setup) */
function getPermissions(): ReturnType<typeof useResourcePermissions> {
  if (!permissionsInstance) {
    permissionsInstance = useResourcePermissions();
  }
  return permissionsInstance;
}

/** Get config values from bootstrap store (reads current values) */
function getConfig() {
  const store = getBootstrapStore();
  // canonical_domain is the canonical LINK domain (DEFAULT_DOMAIN, resolved
  // server-side as default||site.host). site_host is the app's own hostname
  // and may differ; fall back to it only for older bootstrap payloads.
  const canonicalDomain = store.canonical_domain || store.site_host;
  const pool = store.link_domains ?? [];
  return {
    domainsEnabled: store.domains_enabled,
    canonicalDomain,
    // Operator link pool (LINK_DOMAINS, #4063): the domains offered in the
    // picker. The server always resolves an unset LINK_DOMAINS to
    // [canonical_domain], so an empty array here means exactly one thing --
    // a stale pre-#4063 payload -- and only then do we re-derive the
    // canonical entry ourselves. canonicalDomain is NOT guaranteed to be a
    // member: the canonical host may be an internal platform address the
    // operator deliberately hides from the picker.
    linkDomains: pool.length ? pool : [canonicalDomain].filter(Boolean),
    displayDomain: store.display_domain,
    serverDomainContext: store.domain_context,
    domainStrategy: store.domain_strategy,
    customDomains: store.custom_domains ?? [],
  };
}

/**
 * Preferred fallback drawn from the link pool, for the paths that have no
 * user selection yet (currentContext before init, resetContext, and the
 * domains-disabled init branch).
 *
 * Canonical wins when it is a pool member -- that keeps the historical
 * "reset returns you to the canonical domain" behavior -- otherwise the pool
 * head. Both are guaranteed members of availableDomains (buildAvailableDomains
 * appends every pool entry), so setContext can round-trip the result. Returns
 * '' only when there is no pool at all, which is the one value the
 * availableDomains invariant explicitly permits.
 */
function getPoolFallbackDomain(): string {
  const { linkDomains, canonicalDomain } = getConfig();
  if (canonicalDomain && linkDomains.includes(canonicalDomain)) return canonicalDomain;
  return linkDomains[0] ?? '';
}

/** Get display name for a given domain */
function getDomainDisplayName(domain: string): string {
  // Fall back to the pool, not canonicalDomain: naming the canonical host
  // here would surface an address the operator excluded from the picker.
  const name = domain || getPoolFallbackDomain();
  if (!name) {
    console.error('[useDomainContext] getDomainDisplayName called with no domain and an empty link pool');
  }
  return name || 'unknown';
}

/** Build available domains list from store */
function buildAvailableDomains(storeDomains: Array<{ display_domain: string }>): string[] {
  // Ordering contract: the org's custom domains first (permissions order),
  // then every link-pool entry not already listed (pool order). Every entry
  // currentContext/resetContext/getPreferredDomain can produce must appear
  // here, because setContext silently rejects anything that does not.
  const { linkDomains } = getConfig();
  const domainNames = storeDomains.map((d) => d.display_domain);
  linkDomains.forEach((domain) => {
    if (domain && !domainNames.includes(domain)) {
      domainNames.push(domain);
    }
  });
  return domainNames;
}

/** Get the preferred default domain (custom domain preferred over link pool) */
function getPreferredDomain(available: string[]): string {
  const { linkDomains } = getConfig();
  // Prefer the first real custom domain; pool membership (not "!== canonical")
  // is what distinguishes an operator-blessed entry from a customer's domain.
  const customDomain = available.find((d) => !linkDomains.includes(d));
  // Tail is `available[0]` (the pool head, given the ordering above) or ''.
  // Never a value absent from `available` -- setContext would drop it.
  return customDomain || available[0] || '';
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

/**
 * Persist domain selection: registered custom domains and operator link-pool
 * entries sync to server + sessionStorage; everything else clears the session.
 *
 * The predicate is `custom_domains ∪ link_domains`, minus the canonical domain.
 *
 * - Pool entries (LINK_DOMAINS, #4063) have no CustomDomain row and so are never
 *   in `custom_domains`. Gating on that list alone wrote nothing and synced
 *   nothing for them, so the picker silently reset on every reload.
 * - The server admits exactly this set: UpdateDomainContext#valid_domain?
 *   (apps/api/account/logic/account/update_domain_context.rb:93) accepts
 *   `DomainStrategy.canonical_host?(domain)` -- an exact match against the
 *   canonical set, which every pool member joined -- or the customer's own
 *   custom domains. A peer/sibling of a pool member matches neither list here
 *   and would be rejected there, so we must not persist it.
 * - The canonical domain is carved out deliberately: absent sessionStorage IS
 *   the canonical/default state, so selecting it clears rather than writes. It
 *   is a pool member whenever LINK_DOMAINS is unset, which would otherwise
 *   invert that long-standing behavior.
 */
async function persistDomainContext(
  $api: AxiosInstance | undefined,
  domain: string,
  skipBackendSync: boolean
): Promise<void> {
  const { customDomains, linkDomains, canonicalDomain } = getConfig();
  const isPoolMember = domain !== canonicalDomain && linkDomains.includes(domain);
  if (customDomains.includes(domain) || isPoolMember) {
    sessionStorage.setItem('domainContext', domain);
    if (!skipBackendSync) await syncDomainContextToServer($api, domain);
  } else {
    sessionStorage.removeItem('domainContext');
  }
}

/**
 * Create domain fetcher using the permissions API.
 * Extracts domains for the current organization from the bulk permissions response.
 * @see src/tests/composables/useDomainContext.spec.ts
 */
function createPermissionsFetcher(
  organizationStore: ReturnType<typeof useOrganizationStore>,
) {
  return async (): Promise<boolean> => {
    const { domainsEnabled } = getConfig();
    if (!domainsEnabled) return true;
    const orgExtid = organizationStore.currentOrganization?.extid;
    if (!orgExtid) {
      console.debug('[useDomainContext] Skipping fetch: no currentOrganization set yet');
      return false;
    }

    if (currentFetchController) {
      currentFetchController.abort();
    }
    const controller = new AbortController();
    currentFetchController = controller;

    isLoadingDomains.value = true;
    try {
      const result = await permissionsInstance!.fetchAllPermissions();
      if (controller.signal.aborted) return false;

      const orgPerms = result?.organizations.find(o => o.extid === orgExtid);
      permissionsDomains.value = orgPerms?.domains ?? [];
      return true;
    } catch (error) {
      if (error instanceof Error && error.name !== 'AbortError') {
        console.warn('[useDomainContext] Failed to fetch permissions:', error);
      }
      return false;
    } finally {
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
  const { domainsEnabled } = getConfig();

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
      // Domains feature off: no permissions fetch, so the pool is the whole
      // of availableDomains. Land on a member of it, not on canonicalDomain.
      currentDomain.value = getPoolFallbackDomain();
      isInitialized.value = true;
    }
  } catch {
    // On error, don't mark initialized - allow retry via watcher
    console.warn('[useDomainContext] Initialization failed, will retry when org is available');
  } finally {
    // Always release the concurrency guard. The isInitialized ref tracks whether
    // initialization succeeded; isInitializing only prevents concurrent calls.
    isInitializing = false;
  }
}

/**
 * Composable for managing domain context in the workspace.
 * Domains are scoped to the current organization.
 */
export function useDomainContext() {
  const $api = inject('api') as AxiosInstance | undefined;
  const organizationStore = useOrganizationStore();
  getPermissions();

  // Type param omitted (buildAvailableDomains already returns string[])
  const availableDomains = computed(() => buildAvailableDomains(permissionsDomains.value));

  const fetchDomainsForOrganization = createPermissionsFetcher(organizationStore);

  // Set up module-level watcher ONCE to prevent multiple watchers racing
  if (!watcherInitialized) {
    watcherInitialized = true;
    watch(
      () => organizationStore.currentOrganization?.objid,
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
    // Pre-init / anonymous callers land here. The fallback must be a pool
    // member: SecretForm posts currentContext.domain as share_domain on every
    // creation (including the anonymous homepage), and the server only admits
    // pool members from guests.
    const domain = currentDomain.value || getPoolFallbackDomain();
    const isCanonical = domain === canonicalDomain;
    return {
      domain,
      extid: isCanonical ? undefined : findExtidByDomain(permissionsDomains.value, domain),
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
    findDomainByExtid(permissionsDomains.value, extid);

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
    // Reset to the pool's preferred entry (canonical when it is a member),
    // never to a canonical host the operator excluded from the picker.
    resetContext: () => { currentDomain.value = getPoolFallbackDomain(); sessionStorage.removeItem('domainContext'); },
    refreshDomains: fetchDomainsForOrganization,
    getDomainDisplayName,
    getExtidByDomain: (domain: string) => findExtidByDomain(permissionsDomains.value, domain),
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
  isInitializing = false;
  watcherInitialized = false;
  currentFetchController = null;
  bootstrapStoreInstance = null;
  permissionsDomains.value = [];
  permissionsInstance = null;
}
