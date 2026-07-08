<!-- src/apps/workspace/components/dashboard/brand/BrandPreviewColumn.vue -->

<script setup lang="ts">
  /**
   * The fixed preview column. Stays put (sticky) while the left path panel swaps,
   * and shows every recipient-facing surface from the SAME edited tokens:
   *   - Recipient page (the branded secret-link view, via SecretPreview)
   *   - Homepage · enabled / · disabled (BrandHomepageTiles)
   *
   * A thin primary accent bar tops the recipient card. Everything derives from
   * `brandSettings` inline, so the column reflects the edited domain, not the
   * operator's injected <html> theme. (No secondary_color accent: it has no live
   * consumer yet, so the preview mustn't imply one — see SimpleBrandPanel.)
   */
  import SecretPreview from '@/apps/workspace/components/dashboard/SecretPreview.vue';
  import type { BrandSettings, ImageProps } from '@/schemas/shapes/v3/custom-domain';
  import { computed } from 'vue';
  import { Composer, useI18n } from 'vue-i18n';

  import BrandHomepageTiles from './BrandHomepageTiles.vue';

  const { t } = useI18n();

  const props = defineProps<{
    brandSettings: BrandSettings;
    logoImage?: ImageProps | null;
    onLogoUpload: (file: File) => Promise<void>;
    onLogoRemove: () => Promise<void>;
    secretIdentifier: string;
    previewI18n: Composer;
    displayDomain?: string;
  }>();

  const primary = computed(() => props.brandSettings.primary_color ?? 'var(--color-brand-500)');
  const stripeStyle = computed(() => ({ background: primary.value }));
  const primaryHexUpper = computed(() => props.brandSettings.primary_color?.toUpperCase() ?? '');
</script>

<template>
  <div class="lg:sticky lg:top-4">
    <!-- Recipient page -->
    <div class="overflow-hidden rounded-xl border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
      <div
        class="flex items-center gap-2 border-b border-gray-200 bg-gray-100 px-3.5 py-2.5
          dark:border-gray-700 dark:bg-gray-700">
        <span class="text-[11.5px] font-semibold tracking-wide text-gray-500 uppercase dark:text-gray-300">
          {{ t('web.branding.preview_recipient_page') }}
        </span>
        <span
          v-if="displayDomain"
          class="font-mono text-xs text-gray-400">{{ displayDomain }}</span>
      </div>
      <div
        class="h-1 w-full"
        :style="stripeStyle"></div>
      <SecretPreview
        :domain-branding="brandSettings"
        :logo-image="logoImage"
        :preview-i18n="previewI18n"
        :on-logo-upload="onLogoUpload"
        :on-logo-remove="onLogoRemove"
        :secret-identifier="secretIdentifier" />
    </div>

    <!-- Homepage tiles -->
    <div class="mt-2.5">
      <BrandHomepageTiles
        :brand-settings="brandSettings"
        :logo-image="logoImage" />
    </div>

    <!-- Caption -->
    <div class="mt-2.5 flex items-center gap-2 text-xs text-gray-500 dark:text-gray-400">
      <span
        class="size-3 rounded ring-1 ring-gray-200"
        :style="{ background: primary }"></span>
      <span>
        {{ t('web.branding.preview_live') }}<template v-if="primaryHexUpper"> · <span class="font-mono">{{ primaryHexUpper }}</span></template>
      </span>
    </div>
  </div>
</template>
