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
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const organizationStore = useOrganizationStore();

const isLoaded = ref(false);

// Fetch organizations on mount to determine visibility
onMounted(async () => {
  if (!organizationStore.hasOrganizations) {
    try {
      await organizationStore.fetchOrganizations();
    } catch (error) {
      console.error('[OrganizationContextBar] Failed to fetch organizations:', error);
    }
  }
  isLoaded.value = true;
});

/**
 * Show context bar when user has any organizations (including default).
 * This allows users to discover the organization feature and create new orgs.
 * Wait for initial load to avoid flash of content.
 */
const shouldShow = computed(() => isLoaded.value && organizationStore.hasOrganizations);
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
        <OrganizationScopeSwitcher />

        <!-- Separator -->
        <span class="text-gray-300 dark:text-gray-600" aria-hidden="true">|</span>

        <!-- Domain Switcher -->
        <DomainScopeSwitcher />
      </div>
    </div>
  </div>
</template>
