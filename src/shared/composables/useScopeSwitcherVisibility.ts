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
   * Owner + manage_orgs entitlement gate for the org switcher.
   * Standalone (billing disabled): owner role alone is sufficient.
   * Billing enabled: owner + manage_orgs entitlement required.
   * When entitlements haven't been fetched yet (null), allow owners through
   * to avoid hiding the switcher during initial load.
   */
  const canManageOrgs = computed(() => {
    const org = organizationStore.currentOrganization;
    if (org?.current_user_role !== 'owner') return false;

    if (!bootstrapStore.billing_enabled) return true;

    const ents = org.entitlements;
    if (!ents) return true; // not yet fetched — don't block owners
    return ents.includes(ENTITLEMENTS.MANAGE_ORGS);
  });

  /**
   * "Trivial solo" org context: the user has exactly one organization — their
   * auto-created default — and is its only member. There is nothing to switch
   * between and no collaborators to manage, so both the org switcher and the
   * static org-name fallback are suppressed for a cleaner new-user surface.
   *
   * Requires is_default so a user who belongs to exactly one self-created
   * (non-default) org still sees the switcher and org chip — that org is a
   * deliberate choice, not a trivial artifact of signup.
   *
   * Limited to free-tier plans: this suppression exists to declutter brand-new
   * *free* signups. A paying customer working solo inside their default
   * workspace is a deliberate, non-trivial account and must keep the org
   * context surface. A missing planid is treated as free so the switcher stays
   * hidden while the list is still loading (matching the member_count guard).
   *
   * member_count comes from the organizations list safe_dump. When the list
   * hasn't loaded yet (length 0) or the count is unknown, this stays false so
   * the switcher is never hidden prematurely.
   */
  const isSoloDefaultContext = computed(() => {
    const orgs = organizationStore.organizations;
    if (orgs.length !== 1) return false;
    if (!orgs[0].is_default) return false;
    const planid = orgs[0].planid;
    if (planid && !/^free_v\d+$/.test(planid)) return false;
    const memberCount = orgs[0].member_count;
    return typeof memberCount === 'number' && memberCount <= 1;
  });

  // Hide org switcher on custom domains (the domain IS the org scope), and for
  // a brand-new self-signup user whose only org is their solo default.
  const showOrgSwitcher = computed(
    () => !isCustom.value
      && visibility.value.organization !== 'hide'
      && isOrganizationSwitcherEnabled()
      && canManageOrgs.value
      && !isSoloDefaultContext.value
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
    isSoloDefaultContext,
  };
}
