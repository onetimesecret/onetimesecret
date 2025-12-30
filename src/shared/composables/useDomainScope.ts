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

/**
 * Composable for managing domain scope in the workspace.
 * Domains are scoped to the current organization.
 */
export function useDomainScope() {
  const domainsStore = useDomainsStore();
  const organizationStore = useOrganizationStore();

  const availableDomains = computed<string[]>(() => buildAvailableDomains(domainsStore.domains || []));

  const fetchDomainsForOrganization = async () => {
    if (!domainsEnabled) return;
    isLoadingDomains.value = true;
    try {
      await domainsStore.fetchList(organizationStore.currentOrganization?.id);
    } catch (error) {
      console.debug('[useDomainScope] Failed to fetch domains:', error);
    } finally {
      isLoadingDomains.value = false;
    }
  };

  // Watch for organization changes and refresh domains
  watch(
    () => organizationStore.currentOrganization?.id,
    async (newOrgId, oldOrgId) => {
      if (newOrgId && newOrgId !== oldOrgId) {
        await fetchDomainsForOrganization();
        if (currentDomain.value && !availableDomains.value.includes(currentDomain.value)) {
          currentDomain.value = availableDomains.value[0] || canonicalDomain || '';
        }
      }
    },
    { immediate: false }
  );

  // Initialize on first use - fetch domains before restoring saved selection
  if (!isInitialized.value) {
    isInitialized.value = true;
    if (domainsEnabled) {
      fetchDomainsForOrganization().then(() => {
        const savedDomain = localStorage.getItem('domainScope');
        currentDomain.value =
          savedDomain && availableDomains.value.includes(savedDomain)
            ? savedDomain
            : availableDomains.value[0] || canonicalDomain || '';
      });
    } else {
      currentDomain.value = canonicalDomain || '';
    }
  }

  const currentScope = computed<DomainScope>(() => ({
    domain: currentDomain.value || canonicalDomain || '',
    displayName: getDomainDisplayName(currentDomain.value || canonicalDomain || ''),
    isCanonical: (currentDomain.value || canonicalDomain || '') === canonicalDomain,
  }));

  const setScope = (domain: string) => {
    if (availableDomains.value.includes(domain)) {
      currentDomain.value = domain;
      localStorage.setItem('domainScope', domain);
    }
  };

  const resetScope = () => {
    currentDomain.value = canonicalDomain || '';
    localStorage.removeItem('domainScope');
  };

  return {
    currentScope,
    isScopeActive: computed<boolean>(() => domainsEnabled),
    hasMultipleScopes: computed<boolean>(() => availableDomains.value.length > 1),
    availableDomains,
    isLoadingDomains: computed(() => isLoadingDomains.value),
    setScope,
    resetScope,
    refreshDomains: fetchDomainsForOrganization,
    getDomainDisplayName,
  };
}
