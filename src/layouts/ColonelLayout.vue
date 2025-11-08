<!-- src/layouts/ColonelLayout.vue -->

<script setup lang="ts">
  import ColonelNavigation from '@/components/colonel/ColonelNavigation.vue';
  import DefaultHeader from '@/components/layout/DefaultHeader.vue';
  import QuietFooter from '@/components/layout/QuietFooter.vue';
  import BaseLayout from './BaseLayout.vue';
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
</script>

<template>
  <BaseLayout v-bind="props">
    <template #header>
      <DefaultHeader v-bind="props" />
      <ColonelNavigation />
    </template>

    <template #main>

      <main
        class="container mx-auto min-w-[320px] max-w-2xl px-4 py-8"
        name="ColonelLayout">
        <slot></slot>
      </main>
    </template>

    <template #footer>
      <QuietFooter v-bind="props" />
    </template>
  </BaseLayout>
</template>
