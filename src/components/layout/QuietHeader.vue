<!-- src/components/layout/QuietHeader.vue -->

<!-- TODO: Rename "quiet" layout components to "identity" (e.g. IdentityHeader) -->

<script setup lang="ts">
  import BrandedMasthead from '@/components/layout/BrandedMastHead.vue';
  import MastHead from '@/components/layout/MastHead.vue';
  import { useProductIdentity } from '@/stores/identityStore';
  import type { LayoutProps } from '@/types/ui/layouts';
  import { computed } from 'vue';
  import { useI18n } from 'vue-i18n';
  const { t } = useI18n();

  const productIdentity = useProductIdentity();

  const props = withDefaults(defineProps<LayoutProps>(), {
    displayMasthead: true,
    displayNavigation: false,
  });

  const headertext = computed(() => productIdentity.allowPublicHomepage ? t('create-a-secure-link') : t('secure-links'));
  const subtext = computed(() => productIdentity.allowPublicHomepage
      ? t('send-sensitive-information-that-can-only-be-viewed-once')
      : t('a-trusted-way-to-share-sensitive-information-etc'));
</script>

<template>
  <header class="bg-white dark:bg-gray-900">
    <div
      v-if="displayMasthead"
      class="container mx-auto min-w-[320px] max-w-2xl p-4">
      <BrandedMasthead
        v-if="productIdentity.isCustom"
        :headertext="headertext"
        :subtext="subtext"
        v-bind="props" />

      <MastHead
        v-else
        v-bind="props" />
    </div>
  </header>
</template>
