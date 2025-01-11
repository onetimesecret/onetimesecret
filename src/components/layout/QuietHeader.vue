<script setup lang="ts">
  import type { LayoutProps } from '@/types/ui/layouts';
  import { useProductIdentity } from '@/stores/identityStore';
  import MastHead from '@/components/layout/MastHead.vue';
  import BrandedMasthead from '@/components/layout/BrandedMastHead.vue';
import { computed } from 'vue';
  const productIdentity = useProductIdentity();

  const props = withDefaults(defineProps<LayoutProps>(), {
    displayMasthead: true,
    displayNavigation: false,
  });

  const headertext = computed(() => {
    return productIdentity.allowPublicHomepage ? 'Create a secure link' : 'Secure Links';
  });
  const subtext = computed(() => {
    return productIdentity.allowPublicHomepage
      ? 'Send sensitive information that can only be viewed once'
      : 'A trusted way to share sensitive information that self-destructs after being viewed.';
  });
</script>

<template>
  <header class="bg-white dark:bg-gray-900">

    <div
      v-if="displayMasthead"
      class="container mx-auto min-w-[320px] max-w-2xl p-4">
      <MastHead v-if="productIdentity.isCanonical" v-bind="props" />
      <BrandedMasthead
        v-else
        :headertext="headertext"
        :subtext="subtext"
        v-bind="props"/>
    </div>

  </header>
</template>
