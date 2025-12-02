<!-- src/layouts/ColonelLayout.vue -->

<script setup lang="ts">
  import ColonelAdminLayout from '@/shared/components/layout/ColonelAdminLayout.vue';
  import ImprovedHeader from '@/shared/components/layout/ImprovedHeader.vue';
  import ImprovedFooter from '@/shared/components/layout/ImprovedFooter.vue';
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
      <ImprovedHeader v-bind="props" />
    </template>

    <template #main>
      <ColonelAdminLayout>
        <slot></slot>
      </ColonelAdminLayout>
    </template>

    <template #footer>
      <ImprovedFooter v-bind="props" />
    </template>
  </BaseLayout>
</template>
