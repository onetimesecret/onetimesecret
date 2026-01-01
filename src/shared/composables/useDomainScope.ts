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

import { WindowService } from '@/services/window.service';
import { useDomainsStore } from '@/shared/stores/domainsStore';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import { computed, ref, watch } from 'vue';

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

// Window service config (module-level for reuse)
const windowConfig = WindowService.getMultiple(['domains_enabled', 'site_host', 'display_domain']);
const domainsEnabled = windowConfig.domains_enabled;
const canonicalDomain = windowConfig.site_host;
const displayDomain = windowConfig.display_domain;

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

/** Find extid for a given display_domain from store domains */
function findExtidByDomain(
  storeDomains: Array<{ display_domain: string; extid: string }>,
  domain: string
): string | undefined {
  return storeDomains.find((d) => d.display_domain === domain)?.extid;
}

/** Initialize domain scope on module load (runs once). Returns promise for awaiting. */
async function initializeDomainScope(
  fetchFn: () => Promise<void>,
  getAvailable: () => string[]
): Promise<void> {
  if (isInitialized.value) return;

  try {
    if (domainsEnabled) {
      await fetchFn();
      const saved = localStorage.getItem('domainScope');
      const available = getAvailable();
      currentDomain.value = (saved && available.includes(saved))
        ? saved : available[0] || canonicalDomain || '';
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
  const domainsStore = useDomainsStore();
  const organizationStore = useOrganizationStore();

  const availableDomains = computed<string[]>(() =>
    buildAvailableDomains(domainsStore.domains || [])
  );

  const fetchDomainsForOrganization = async () => {
    if (!domainsEnabled) return;
    // Guard: Only fetch if we have a valid organization ID
    const orgId = organizationStore.currentOrganization?.id;
    if (!orgId) {
      console.debug('[useDomainScope] Skipping fetch: no currentOrganization set yet');
      return;
    }
    isLoadingDomains.value = true;
    try {
      await domainsStore.fetchList(orgId);
    } catch (error) {
      console.warn('[useDomainScope] Failed to fetch domains:', error);
    } finally {
      isLoadingDomains.value = false;
    }
  };

  // Watch for organization changes (including initial load from null -> org)
  // immediate: true ensures we catch the first org load from OrganizationContextBar
  watch(() => organizationStore.currentOrganization?.id, async (newOrgId, oldOrgId) => {
    if (newOrgId && newOrgId !== oldOrgId) {
      await fetchDomainsForOrganization();
      if (currentDomain.value && !availableDomains.value.includes(currentDomain.value)) {
        currentDomain.value = availableDomains.value[0] || canonicalDomain || '';
      }
    }
  }, { immediate: true });

  // Initialize async - returns promise for components that need to await
  // Note: If currentOrganization is not yet set, initializeDomainScope will skip the fetch
  // and the watcher above will handle fetching when the organization becomes available
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

  const setScope = (domain: string) => {
    if (availableDomains.value.includes(domain)) {
      currentDomain.value = domain;
      localStorage.setItem('domainScope', domain);
    }
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
    /** Promise that resolves when initial domain fetch completes */
    initialized: initPromise,
  };
}
