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
import { storeToRefs } from 'pinia';
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

// Bootstrap config refs - lazily initialized on first composable use
let domainsEnabled: boolean = false;
let canonicalDomain: string = '';
let displayDomain: string = '';
let serverDomainScope: string | null = null;
let configInitialized = false;

/** Initialize config from bootstrap store (called on first composable use) */
function initConfig(): void {
  if (configInitialized) return;
  const bootstrapStore = useBootstrapStore();
  const refs = storeToRefs(bootstrapStore);
  domainsEnabled = refs.domains_enabled.value;
  canonicalDomain = refs.site_host.value;
  displayDomain = refs.display_domain.value;
  serverDomainScope = refs.domain_scope.value;
  configInitialized = true;
}

/** Get display name for a given domain */
function getDomainDisplayName(domain: string): string {
  const isCanonical = domain === canonicalDomain;
  const defaultDisplay = displayDomain || canonicalDomain || 'onetimesecret.com';
  return isCanonical ? defaultDisplay : domain;
}

/** Build available domains list from store */
function buildAvailableDomains(storeDomains: Array<{ display_domain: string }>): string[] {
  const domainNames = storeDomains.map((d) => d.display_domain);
  if (canonicalDomain && !domainNames.includes(canonicalDomain)) {
    domainNames.push(canonicalDomain);
  }
  return domainNames;
}

/** Get the preferred default domain (custom domain preferred over canonical) */
function getPreferredDomain(available: string[]): string {
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
  initConfig();

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
    const domain = currentDomain.value || canonicalDomain || '';
    const isCanonical = domain === canonicalDomain;
    return {
      domain,
      extid: isCanonical ? undefined : findExtidByDomain(domainsStore.domains || [], domain),
      displayName: getDomainDisplayName(domain),
      isCanonical,
    };
  });

  const setScope = async (domain: string): Promise<void> => {
    if (!availableDomains.value.includes(domain)) return;
    currentDomain.value = domain;
    localStorage.setItem('domainScope', domain);
    await syncDomainScopeToServer($api, domain);
  };

  return {
    currentScope,
    isScopeActive: computed<boolean>(() => domainsEnabled),
    hasMultipleScopes: computed<boolean>(() => availableDomains.value.length > 1),
    availableDomains,
    isLoadingDomains: computed(() => isLoadingDomains.value),
    setScope,
    resetScope: () => { currentDomain.value = canonicalDomain || ''; localStorage.removeItem('domainScope'); },
    refreshDomains: fetchDomainsForOrganization,
    getDomainDisplayName,
    getExtidByDomain: (domain: string) => findExtidByDomain(domainsStore.domains || [], domain),
    initialized: initPromise,
  };
}
