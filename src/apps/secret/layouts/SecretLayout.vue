<!-- src/apps/secret/layouts/SecretLayout.vue -->

<!--
  Secret Layout for conceal, metadata, and incoming flows.
  Authentication-aware: uses workspace components when authenticated,
  transactional components for public/guest access.
-->

<script setup lang="ts">
  import OrganizationContextBar from '@/apps/workspace/components/navigation/OrganizationContextBar.vue';
  import WorkspaceFooter from '@/apps/workspace/components/layout/WorkspaceFooter.vue';
  import ManagementHeader from '@/shared/components/layout/ManagementHeader.vue';
  import TransactionalFooter from '@/shared/components/layout/TransactionalFooter.vue';
  import TransactionalHeader from '@/shared/components/layout/TransactionalHeader.vue';
  import BaseLayout from '@/shared/layouts/BaseLayout.vue';
  import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
  import { useDomainsStore, useReceiptListStore } from '@/shared/stores';
  import { storeToRefs } from 'pinia';
  import type { LayoutProps } from '@/types/ui/layouts';
  import { computed, onMounted } from 'vue';

  const props = withDefaults(defineProps<LayoutProps>(), {
    displayMasthead: true,
    displayNavigation: true,
    displayFeedback: true,
    displayFooterLinks: true,
    displayVersion: true,
    displayToggles: true,
    displayPoweredBy: false,
  });

  const bootstrapStore = useBootstrapStore();
  const { authenticated, domains_enabled: domainsEnabled } = storeToRefs(bootstrapStore);

  // Store instances for centralized data loading (for authenticated view)
  const receiptListStore = useReceiptListStore();
  const domainsStore = useDomainsStore();

  // Load stores when authenticated (needed for workspace footer mobile nav)
  onMounted(() => {
    if (authenticated.value) {
      receiptListStore.refreshRecords(true);
      if (domainsEnabled) {
        domainsStore.refreshRecords(true);
      }
    }
  });

  // Transactional layout: narrower, centered content
  const transactionalClasses = computed(() => {
    const base = 'container mx-auto flex min-w-[320px] max-w-2xl flex-1 flex-col px-4 justify-start';
    return props.displayMasthead ? `${base} py-8` : `${base} pt-16 pb-8`;
  });
</script>

<template>
  <BaseLayout v-bind="props">
    <template #header>
      <!-- Authenticated: ManagementHeader with context bar -->
      <ManagementHeader v-if="authenticated" v-bind="props">
        <OrganizationContextBar />
      </ManagementHeader>
      <!-- Guest: TransactionalHeader (simpler) -->
      <TransactionalHeader v-else v-bind="props" />
    </template>

    <template #main>
      <!-- Authenticated: wider workspace-style layout -->
      <div v-if="authenticated" class="min-h-screen bg-gray-50 dark:bg-gray-900">
        <div class="container mx-auto min-w-[320px] max-w-4xl px-4 py-8">
          <main class="min-w-0 flex-1">
            <slot></slot>
          </main>
        </div>
      </div>
      <!-- Guest: narrower transactional layout -->
      <main v-else :class="transactionalClasses">
        <slot></slot>
      </main>
    </template>

    <template #footer>
      <!-- Authenticated: WorkspaceFooter (no region switcher, SaaS links) -->
      <WorkspaceFooter v-if="authenticated" v-bind="props" />
      <!-- Guest: TransactionalFooter (region switcher, toggles) -->
      <TransactionalFooter v-else v-bind="props" />
    </template>
  </BaseLayout>
</template>
