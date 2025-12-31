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

  const visibility = computed<ScopeSwitcherVisibility>(() => ({
    organization: route.meta.scopesAvailable?.organization ?? defaults.organization,
    domain: route.meta.scopesAvailable?.domain ?? defaults.domain,
  }));

  const showOrgSwitcher = computed(() => visibility.value.organization !== 'hide');
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
