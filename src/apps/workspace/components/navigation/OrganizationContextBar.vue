<!-- src/apps/workspace/components/navigation/OrganizationContextBar.vue -->

<!--
  Organization Context Bar Component

  A contextual navigation bar that displays workspace scope information.
  Shows the domain switcher for the current workspace context.

  Layout:
  ┌────────────────────────────────────────────────────────────────┐
  │ dev.onetime.dev ▼                                              │
  └────────────────────────────────────────────────────────────────┘
-->

<script setup lang="ts">
import DomainContextSwitcher from '@/shared/components/navigation/DomainContextSwitcher.vue';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import { useScopeSwitcherVisibility } from '@/shared/composables/useScopeSwitcherVisibility';
import { computed, onMounted, ref } from 'vue';
import axios from 'axios';
const organizationStore = useOrganizationStore();
const {
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
 * AND the domain switcher is visible based on route meta.
 * Wait for initial load to avoid flash of content.
 */
const shouldShow = computed(() =>
  isLoaded.value &&
  organizationStore.hasOrganizations &&
  showDomainSwitcher.value
);
</script>

<template>
  <!-- Inline context switchers (wrapper styling provided by parent slot) -->
  <template v-if="shouldShow">
    <!-- Domain Switcher -->
    <DomainContextSwitcher
      v-if="showDomainSwitcher"
      :locked="lockDomainSwitcher" />
  </template>
</template>
