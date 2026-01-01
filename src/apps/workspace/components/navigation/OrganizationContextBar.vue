<!-- src/apps/workspace/components/navigation/OrganizationContextBar.vue -->

<!--
  Organization Context Bar Component

  A contextual navigation bar that displays workspace scope information.
  Shows organization and domain switchers on the same horizontal line.

  Layout:
  ┌────────────────────────────────────────────────────────────────┐
  │ Workspace ▼  |  dev.onetime.dev ▼                              │
  └────────────────────────────────────────────────────────────────┘
-->

<script setup lang="ts">
import DomainScopeSwitcher from '@/shared/components/navigation/DomainScopeSwitcher.vue';
import OrganizationScopeSwitcher from '@/apps/workspace/components/navigation/OrganizationScopeSwitcher.vue';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import { useScopeSwitcherVisibility } from '@/shared/composables/useScopeSwitcherVisibility';
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import axios from 'axios';

const { t } = useI18n();
const organizationStore = useOrganizationStore();
const {
  showOrgSwitcher,
  lockOrgSwitcher,
  showDomainSwitcher,
  lockDomainSwitcher,
} = useScopeSwitcherVisibility();

const isLoaded = ref(false);

// Fetch organizations on mount to determine visibility
onMounted(async () => {
  if (!organizationStore.hasOrganizations) {
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
 * AND at least one switcher is visible based on route meta.
 * Wait for initial load to avoid flash of content.
 */
const shouldShow = computed(() =>
  isLoaded.value &&
  organizationStore.hasOrganizations &&
  (showOrgSwitcher.value || showDomainSwitcher.value)
);

/**
 * Show separator only when both switchers are visible
 */
const showSeparator = computed(() => showOrgSwitcher.value && showDomainSwitcher.value);
</script>

<template>
  <div
    v-if="shouldShow"
    class="border-t border-gray-200 bg-gray-50 dark:border-gray-700 dark:bg-gray-800/50"
    role="navigation"
    :aria-label="t('web.layout.workspace_context')">
    <div class="container mx-auto min-w-[320px] max-w-4xl px-4">
      <div class="flex items-center gap-3 py-2">
        <!-- Organization Switcher -->
        <OrganizationScopeSwitcher
          v-if="showOrgSwitcher"
          :locked="lockOrgSwitcher" />

        <!-- Separator (only when both visible) -->
        <span
          v-if="showSeparator"
          class="text-gray-300 dark:text-gray-600"
          aria-hidden="true">|</span>

        <!-- Domain Switcher -->
        <DomainScopeSwitcher
          v-if="showDomainSwitcher"
          :locked="lockDomainSwitcher" />
      </div>
    </div>
  </div>
</template>
