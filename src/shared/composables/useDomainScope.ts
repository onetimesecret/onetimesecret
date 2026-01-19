// src/shared/composables/useDomainScope.ts

/**
 * Domain Scope Composable
 *
 * Provides workspace-level domain scope context for managing secrets
 * across multiple custom domains. Domain scope is a session-level filter
 * that determines which domain context is active for the current workspace.
 *
 * Domains are scoped to the currently active organization - when the user
 * switches organizations, the available domains list updates accordingly.
 *
 * @see docs/product/interaction-modes.md - Domain Scope concept
 */

import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { useDomainsStore } from '@/shared/stores/domainsStore';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import type { AxiosInstance } from 'axios';
import { computed, inject, ref, watch } from 'vue';

export interface DomainScope {
  /** The domain hostname (e.g., "acme.example.com" or "onetimesecret.com") */
  domain: string;
  /** The external ID for API calls (e.g., "cd1234abcdef") - undefined for canonical domain */
  extid: string | undefined;
  /** Display-friendly name for the scope */
  displayName: string;
  /** Whether this is the canonical (default) domain */
  isCanonical: boolean;
}

// Shared state for domain scope across components
const currentDomain = ref('');
const isInitialized = ref(false);
const isLoadingDomains = ref(false);

// Request ID to handle race conditions during rapid org switches
let currentFetchRequestId = 0;

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
    serverDomainScope: store.domain_scope,
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

/** Sync domain scope to backend (fire-and-forget) */
async function syncDomainScopeToServer(
  $api: AxiosInstance | undefined,
  domain: string
): Promise<void> {
  if (!$api) return;
  try {
    await $api.post('/api/account/update-domain-scope', { domain });
  } catch (error) {
    console.warn('[useDomainScope] Failed to sync to server:', error);
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
      console.debug('[useDomainScope] Skipping fetch: no currentOrganization set yet');
      return false;
    }
    const requestId = ++currentFetchRequestId;
    isLoadingDomains.value = true;
    try {
      await domainsStore.fetchList(orgId);
      return requestId === currentFetchRequestId;
    } catch (error) {
      console.warn('[useDomainScope] Failed to fetch domains:', error);
      return false;
    } finally {
      if (requestId === currentFetchRequestId) {
        isLoadingDomains.value = false;
      }
    }
  };
}

/** Initialize domain scope on module load (runs once). Returns promise for awaiting. */
async function initializeDomainScope(
  fetchFn: () => Promise<boolean | void>,
  getAvailable: () => string[]
): Promise<void> {
  if (isInitialized.value) return;

  const { domainsEnabled, canonicalDomain, serverDomainScope } = getConfig();

  try {
    if (domainsEnabled) {
      await fetchFn();
      const available = getAvailable();

      // Priority: server preference > localStorage > preferred domain
      const localScope = localStorage.getItem('domainScope');

      if (serverDomainScope && available.includes(serverDomainScope)) {
        // Server-side preference takes priority
        currentDomain.value = serverDomainScope;
        localStorage.setItem('domainScope', serverDomainScope); // Sync localStorage
      } else if (localScope && available.includes(localScope)) {
        // Fall back to localStorage if valid
        currentDomain.value = localScope;
      } else {
        // Fall back to preferred domain (first custom domain or canonical)
        currentDomain.value = getPreferredDomain(available);
      }
    } else {
      currentDomain.value = canonicalDomain || '';
    }
  } finally {
    // Set initialized flag after completion to prevent race conditions
    isInitialized.value = true;
  }
}

/**
 * Composable for managing domain scope in the workspace.
 * Domains are scoped to the current organization.
 */
export function useDomainScope() {
  const $api = inject('api') as AxiosInstance | undefined;
  const domainsStore = useDomainsStore();
  const organizationStore = useOrganizationStore();

  const availableDomains = computed<string[]>(() =>
    buildAvailableDomains(domainsStore.domains || [])
  );

  const fetchDomainsForOrganization = createDomainFetcher(organizationStore, domainsStore);

  // Watch for organization changes (including initial load from null -> org)
  watch(() => organizationStore.currentOrganization?.id, async (newOrgId, oldOrgId) => {
    if (newOrgId && newOrgId !== oldOrgId) {
      const isCurrentRequest = await fetchDomainsForOrganization();
      if (isCurrentRequest && currentDomain.value && !availableDomains.value.includes(currentDomain.value)) {
        currentDomain.value = getPreferredDomain(availableDomains.value);
      }
    }
  }, { immediate: true });

  const initPromise = initializeDomainScope(fetchDomainsForOrganization, () => availableDomains.value);

  const currentScope = computed<DomainScope>(() => {
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

  /**
   * Set the current domain scope
   * @param domain - The domain to set as active scope
   * @param skipBackendSync - If true, skips the backend sync (use when server already set the scope)
   */
  const setScope = async (domain: string, skipBackendSync = false): Promise<void> => {
    if (!availableDomains.value.includes(domain)) return;
    currentDomain.value = domain;
    localStorage.setItem('domainScope', domain);
    if (!skipBackendSync) {
      await syncDomainScopeToServer($api, domain);
    }
  };

  return {
    currentScope,
    isScopeActive: computed<boolean>(() => getConfig().domainsEnabled),
    hasMultipleScopes: computed<boolean>(() => availableDomains.value.length > 1),
    availableDomains,
    isLoadingDomains: computed(() => isLoadingDomains.value),
    setScope,
    resetScope: () => {
      const { canonicalDomain } = getConfig();
      currentDomain.value = canonicalDomain || '';
      localStorage.removeItem('domainScope');
    },
    refreshDomains: fetchDomainsForOrganization,
    getDomainDisplayName,
    getExtidByDomain: (domain: string) => findExtidByDomain(domainsStore.domains || [], domain),
    initialized: initPromise,
  };
}
