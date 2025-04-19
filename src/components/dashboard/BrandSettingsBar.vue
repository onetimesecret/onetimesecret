/** eslint-disable tailwindcss/classnames-order */
<!-- src/components/dashboard/BrandSettingsBar.vue -->

<script setup lang="ts">
  import OIcon from '@/components/icons/OIcon.vue';
  import type { BrandSettings } from '@/schemas/models';
  import {
    CornerStyle,
    cornerStyleDisplayMap,
    cornerStyleIconMap,
    cornerStyleOptions,
    fontDisplayMap,
    FontFamily,
    fontIconMap,
    fontOptions,
  } from '@/schemas/models/domain/brand';
  import { computed } from 'vue';
  import { Composer, useI18n } from 'vue-i18n';

  import ColorPicker from '../common/ColorPicker.vue';
  import CycleButton from '../common/CycleButton.vue';

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

  const isDisabled = computed(() => {
    return props.isLoading || !props.hasUnsavedChanges;
  });

  const buttonText = computed(() => {
    return props.isLoading ? t('web.LABELS.saving') : t('web.LABELS.save');
  });
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
                :model-value="modelValue.primary_color"
                @update:model-value="(value) => updateBrandSetting('primary_color', value)"
                name="brand[primary_color]"
                :label="t('brand-color')"
                id="brand-color" />
            </div>

            <!-- UI Elements -->
            <div class="flex shrink-0 items-center gap-2">
              <OIcon collection="" name="tabler-border-corner-rounded" />
              <CycleButton
                :model-value="modelValue.corner_style"
                @update:model-value="(value) => updateBrandSetting('corner_style', value)"
                :default-value="CornerStyle.ROUNDED"
                :options="cornerStyleOptions"
                :label="t('corner-style')"
                :display-map="cornerStyleDisplayMap"
                :icon-map="cornerStyleIconMap"
              />
              <CycleButton
                :model-value="modelValue.font_family"
                @update:model-value="(value) => updateBrandSetting('font_family', value)"
                :default-value="FontFamily.SANS"
                :options="fontOptions"
                :label="t('font-family')"
                :display-map="fontDisplayMap"
                :icon-map="fontIconMap"
              />
            </div>

            <!-- Instructions -->
            <div class="shrink-0">
              <slot name="instructions-button"></slot>
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
              class="inline-flex h-11 shrink-0 items-center justify-center
                       rounded-lg border border-transparent
                       bg-brand-600 px-4
                       text-base font-medium text-white
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
                class="-ml-1 mr-2 size-4 animate-spin" />
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
