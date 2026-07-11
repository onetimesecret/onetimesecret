<!-- src/apps/workspace/components/dashboard/brand/BrandLogoField.vue -->

<script setup lang="ts">
  /**
   * The Simple form's logo control — the discoverable, in-form counterpart to
   * the click-the-preview-image affordance in SecretPreview (which stays as a
   * second entry point). Both share useLogoImage so validity / data-URL /
   * change handling can't drift.
   *
   * Upload/Remove hit the API immediately (useBranding.handleLogoUpload /
   * removeLogo), independent of the header Save — unlike the color/corner/font
   * controls, which defer to Save. The hint line says so.
   */
  import type { ImageProps } from '@/schemas/shapes/v3/custom-domain';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useLogoImage } from '@/shared/composables/useLogoImage';
  import { useI18n } from 'vue-i18n';

  const { t } = useI18n();

  const props = defineProps<{
    logoImage?: ImageProps | null;
    onLogoUpload: (file: File) => Promise<void>;
    onLogoRemove: () => Promise<void>;
  }>();

  // Pass a getter so the composable tracks prop changes (upload/remove swap it).
  const { isValidLogo, logoSrc, onFileChange } = useLogoImage(() => props.logoImage);

  const onChange = (event: Event) => onFileChange(event, props.onLogoUpload);
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
      <div class="flex flex-col gap-1.5">
        <div class="flex items-center gap-2">
          <!-- File input nested in the label: the whole button is the picker
               target, and focus-within paints the focus ring on keyboard tab. -->
          <label
            class="inline-flex cursor-pointer items-center gap-1.5 rounded-lg
              border border-gray-200 bg-white px-3 py-1.5 text-xs font-semibold text-gray-700
              shadow-sm transition-colors focus-within:ring-1 focus-within:ring-brand-500
              hover:border-gray-400 dark:border-gray-600 dark:bg-gray-800 dark:text-gray-200">
            <OIcon
              collection="mdi"
              name="upload"
              class="size-4"
              aria-hidden="true" />
            {{ isValidLogo ? t('web.branding.replace_logo') : t('web.branding.upload_logo') }}
            <input
              type="file"
              class="sr-only"
              accept="image/*"
              @change="onChange" />
          </label>

          <button
            v-if="isValidLogo"
            type="button"
            @click="onLogoRemove"
            class="inline-flex items-center gap-1 rounded-lg px-2.5 py-1.5 text-xs font-semibold
              text-red-600 transition-colors hover:bg-red-50 dark:text-red-400
              dark:hover:bg-red-900/30">
            <OIcon
              collection="mdi"
              name="trash-can-outline"
              class="size-4"
              aria-hidden="true" />
            {{ t('web.COMMON.remove') }}
          </button>
        </div>
        <span class="text-[11px] text-gray-400">{{ t('web.branding.logo_field_hint') }}</span>
      </div>
    </div>
  </div>
</template>
