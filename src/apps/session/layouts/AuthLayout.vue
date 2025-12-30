<!-- src/apps/session/layouts/AuthLayout.vue -->

<script setup lang="ts">
import DefaultFooter from '@/shared/components/layout/DefaultFooter.vue';
import DefaultHeader from '@/shared/components/layout/DefaultHeader.vue';
import BaseLayout from '@/shared/layouts/BaseLayout.vue';
import type { LayoutProps } from '@/types/ui/layouts';
import { computed } from 'vue';

const props = withDefaults(defineProps<LayoutProps>(), {
  displayMasthead: false,
  displayNavigation: false,
  displayFooterLinks: false,
  displayFeedback: false,
  displayVersion: true,
  displayToggles: true,
  displayPoweredBy: true,
});

const mainClasses = computed(() => {
  const base = 'container mx-auto flex min-w-[320px] max-w-2xl flex-1 flex-col px-4 justify-start';
  return props.displayMasthead ? `${base} py-8` : `${base} pt-16 pb-8`;
});
</script>

<template>
  <BaseLayout v-bind="props">
    <template #header>
      <DefaultHeader v-bind="props" />
    </template>
    <template #main>
      <main :class="mainClasses" name="AuthLayout">
        <slot></slot>
      </main>
    </template>
    <template #footer>
      <DefaultFooter v-bind="props" />
    </template>
  </BaseLayout>
</template>
