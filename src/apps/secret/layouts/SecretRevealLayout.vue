<!-- src/apps/secret/layouts/SecretRevealLayout.vue -->

<!--
  Secret Reveal Layout for the /secret/:secretIdentifier reveal page.
  Minimal chrome for focused secret viewing experience.
  Composes BaseLayout with BrandedHeader + BrandedFooter.
-->

<script setup lang="ts">
  import BrandedFooter from '@/apps/secret/components/layout/BrandedFooter.vue';
  import BrandedHeader from '@/apps/secret/components/layout/BrandedHeader.vue';
  import BaseLayout from '@/shared/layouts/BaseLayout.vue';
  import type { LayoutProps } from '@/types/ui/layouts';
  import { computed } from 'vue';

  const props = withDefaults(defineProps<LayoutProps>(), {
    displayMasthead: false,
    displayNavigation: false,
    displayFeedback: false,
    displayFooterLinks: false,
    displayVersion: false,
    displayToggles: true,
    displayPoweredBy: false,
  });

  const mainClasses = computed(() => {
    const base = 'container mx-auto flex min-w-[320px] max-w-2xl flex-1 flex-col px-4 justify-start';
    return props.displayMasthead ? `${base} py-8` : `${base} pt-16 pb-8`;
  });
</script>

<template>
  <BaseLayout v-bind="props">
    <template #header>
      <BrandedHeader v-bind="props" />
    </template>
    <template #main>
      <main :class="mainClasses">
        <slot></slot>
      </main>
    </template>
    <template #footer>
      <BrandedFooter v-bind="props" />
    </template>
  </BaseLayout>
</template>
