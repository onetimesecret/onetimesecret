// src/shared/composables/useDomainScope.ts
/**
 * Domain Scope Composable
 *
 * Provides workspace-level domain scope context for managing secrets
 * across multiple custom domains. Domain scope is a session-level filter
 * that determines which domain context is active for the current workspace.
 *
 * @see docs/product/interaction-modes.md - Domain Scope concept
 */

import { WindowService } from '@/services/window.service';
import { computed, ref } from 'vue';

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

/**
 * Composable for managing domain scope in the workspace.
 *
 * Domain scope elevates domain selection from a form field to a
 * workspace-level context that affects secret creation and management.
 *
 * @example
 * const { currentScope, isScopeActive, setScope } = useDomainScope();
 *
 * // Watch for scope changes
 * watch(() => currentScope.value.domain, (domain) => {
 *   operations.updateField('share_domain', domain);
 * });
 */
export function useDomainScope() {
  const {
    domains_enabled: domainsEnabled,
    site_host: canonicalDomain,
    custom_domains: customDomains = [],
  } = WindowService.getMultiple(['domains_enabled', 'site_host', 'custom_domains']);

  // Build available domains list
  const availableDomains = computed<string[]>(() => {
    const domains = [...(customDomains || [])];
    if (canonicalDomain && !domains.includes(canonicalDomain)) {
      domains.push(canonicalDomain);
    }
    return domains;
  });

  // Initialize on first use
  if (!isInitialized.value) {
    const savedDomain = localStorage.getItem('domainScope');
    if (savedDomain && availableDomains.value.includes(savedDomain)) {
      currentDomain.value = savedDomain;
    } else {
      // Default to first custom domain, or canonical if none
      currentDomain.value = availableDomains.value[0] || canonicalDomain || '';
    }
    isInitialized.value = true;
  }

  /**
   * Current domain scope as a structured object
   */
  const currentScope = computed<DomainScope>(() => {
    const domain = currentDomain.value || canonicalDomain || '';
    const isCanonical = domain === canonicalDomain;

    return {
      domain,
      displayName: isCanonical ? 'Personal' : domain,
      isCanonical,
    };
  });

  /**
   * Whether domain scope feature is active (user has custom domains)
   */
  const isScopeActive = computed<boolean>(() => domainsEnabled && customDomains && customDomains.length > 0);

  /**
   * Whether multiple scopes are available for switching
   */
  const hasMultipleScopes = computed<boolean>(() => availableDomains.value.length > 1);

  /**
   * Set the current domain scope
   * @param domain - Domain to switch to
   */
  const setScope = (domain: string) => {
    if (availableDomains.value.includes(domain)) {
      currentDomain.value = domain;
      localStorage.setItem('domainScope', domain);
    }
  };

  /**
   * Reset scope to canonical domain
   */
  const resetScope = () => {
    currentDomain.value = canonicalDomain || '';
    localStorage.removeItem('domainScope');
  };

  return {
    currentScope,
    isScopeActive,
    hasMultipleScopes,
    availableDomains,
    setScope,
    resetScope,
  };
}
