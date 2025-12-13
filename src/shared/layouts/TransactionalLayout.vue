<!-- src/shared/layouts/TransactionalLayout.vue -->

<script setup lang="ts">
  import DefaultFooter from '@/shared/components/layout/DefaultFooter.vue';
  import DefaultHeader from '@/shared/components/layout/DefaultHeader.vue';
  import type { LayoutProps } from '@/types/ui/layouts';
  import { computed } from 'vue';

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

  // Content always starts at top - no vertical centering
  // Custom domains (no MastHead) get extra top padding to compensate
  const mainClasses = computed(() => {
    const base = 'container mx-auto flex min-w-[320px] max-w-full flex-1 flex-col px-0 justify-start';
    return props.displayMasthead ? `${base} py-8` : `${base} pt-16 pb-8`;
  });
</script>

<template>
  <BaseLayout v-bind="props">
    <template #header>
      <DefaultHeader v-bind="props" />
    </template>

    <template #main>
      <main :class="mainClasses" name="DefaultLayout">
        <slot></slot>
      </main>
    </template>

    <template #footer>
      <DefaultFooter v-bind="props" />
    </template>
  </BaseLayout>
</template>
