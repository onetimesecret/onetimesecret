<!-- src/shared/components/layout/QuietHeader.vue -->

<!-- TODO: Rename "quiet" layout components to "identity" (e.g. IdentityHeader) -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import BrandedMasthead from '@/shared/components/layout/BrandedMastHead.vue';
  import MastHead from '@/shared/components/layout/MastHead.vue';
  import { useProductIdentity } from '@/shared/stores/identityStore';
  import type { LayoutProps } from '@/types/ui/layouts';
  import { computed } from 'vue';
  const { t } = useI18n();

  const productIdentity = useProductIdentity();

  const props = withDefaults(defineProps<LayoutProps>(), {
    displayMasthead: true,
    displayNavigation: false,
  });

  const headertext = computed(() => productIdentity.allowPublicHomepage ? t('web.homepage.create_a_secure_link') : t('web.homepage.secure_links'));
  const subtext = computed(() => productIdentity.allowPublicHomepage
      ? t('web.homepage.send_sensitive_information_that_can_only_be_viewed_once')
      : t('web.homepage.a_trusted_way_to_share_sensitive_information_etc'));
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
