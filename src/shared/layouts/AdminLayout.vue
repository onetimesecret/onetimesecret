<!-- src/shared/layouts/AdminLayout.vue -->

<script setup lang="ts">
  import ColonelAdminLayout from '@/apps/colonel/components/layout/ColonelAdminLayout.vue';
  import ManagementHeader from '@/shared/components/layout/ManagementHeader.vue';
  import ManagementFooter from '@/shared/components/layout/ManagementFooter.vue';
  import type { LayoutProps } from '@/types/ui/layouts';

  import BaseLayout from './BaseLayout.vue';

  const props = withDefaults(defineProps<LayoutProps>(), {
    displayFeedback: true,
    displayFooterLinks: true,
    displayMasthead: true,
    displayNavigation: true,
    displayVersion: true,
    displayToggles: true,
    displayPoweredBy: true,
  });
</script>

<template>
  <BaseLayout v-bind="props">
    <template #header>
      <ManagementHeader v-bind="props" />
    </template>

    <template #main>
      <ColonelAdminLayout>
        <slot></slot>
      </ColonelAdminLayout>
    </template>

    <template #footer>
      <ManagementFooter v-bind="props" />
    </template>
  </BaseLayout>
</template>
