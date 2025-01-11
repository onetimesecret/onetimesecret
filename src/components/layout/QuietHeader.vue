<script setup lang="ts">
  import type { LayoutProps } from '@/types/ui/layouts';
  import { useProductIdentity } from '@/stores/identityStore';
  import MastHead from '@/components/layout/MastHead.vue';
  import BrandedMasthead from '@/components/layout/BrandedMastHead.vue';

  const productIdentity = useProductIdentity();

  const props = withDefaults(defineProps<LayoutProps>(), {
    displayMasthead: true,
    displayNavigation: false,
  });


</script>

<template>
  <header class="bg-white dark:bg-gray-900">
    <div
      v-if="displayMasthead"
      class="container mx-auto min-w-[320px] max-w-2xl p-4">
      <MastHead v-if="productIdentity.isCanonical" v-bind="props" />
      <BrandedMasthead v-else v-bind="props"/>
    </div>
  </header>
</template>
