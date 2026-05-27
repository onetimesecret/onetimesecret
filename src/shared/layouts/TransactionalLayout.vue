<!-- src/shared/layouts/TransactionalLayout.vue -->

<script setup lang="ts">
  import TransactionalFooter from '@/shared/components/layout/TransactionalFooter.vue';
  import TransactionalHeader from '@/shared/components/layout/TransactionalHeader.vue';
  import type { LayoutProps } from '@/types/ui/layouts';
  import { computed } from 'vue';

  import BaseLayout from './BaseLayout.vue';

  // Defaults for every boolean prop this layout consumes. Vue coerces a
  // missing Boolean prop to `false`; once `false` is bound, the child
  // component's own withDefaults can't recover it. So each `display*` flag
  // must have its true-default declared here, not relied on downstream.
  const props = withDefaults(defineProps<LayoutProps>(), {
    displayHeader: true,
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
    return props.displayMasthead ? `${base} py-8` : `${base} pt-8 pb-8`;
  });
</script>

<template>
  <BaseLayout v-bind="props">
    <template #header>
      <TransactionalHeader v-bind="props" />
    </template>

    <template #main>
      <main :class="mainClasses" name="DefaultLayout">
        <slot></slot>
      </main>
    </template>

    <template #footer>
      <TransactionalFooter v-bind="props" />
    </template>
  </BaseLayout>
</template>
