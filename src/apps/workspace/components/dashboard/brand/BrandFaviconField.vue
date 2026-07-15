<!-- src/apps/workspace/components/dashboard/brand/BrandFaviconField.vue -->

<script setup lang="ts">
  /**
   * The Simple form's favicon control (#3780) — the upload counterpart to the
   * "Refresh favicon" button, which forces a background re-fetch from the
   * domain. The two affordances coexist: uploading here stamps
   * favicon_source='user_upload' server-side (which disables the refresh button,
   * since a forced fetch can't overwrite a user upload), and removing the upload
   * clears provenance and re-enqueues an auto-fetch. Opens the shared
   * ImageUploadModal, which stages the picked file and commits (upload/remove)
   * only on its confirm CTA. Reuses useLogoImage for the thumbnail so the
   * validity / data-URL handling can't drift from the logo control.
   */
  import type { ImageProps } from '@/schemas/shapes/v3/custom-domain';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import ImageUploadModal from '@/shared/components/modals/ImageUploadModal.vue';
  import { useLogoImage } from '@/shared/composables/useLogoImage';
  import { ref } from 'vue';
  import { useI18n } from 'vue-i18n';

  const { t } = useI18n();

  const props = defineProps<{
    faviconImage?: ImageProps | null;
    onFaviconUpload: (file: File) => Promise<unknown>;
    onFaviconRemove: () => Promise<unknown>;
  }>();

  // Favicon-appropriate upload constraints — deliberately NOT the logo limits.
  // Accept the formats a favicon actually ships in: .ico (which the shared logo
  // allowlist omits) plus PNG and SVG. Cap the size far below the shared 2MB
  // image limit — real favicons are a few KB to tens of KB, so 256KB is generous
  // headroom while still rejecting oversized files client-side. The server
  // (UpdateDomainIcon) enforces its own allowlist + ceiling as the real gate.
  const FAVICON_ACCEPT = 'image/png,image/svg+xml,image/x-icon,image/vnd.microsoft.icon,.ico';
  const FAVICON_MAX_BYTES = 256 * 1024; // 256KB

  // Pass a getter so the composable tracks prop changes (a commit swaps it).
  const { isValidLogo: isValidFavicon, logoSrc: faviconSrc } = useLogoImage(
    () => props.faviconImage
  );

  const isModalOpen = ref(false);
</script>

<template>
  <div>
    <div class="text-xs font-semibold text-gray-700 dark:text-gray-300">
      {{ t('web.branding.favicon') }}
    </div>
    <div class="mt-1.5 flex items-center gap-3">
      <!-- Thumbnail / empty placeholder -->
      <div
        class="flex size-14 shrink-0 items-center justify-center overflow-hidden rounded-lg border
          border-gray-200 bg-gray-50 dark:border-gray-600 dark:bg-gray-900">
        <img
          v-if="isValidFavicon"
          :src="faviconSrc"
          :alt="faviconImage?.filename || t('web.branding.favicon_preview_alt')"
          class="size-full object-contain" />
        <OIcon
          v-else
          collection="mdi"
          name="image-outline"
          class="size-6 text-gray-400 dark:text-gray-500"
          aria-hidden="true" />
      </div>

      <!-- Controls -->
      <div class="flex flex-col items-start gap-1.5">
        <button
          type="button"
          data-testid="domain-favicon-upload"
          @click="isModalOpen = true"
          class="inline-flex items-center gap-1.5 rounded-lg border border-gray-200 bg-white px-3
            py-1.5 text-xs font-semibold text-gray-700 shadow-sm transition-colors
            hover:border-gray-400 focus:ring-1 focus:ring-brand-500 focus:outline-none
            dark:border-gray-600 dark:bg-gray-800 dark:text-gray-200">
          <OIcon
            collection="mdi"
            name="upload"
            class="size-4"
            aria-hidden="true" />
          {{ isValidFavicon ? t('web.branding.replace_favicon') : t('web.branding.upload_favicon') }}
        </button>
        <span class="text-[11px] text-gray-400">{{ t('web.branding.favicon_field_hint') }}</span>
      </div>
    </div>

    <ImageUploadModal
      :is-open="isModalOpen"
      :current-image="faviconImage"
      :title="t('web.branding.favicon_modal_title')"
      :hint="t('web.branding.favicon_modal_hint')"
      :save-label="t('web.branding.favicon_modal_save')"
      :remove-label="t('web.branding.remove_favicon')"
      :accept="FAVICON_ACCEPT"
      :max-size-bytes="FAVICON_MAX_BYTES"
      :on-save="onFaviconUpload"
      :on-remove="onFaviconRemove"
      @close="isModalOpen = false" />
  </div>
</template>
