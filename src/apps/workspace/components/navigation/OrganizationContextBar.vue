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
  - ENABLE_ORGS env var (feature flag for org switcher)
  - Route meta.scopesAvailable (per-route visibility control)
-->

<script setup lang="ts">
import OIcon from '@/shared/components/icons/OIcon.vue';
import DomainContextSwitcher from '@/apps/workspace/components/navigation/DomainContextSwitcher.vue';
import OrganizationScopeSwitcher from '@/apps/workspace/components/navigation/OrganizationScopeSwitcher.vue';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import { useScopeSwitcherVisibility } from '@/shared/composables/useScopeSwitcherVisibility';
import { isOrganizationSwitcherEnabled } from '@/utils/features';
import { computed, onMounted, ref } from 'vue';
import { RouterLink } from 'vue-router';
import axios from 'axios';
const organizationStore = useOrganizationStore();
const {
  visibility,
  showOrgSwitcher,
  lockOrgSwitcher,
  showDomainSwitcher,
  lockDomainSwitcher,
  isSoloDefaultContext,
} = useScopeSwitcherVisibility();

// The static org-name chip is the fallback when the switcher is hidden by role
// (admins/members still need workspace context). It is suppressed for a solo
// default org, where the switcher is hidden to declutter the new-user surface.
const showStaticOrgName = computed(() =>
  isLoaded.value &&
  visibility.value.organization !== 'hide' &&
  !showOrgSwitcher.value &&
  !isSoloDefaultContext.value &&
  isOrganizationSwitcherEnabled() &&
  organizationStore.hasOrganizations &&
  !!organizationStore.currentOrganization
);

const orgDisplayName = computed(() =>
  organizationStore.currentOrganization?.display_name || ''
);

const orgIsDefault = computed(() =>
  organizationStore.currentOrganization?.is_default ?? false
);

const orgInitial = computed(() =>
  (orgDisplayName.value || 'O').charAt(0).toUpperCase()
);

const orgSettingsPath = computed(() => {
  const org = organizationStore.currentOrganization;
  if (!org?.extid) return null;
  const role = org.current_user_role;
  if (role !== 'owner' && role !== 'admin') return null;
  return `/org/${org.extid}`;
});

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
  (showOrgSwitcher.value || showDomainSwitcher.value || showStaticOrgName.value)
);
</script>

<template>
  <!-- Inline context switchers (wrapper styling provided by parent slot) -->
  <template v-if="shouldShow">
    <!-- Organization Switcher (owners) -->
    <OrganizationScopeSwitcher
      v-if="showOrgSwitcher"
      :locked="lockOrgSwitcher" />

    <!-- Static org name (admins/members — no switcher, but establishes workspace context) -->
    <div
      v-else-if="showStaticOrgName"
      class="inline-flex h-10 items-center gap-2 rounded-lg bg-gray-100 px-3 text-sm font-medium text-gray-700 dark:bg-gray-800 dark:text-gray-300"
      :title="orgDisplayName"
      data-testid="org-context-static">
      <span
        class="flex size-5 items-center justify-center rounded text-xs font-bold"
        :class="orgIsDefault
          ? 'bg-gray-200 dark:bg-gray-700'
          : 'bg-brand-500 text-white dark:bg-brand-500'"
        aria-hidden="true">
        <OIcon
          v-if="orgIsDefault"
          collection="heroicons"
          name="building-office"
          aria-label=""
          class="size-3.5 text-gray-600 dark:text-gray-300" />
        <template v-else>{{ orgInitial }}</template>
      </span>
      <span
        class="hidden max-w-[120px] truncate font-brand lg:inline"
        :title="orgDisplayName">
        {{ orgDisplayName }}
      </span>
      <RouterLink
        v-if="orgSettingsPath"
        :to="orgSettingsPath"
        class="rounded p-0.5 text-gray-400 transition-colors hover:bg-gray-200 hover:text-gray-600 dark:text-gray-500 dark:hover:bg-gray-600 dark:hover:text-gray-300"
        :aria-label="`${orgDisplayName} settings`">
        <OIcon
          collection="heroicons"
          name="cog"
          class="size-4"
          aria-hidden="true" />
      </RouterLink>
    </div>

    <!-- Domain Switcher -->
    <DomainContextSwitcher
      v-if="showDomainSwitcher"
      :locked="lockDomainSwitcher" />
  </template>
</template>
