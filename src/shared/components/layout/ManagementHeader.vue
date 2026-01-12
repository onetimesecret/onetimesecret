<!-- src/shared/components/layout/ManagementHeader.vue -->

<!--
  Management Header Component

  Features:
  - Wider container (max-w-4xl instead of max-w-2xl)
  - Default slot for custom content (e.g., context bars)
  - Toggleable primary nav via displayPrimaryNav prop
  - Cleaner separation between brand and navigation
-->

<script setup lang="ts">
  import MastHead from '@/shared/components/layout/MastHead.vue';
  import ImprovedPrimaryNav from '@/shared/components/navigation/ImprovedPrimaryNav.vue';
  import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
  import type { LayoutProps } from '@/types/ui/layouts';
  import { storeToRefs } from 'pinia';

  const props = withDefaults(defineProps<LayoutProps>(), {
    displayMasthead: true,
    displayNavigation: true,
    displayPrimaryNav: true,
    colonel: false,
  });

  const bootstrapStore = useBootstrapStore();
  const { authenticated } = storeToRefs(bootstrapStore);
</script>

<template>
  <header class="border-b border-gray-200 bg-white dark:border-gray-800 dark:bg-gray-900">
    <!-- Top Bar with Logo and User Menu -->
    <div class="container mx-auto min-w-[320px] max-w-4xl px-4">
      <div class="py-4">
        <MastHead v-if="displayMasthead" v-bind="props" />
      </div>
    </div>

    <!-- Slot for custom content (e.g., OrganizationContextBar) -->
    <slot ></slot>

    <!-- Primary Navigation Bar (for authenticated users) - Hidden on mobile -->
    <div
      v-if="authenticated && displayNavigation && displayPrimaryNav"
      class="hidden bg-gray-100 dark:bg-gray-800 md:block">
      <div class="container mx-auto min-w-[320px] max-w-4xl px-4">
        <ImprovedPrimaryNav />
      </div>
    </div>
  </header>
</template>
