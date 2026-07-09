<!-- src/apps/secret/components/layout/BrandedHeader.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import BrandedMasthead from '@/apps/secret/components/layout/BrandedMastHead.vue';
  import MastHead from '@/shared/components/layout/MastHead.vue';
  import { useHeaderEnabled } from '@/shared/composables/useHeaderEnabled';
  import { useProductIdentity } from '@/shared/stores/identityStore';
  import type { LayoutProps } from '@/types/ui/layouts';
  import { computed } from 'vue';
  const { t } = useI18n();

  const productIdentity = useProductIdentity();

  const props = withDefaults(defineProps<LayoutProps>(), {
    displayMasthead: true,
    displayNavigation: false,
  });

  // Operator-level header gate (HEADER_ENABLED), shared via composable. When
  // disabled, the entire <header> banner landmark collapses — no empty
  // landmark, no padding band.
  const { headerEnabled } = useHeaderEnabled();

  // Copy tracks what the domain's homepage actually offers: the create
  // headline for the classic form, the send headline when the homepage
  // presents the incoming form (secrets_mode=incoming), and the neutral
  // secure-links copy when the homepage is private.
  const headertext = computed(() => {
    if (!productIdentity.allowPublicHomepage) return t('web.homepage.secure_links');
    return productIdentity.homepageSecretsMode === 'incoming'
      ? t('web.homepage.send_a_secret')
      : t('web.homepage.create_a_secure_link');
  });
  const subtext = computed(() => {
    if (!productIdentity.allowPublicHomepage) {
      return t('web.homepage.a_trusted_way_to_share_sensitive_information_etc');
    }
    return productIdentity.homepageSecretsMode === 'incoming'
      ? t('web.homepage.deliver_sensitive_information_directly_and_securely')
      : t('web.homepage.send_sensitive_information_that_can_only_be_viewed_once');
  });
</script>

<template>
  <header
    v-if="headerEnabled"
    class="bg-white dark:bg-gray-900">
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
