<!-- src/apps/workspace/components/dashboard/BrandSettingsBar.vue -->

/** eslint-disable tailwindcss/classnames-order */

<script setup lang="ts">
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import type { BrandSettings } from '@/schemas/shapes/v3/custom-domain';
  import {
    CornerStyle,
    cornerStyleDisplayMap,
    cornerStyleIconMap,
    cornerStyleOptions,
    fontDisplayMap,
    FontFamily,
    fontIconMap,
    fontOptions,
    type CornerStyle as CornerStyleType,
    type FontFamily as FontFamilyType,
  } from '@/shared/utils/brand-helpers';
  import { checkBrandContrast } from '@/utils/brand-palette';
  import { computed } from 'vue';
  import { useI18n, Composer } from 'vue-i18n';

  import ColorPicker from '@/shared/components/common/ColorPicker.vue';
  import CycleButton from '@/shared/components/common/CycleButton.vue';

  const { t } = useI18n();

  const props = defineProps<{
    modelValue: BrandSettings;
    isLoading: boolean;
    isInitialized: boolean;
    previewI18n: Composer;
    hasUnsavedChanges: boolean;
  }>();

  const emit = defineEmits<{
    (e: 'update:modelValue', value: BrandSettings): void;
    (e: 'submit'): void;
  }>();

  const updateBrandSetting = <K extends keyof BrandSettings>(
    key: K,
    value: BrandSettings[K]
  ) => {
    emit('update:modelValue', {
      ...props.modelValue,
      [key]: value,
    });
  };

  const isDisabled = computed(() => props.isLoading || !props.hasUnsavedChanges);

  const contrastCheck = computed(() => checkBrandContrast(props.modelValue.primary_color ?? ''));
  const showContrastWarning = computed(() => !contrastCheck.value.passesAA);
  const contrastRatioDisplay = computed(() => contrastCheck.value.ratio.toFixed(1));

  const buttonText = computed(() => props.isLoading ? t('web.LABELS.saving') : t('web.LABELS.save'));
  const handleSubmit = () => emit('submit');
</script>

<template>
  <div v-if="!isLoading || isInitialized">
    <!-- prettier-ignore-attribute class -->
    <div
      class="border-b border-gray-200
        bg-white/80 backdrop-blur-sm
        dark:border-gray-700 dark:bg-gray-800/80">
      <div class="mx-auto w-fit px-2 py-3">
        <form
          @submit.prevent="handleSubmit"
          class="flex min-w-0 items-center gap-4">
          <!-- Left section - wrap in flex container -->
          <div class="flex min-w-0 shrink items-center gap-4">
            <!-- Color Picker -->
            <div class="flex min-w-0 shrink items-center gap-4">
              <ColorPicker
                :model-value="modelValue.primary_color ?? undefined"
                @update:model-value="(value) => updateBrandSetting('primary_color', value)"
                name="brand[primary_color]"
                variant="sketch"
                :disable-alpha="false"
                :label="t('web.branding.brand_color')"
                id="brand-color" />
              <!-- WCAG Contrast Warning -->
              <div
                v-if="showContrastWarning"
                class="flex items-center gap-1.5 rounded-md bg-amber-50 px-2 py-1 text-xs text-amber-700 dark:bg-amber-900/30 dark:text-amber-300"
                role="alert">
                <OIcon
                  collection="mdi"
                  name="alert"
                  class="size-4 shrink-0" />
                <span class="whitespace-nowrap">
                  {{ t('web.branding.low_contrast_warning') }}
                  <span class="font-medium">{{ contrastRatioDisplay }}:1</span>
                </span>
              </div>
            </div>

            <!-- UI Elements -->
            <div class="flex shrink-0 items-center gap-2">
              <CycleButton
                :model-value="modelValue.corner_style"
                @update:model-value="(value) => updateBrandSetting('corner_style', value as CornerStyleType)"
                :default-value="CornerStyle.ROUNDED"
                :options="cornerStyleOptions"
                :label="t('web.branding.corner_style')"
                :display-map="cornerStyleDisplayMap"
                :icon-map="cornerStyleIconMap" />
              <CycleButton
                :model-value="modelValue.font_family"
                @update:model-value="(value) => updateBrandSetting('font_family', value as FontFamilyType)"
                :default-value="FontFamily.SANS"
                :options="fontOptions"
                :label="t('web.branding.font_family')"
                :display-map="fontDisplayMap"
                :icon-map="fontIconMap" />
            </div>

            <!-- Instructions -->
            <div class="shrink-0">
              <slot name="instructions-buttons"></slot>
            </div>

            <!-- Language -->
            <div class="shrink-0">
              <slot name="language-button"></slot>
            </div>
          </div>

          <!-- Save Button -->
          <div class="ml-auto shrink-0">
            <!-- prettier-ignore-attribute class -->
            <button
              type="submit"
              :disabled="isDisabled"
              class="inline-flex h-11 min-w-[120px] shrink-0 items-center
                justify-center rounded-lg border
                border-transparent bg-brand-600
                px-4 text-base font-medium
                text-white
                shadow-sm
                transition-all
                duration-200 hover:bg-brand-700 focus:outline-none focus:ring-2
                focus:ring-brand-500 focus:ring-offset-2
                disabled:cursor-not-allowed disabled:opacity-50
                dark:focus:ring-brand-400 dark:focus:ring-offset-0
                sm:w-auto sm:text-sm">
              <OIcon
                v-if="isLoading"
                collection="mdi"
                name="loading"
                class="-ml-1 mr-2 size-4 animate-spin motion-reduce:animate-none" />
              <OIcon
                v-else
                collection="mdi"
                name="content-save"
                class="-ml-1 mr-2 size-4" />
              {{ buttonText }}
            </button>
          </div>
        </form>
      </div>
    </div>
  </div>
  <div
    v-else
    class="h-[68px]"></div>
</template>
