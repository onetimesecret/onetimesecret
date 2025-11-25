<!-- src/layouts/ColonelLayout.vue -->

<script setup lang="ts">
  import ColonelAdminLayout from '@/components/layout/ColonelAdminLayout.vue';
  import DefaultHeader from '@/components/layout/DefaultHeader.vue';
  import QuietFooter from '@/components/layout/QuietFooter.vue';
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
      <DefaultHeader v-bind="props" />
    </template>

    <template #main>
      <ColonelAdminLayout>
        <slot></slot>
      </ColonelAdminLayout>
    </template>

    <template #footer>
      <QuietFooter v-bind="props" />
    </template>
  </BaseLayout>
</template>
