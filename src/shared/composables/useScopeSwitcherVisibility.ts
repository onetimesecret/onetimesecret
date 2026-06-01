// src/shared/composables/useScopeSwitcherVisibility.ts

/**
 * Scope Switcher Visibility Composable
 *
 * Provides route-aware visibility control for organization and domain
 * scope switchers based on route meta configuration.
 *
 * Each route can specify visibility for organization and domain switchers:
 * - 'show': Switcher is visible and interactive
 * - 'locked': Switcher is visible but disabled (context is fixed by route)
 * - 'hide': Switcher is not rendered
 *
 * @see src/types/router.ts - ScopeSwitcherState, ScopesAvailable types
 */

import { computed } from 'vue';
import { useRoute } from 'vue-router';
import type { ScopeSwitcherState } from '@/types/router';
import { isOrganizationSwitcherEnabled } from '@/utils/features';
import { useProductIdentity } from '@/shared/stores/identityStore';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { ENTITLEMENTS } from '@/types/organization';
import { storeToRefs } from 'pinia';

interface ScopeSwitcherVisibility {
  organization: ScopeSwitcherState;
  domain: ScopeSwitcherState;
}

const defaults: ScopeSwitcherVisibility = {
  organization: 'show',
  domain: 'hide',
};

export function useScopeSwitcherVisibility() {
  const route = useRoute();
  const { isCustom } = storeToRefs(useProductIdentity());
  const organizationStore = useOrganizationStore();
  const bootstrapStore = useBootstrapStore();

  const visibility = computed<ScopeSwitcherVisibility>(() => ({
    organization: route.meta.scopesAvailable?.organization ?? defaults.organization,
    domain: route.meta.scopesAvailable?.domain ?? defaults.domain,
  }));

  /**
   * Owner + manage_org entitlement gate for the org switcher.
   * Standalone (billing disabled): owner role alone is sufficient.
   * Billing enabled: owner + manage_org entitlement required.
   * When entitlements haven't been fetched yet (null), allow owners through
   * to avoid hiding the switcher during initial load.
   */
  const canManageOrgs = computed(() => {
    const org = organizationStore.currentOrganization;
    if (org?.current_user_role !== 'owner') return false;

    if (!bootstrapStore.billing_enabled) return true;

    const ents = org.entitlements;
    if (!ents) return true; // not yet fetched — don't block owners
    return ents.includes(ENTITLEMENTS.MANAGE_ORG);
  });

  // Hide org switcher on custom domains (the domain IS the org scope)
  const showOrgSwitcher = computed(
    () => !isCustom.value
      && visibility.value.organization !== 'hide'
      && isOrganizationSwitcherEnabled()
      && canManageOrgs.value
  );
  const lockOrgSwitcher = computed(() => visibility.value.organization === 'locked');

  const showDomainSwitcher = computed(() => visibility.value.domain !== 'hide');
  const lockDomainSwitcher = computed(() => visibility.value.domain === 'locked');

  return {
    visibility,
    showOrgSwitcher,
    lockOrgSwitcher,
    showDomainSwitcher,
    lockDomainSwitcher,
  };
}
