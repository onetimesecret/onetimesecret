<!-- src/apps/workspace/components/dashboard/brand/BrandLogoField.vue -->

<script setup lang="ts">
  /**
   * The Simple form's logo control — the discoverable, in-form counterpart to
   * the click-the-preview-image affordance in SecretPreview (which stays as a
   * second entry point). Both open the shared ImageUploadModal, which stages the
   * picked file and commits (upload/remove) only on its confirm CTA — so a logo
   * change is a deliberate, previewed action rather than an upload-on-pick
   * surprise. The two entry points share useLogoImage for the thumbnail so their
   * validity / data-URL handling can't drift.
   */
  import type { ImageProps } from '@/schemas/shapes/v3/custom-domain';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import ImageUploadModal from '@/shared/components/modals/ImageUploadModal.vue';
  import { useLogoImage } from '@/shared/composables/useLogoImage';
  import { ref } from 'vue';
  import { useI18n } from 'vue-i18n';

  const { t } = useI18n();

  const props = defineProps<{
    logoImage?: ImageProps | null;
    onLogoUpload: (file: File) => Promise<unknown>;
    onLogoRemove: () => Promise<unknown>;
  }>();

  // Pass a getter so the composable tracks prop changes (a commit swaps it).
  const { isValidLogo, logoSrc } = useLogoImage(() => props.logoImage);

  const isModalOpen = ref(false);
</script>

<template>
  <div>
    <div class="text-xs font-semibold text-gray-700 dark:text-gray-300">
      {{ t('web.branding.logo') }}
    </div>
    <div class="mt-1.5 flex items-center gap-3">
      <!-- Thumbnail / empty placeholder -->
      <div
        class="flex size-14 shrink-0 items-center justify-center overflow-hidden rounded-lg border
          border-gray-200 bg-gray-50 dark:border-gray-600 dark:bg-gray-900">
        <img
          v-if="isValidLogo"
          :src="logoSrc"
          :alt="logoImage?.filename || t('web.layout.brand_logo')"
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
          {{ isValidLogo ? t('web.branding.replace_logo') : t('web.branding.upload_logo') }}
        </button>
        <span class="text-[11px] text-gray-400">{{ t('web.branding.logo_field_hint') }}</span>
      </div>
    </div>

    <ImageUploadModal
      :is-open="isModalOpen"
      :current-image="logoImage"
      :title="t('web.branding.logo_modal_title')"
      :hint="t('web.branding.logo_modal_hint')"
      :save-label="t('web.branding.logo_modal_save')"
      :remove-label="t('web.branding.remove_logo')"
      :on-save="onLogoUpload"
      :on-remove="onLogoRemove"
      @close="isModalOpen = false" />
  </div>
</template>
