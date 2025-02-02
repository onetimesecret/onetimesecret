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

  import ColorPicker from '../common/ColorPicker.vue';
  import CycleButton from '../common/CycleButton.vue';

  const props = defineProps<{
    modelValue: BrandSettings;
    isLoading: boolean;
    isInitialized: boolean;
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

  const handleSubmit = () => emit('submit');
</script>

<template>
  <div v-if="!isLoading || isInitialized">
    <div
      class="border-b border-gray-200 bg-white/80 backdrop-blur-sm dark:border-gray-700 dark:bg-gray-800/80">
      <div class="mx-auto max-w-7xl px-4 py-3 sm:px-6 lg:px-8">
        <form
          @submit.prevent="handleSubmit"
          class="flex flex-wrap items-center gap-4">
          <!-- Color Picker -->
          <ColorPicker
            :model-value="modelValue.primary_color"
            @update:model-value="(value) => updateBrandSetting('primary_color', value)"
            name="brand[primary_color]"
            label="$t('brand-color')"
            id="brand-color" />

          <div class="inline-flex items-center gap-2">
            <!-- Corner Style -->
            <CycleButton
              :model-value="modelValue.corner_style"
              @update:model-value="(value) => updateBrandSetting('corner_style', value)"
              :default-value="CornerStyle.ROUNDED"
              :options="cornerStyleOptions"
              label="$t('corner-style')"
              :display-map="cornerStyleDisplayMap"
              :icon-map="cornerStyleIconMap" />

            <!-- Font Family -->
            <CycleButton
              :model-value="modelValue.font_family"
              @update:model-value="(value) => updateBrandSetting('font_family', value)"
              :default-value="FontFamily.SANS"
              :options="fontOptions"
              label="$t('font-family')"
              :display-map="fontDisplayMap"
              :icon-map="fontIconMap" />
          </div>

          <!-- Instructions Field -->

          <slot name="instructions-button"></slot>

          <!-- Spacer -->
          <div class="flex-1"></div>

          <!-- Save Button -->
          <button
            type="submit"
            :disabled="isLoading"
            class="inline-flex h-11 w-full items-center justify-center rounded-lg border border-transparent bg-brand-600 px-4 text-base font-medium text-white shadow-sm hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 sm:w-auto sm:text-sm">
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
            {{ isLoading ? 'Save' : 'Save' }}
          </button>
        </form>
      </div>
    </div>
  </div>
  <div
    v-else
    class="h-[68px]"></div>
</template>
