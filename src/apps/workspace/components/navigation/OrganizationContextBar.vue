<!-- src/apps/workspace/components/navigation/OrganizationContextBar.vue -->

<!--
  Organization Context Bar Component

  A contextual navigation bar that displays workspace scope information.
  Shows organization and domain switchers based on feature flags and route config.

  Layout (when both enabled):
  ┌────────────────────────────────────────────────────────────────┐
  │ Default Workspace ▼  dev.onetime.dev ▼                         │
  └────────────────────────────────────────────────────────────────┘

  Visibility controlled by:
  - ENABLE_ORGANIZATIONS env var (feature flag for org switcher)
  - Route meta.scopesAvailable (per-route visibility control)
-->

<script setup lang="ts">
import DomainContextSwitcher from '@/shared/components/navigation/DomainContextSwitcher.vue';
import OrganizationScopeSwitcher from '@/apps/workspace/components/navigation/OrganizationScopeSwitcher.vue';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import { useScopeSwitcherVisibility } from '@/shared/composables/useScopeSwitcherVisibility';
import { computed, onMounted, ref } from 'vue';
import axios from 'axios';
const organizationStore = useOrganizationStore();
const {
  showOrgSwitcher,
  lockOrgSwitcher,
  showDomainSwitcher,
  lockDomainSwitcher,
} = useScopeSwitcherVisibility();

const isLoaded = ref(false);

// Fetch organizations on mount to determine visibility
// Use isListFetched (not hasOrganizations) to ensure full list is loaded.
// hasOrganizations can be true if fetchOrganization() added a single org.
onMounted(async () => {
  if (!organizationStore.isListFetched) {
    try {
      await organizationStore.fetchOrganizations();
    } catch (error) {
      if (axios.isCancel(error)) {
        // Expected when another component triggers a fetch - visible with DevTools "Verbose" level
        console.debug('[OrganizationContextBar] Fetch canceled (expected):', error);
      } else {
        console.error('[OrganizationContextBar] Failed to fetch organizations:', error);
      }
    }
  }

  // Initialize currentOrganization if not already set (restores from localStorage)
  if (!organizationStore.currentOrganization && organizationStore.hasOrganizations) {
    const initialOrg = organizationStore.restorePersistedSelection();
    if (initialOrg) {
      organizationStore.setCurrentOrganization(initialOrg);
    }
  }

  isLoaded.value = true;
});

/**
 * Show context bar when user has any organizations (including default)
 * AND at least one switcher is visible based on route meta and feature flags.
 * Wait for initial load to avoid flash of content.
 */
const shouldShow = computed(() =>
  isLoaded.value &&
  organizationStore.hasOrganizations &&
  (showOrgSwitcher.value || showDomainSwitcher.value)
);
</script>

<template>
  <!-- Inline context switchers (wrapper styling provided by parent slot) -->
  <template v-if="shouldShow">
    <!-- Organization Switcher -->
    <OrganizationScopeSwitcher
      v-if="showOrgSwitcher"
      :locked="lockOrgSwitcher" />

    <!-- Domain Switcher -->
    <DomainContextSwitcher
      v-if="showDomainSwitcher"
      :locked="lockDomainSwitcher" />
  </template>
</template>
