<!-- src/apps/workspace/components/dashboard/brand/BrandPreviewColumn.vue -->

<script setup lang="ts">
  /**
   * The fixed preview column. Stays put (sticky) while the left panel swaps,
   * and shows the recipient page (the branded secret-link view, via SecretPreview)
   * from the edited tokens. A single instance in DomainBrand serves both tabs,
   * since delivery locale + reveal instructions also shape the recipient page;
   * v-model:revealed lets the page drive the sample's reveal state (focus-follow
   * from the Delivery instruction fields).
   *
   * Treated as a preview, not a live interface: the card carries a dashed frame
   * and a persistent "Preview" tag, so it reads as a sample of the recipient
   * page rather than part of the editing UI. Its interactions (logo upload,
   * reveal toggle) are intentional, so we frame + label rather than disable
   * them. The card spans the full column so its edges align with the path
   * switcher cards above.
   *
   * A thin primary accent bar tops the recipient card. Everything derives from
   * `brandSettings` inline, so the column reflects the edited domain, not the
   * operator's injected <html> theme. (No secondary_color accent: it has no live
   * consumer yet, so the preview mustn't imply one — see SimpleBrandPanel.)
   */
  import SecretPreview from '@/apps/workspace/components/dashboard/SecretPreview.vue';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import type { BrandSettings, ImageProps } from '@/schemas/shapes/v3/custom-domain';
  import { computed } from 'vue';
  import { Composer, useI18n } from 'vue-i18n';

  const { t } = useI18n();

  const props = defineProps<{
    brandSettings: BrandSettings;
    logoImage?: ImageProps | null;
    onLogoUpload: (file: File) => Promise<unknown>;
    onLogoRemove: () => Promise<unknown>;
    secretIdentifier: string;
    previewI18n: Composer;
  }>();

  // Pass-through reveal state: syncs with the parent when bound, plain local
  // state otherwise (SecretPreview's toggle writes back through it either way).
  const revealed = defineModel<boolean>('revealed', { default: false });

  const primary = computed(() => props.brandSettings.primary_color ?? 'var(--color-brand-500)');
  const stripeStyle = computed(() => ({ background: primary.value }));
</script>

<template>
  <div class="lg:sticky lg:top-4">
    <!-- Recipient page. Dashed border (not solid) reads as a sample/preview,
         not a live surface — reinforcing the PREVIEW badge. -->
    <div
      class="overflow-hidden rounded-xl border border-dashed border-gray-300 bg-white shadow-sm
        dark:border-gray-600 dark:bg-gray-800">
      <div
        class="flex items-center gap-2 border-b border-gray-200 bg-gray-50 px-3.5 py-2
          dark:border-gray-700 dark:bg-gray-700/60">
        <span
          class="inline-flex items-center gap-1 rounded-full bg-gray-200 px-2 py-0.5 text-[10px]
            font-semibold tracking-wide text-gray-600 uppercase dark:bg-gray-600 dark:text-gray-200">
          <OIcon
            collection="mdi"
            name="eye-outline"
            class="size-3"
            aria-hidden="true" />
          {{ t('web.branding.preview_badge') }}
        </span>
        <span class="text-[11.5px] font-medium text-gray-500 dark:text-gray-300">
          {{ t('web.branding.preview_recipient_page') }}
        </span>
      </div>
      <div
        class="h-1 w-full"
        :style="stripeStyle"></div>
      <!-- De-emphasis veil: a subtle scrim mutes the sample so its
           recipient-facing "reveal" button doesn't visually compete with the
           page's Save CTA in the header. pointer-events-none keeps the
           intentional interactions (logo upload, reveal toggle) usable
           underneath; a sibling overlay (not an opacity ancestor) so the logo
           upload modal still layers above it cleanly. -->
      <div class="relative">
        <SecretPreview
          v-model:revealed="revealed"
          :domain-branding="brandSettings"
          :logo-image="logoImage"
          :preview-i18n="previewI18n"
          :on-logo-upload="onLogoUpload"
          :on-logo-remove="onLogoRemove"
          :secret-identifier="secretIdentifier" />
        <div
          aria-hidden="true"
          class="pointer-events-none absolute inset-0 bg-gray-900/[0.08] dark:bg-gray-950/25"></div>
      </div>
    </div>
  </div>
</template>
