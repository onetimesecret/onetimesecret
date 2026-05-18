<!-- src/apps/colonel/layouts/ColonelLayout.vue -->

<!--
  Colonel Layout for admin users.
  Based on ManagementLayout with ManagementFooter and ColonelAdminLayout.
-->

<script setup lang="ts">
  import BaseLayout from '@/shared/layouts/BaseLayout.vue';
  import ManagementHeader from '@/shared/components/layout/ManagementHeader.vue';
  import ManagementFooter from '@/shared/components/layout/ManagementFooter.vue';
  import PreviewModeBanner from '@/shared/components/ui/PreviewModeBanner.vue';
  import ColonelAdminLayout from '@/apps/colonel/components/layout/ColonelAdminLayout.vue';
  import { usePreviewPlanMode } from '@/shared/composables/usePreviewPlanMode';
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

  const { isPreviewModeActive } = usePreviewPlanMode();
</script>

<template>
  <BaseLayout v-bind="props">
    <template #header>
      <PreviewModeBanner v-if="isPreviewModeActive" />
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
