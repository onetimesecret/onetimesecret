<!-- src/apps/colonel/layouts/ColonelLayout.vue -->

<!--
  Colonel Layout for admin users.
  Based on ManagementLayout with ManagementFooter and ColonelAdminLayout.
-->

<script setup lang="ts">
  import BaseLayout from '@/shared/layouts/BaseLayout.vue';
  import ManagementHeader from '@/shared/components/layout/ManagementHeader.vue';
  import ManagementFooter from '@/shared/components/layout/ManagementFooter.vue';
  import TestModeBanner from '@/shared/components/ui/TestModeBanner.vue';
  import ColonelAdminLayout from '@/apps/colonel/components/layout/ColonelAdminLayout.vue';
  import { useTestPlanMode } from '@/shared/composables/useTestPlanMode';
  import type { LayoutProps } from '@/types/ui/layouts';

  const props = withDefaults(defineProps<LayoutProps>(), {
    displayFeedback: true,
    displayFooterLinks: true,
    displayMasthead: true,
    displayNavigation: true,
    displayVersion: true,
    displayToggles: true,
    displayPoweredBy: true,
  });

  const { isTestModeActive } = useTestPlanMode();
</script>

<template>
  <BaseLayout v-bind="props">
    <template #header>
      <TestModeBanner v-if="isTestModeActive" />
      <ManagementHeader v-bind="props" />
    </template>

    <template #main>
      <ColonelAdminLayout>
        <slot ></slot>
      </ColonelAdminLayout>
    </template>

    <template #footer>
      <ManagementFooter v-bind="props" />
    </template>
  </BaseLayout>
</template>
