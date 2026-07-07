<!-- src/apps/workspace/components/dashboard/BrandSettingsBar.vue -->

/** eslint-disable tailwindcss/classnames-order */

<script setup lang="ts">
  import type { BrandSettings } from '@/schemas/shapes/v3/custom-domain';
  import ColorPicker from '@/shared/components/common/ColorPicker.vue';
  import CycleButton from '@/shared/components/common/CycleButton.vue';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import {
    borderRadiusDisplayMap,
    borderRadiusIconMap,
    borderRadiusOptions,
    brandPresets,
    CornerStyle,
    cornerStyleDisplayMap,
    cornerStyleIconMap,
    cornerStyleOptions,
    fontDisplayMap,
    FontFamily,
    fontIconMap,
    fontOptions,
    type BrandPreset,
    type CornerStyle as CornerStyleType,
    type FontFamily as FontFamilyType,
  } from '@/shared/utils/brand-helpers';
  import { checkBrandContrast } from '@/utils/brand-palette';
  import { computed } from 'vue';
  import { useI18n, Composer } from 'vue-i18n';

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

  // Theme presets (#3646): one click applies a designed token combination on
  // top of the current settings. Identity fields (logo, name, instructions)
  // are untouched — only the cosmetic token subset is merged.
  const presets = brandPresets;

  const applyPreset = (preset: BrandPreset) => {
    emit('update:modelValue', {
      ...props.modelValue,
      ...preset.tokens,
    });
  };

  // border_radius may be a preset string or a numeric px value; CycleButton
  // cycles the named presets, so coerce to a string for the control.
  const borderRadiusValue = computed<string | undefined>(() => {
    const radius = props.modelValue.border_radius;
    // Treat '' as unset (matches identityStore.cornerClass) so CycleButton
    // never receives a model-value that isn't one of its options.
    return radius == null || radius === '' ? undefined : String(radius);
  });

  // A preset is "active" only when EVERY token it sets matches the current
  // settings — otherwise aria-pressed and the selection border would lie when
  // the user has tweaked a color/font/radius away from the preset.
  const presetMatches = (preset: BrandPreset): boolean =>
    (Object.keys(preset.tokens) as (keyof BrandPreset['tokens'])[]).every((key) => {
      const want = preset.tokens[key];
      const have = props.modelValue[key];
      if (typeof want === 'string' && typeof have === 'string') {
        return want.toLowerCase() === have.toLowerCase();
      }
      return want === have;
    });

  const activePresetId = computed(() => presets.find(presetMatches)?.id ?? null);

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
          class="flex min-w-0 flex-wrap items-center gap-4">
          <!-- Left section - wrap in flex container -->
          <div class="flex min-w-0 shrink flex-wrap items-center gap-3">
            <!-- Color Pickers -->
            <div class="flex min-w-0 shrink flex-wrap items-center gap-3">
              <ColorPicker
                :model-value="modelValue.primary_color ?? undefined"
                @update:model-value="(value) => updateBrandSetting('primary_color', value)"
                name="brand[primary_color]"
                variant="sketch"
                :disable-alpha="false"
                :label="t('web.branding.brand_color')"
                id="brand-color" />
              <ColorPicker
                :model-value="modelValue.secondary_color ?? undefined"
                @update:model-value="(value) => updateBrandSetting('secondary_color', value)"
                name="brand[secondary_color]"
                variant="sketch"
                :disable-alpha="false"
                :label="t('web.branding.secondary_color')"
                id="brand-secondary-color" />
              <ColorPicker
                :model-value="modelValue.background_color ?? undefined"
                @update:model-value="(value) => updateBrandSetting('background_color', value)"
                name="brand[background_color]"
                variant="sketch"
                :disable-alpha="false"
                :label="t('web.branding.background_color')"
                id="brand-background-color" />
              <ColorPicker
                :model-value="modelValue.text_color ?? undefined"
                @update:model-value="(value) => updateBrandSetting('text_color', value)"
                name="brand[text_color]"
                variant="sketch"
                :disable-alpha="false"
                :label="t('web.branding.text_color')"
                id="brand-text-color" />
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
            <div class="flex shrink-0 flex-wrap items-center gap-2">
              <CycleButton
                :model-value="modelValue.corner_style"
                @update:model-value="(value) => updateBrandSetting('corner_style', value as CornerStyleType)"
                :default-value="CornerStyle.ROUNDED"
                :options="cornerStyleOptions"
                :label="t('web.branding.corner_style')"
                :display-map="cornerStyleDisplayMap"
                :icon-map="cornerStyleIconMap" />
              <!-- Border radius (#3646): richer replacement for corner_style -->
              <CycleButton
                :model-value="borderRadiusValue"
                @update:model-value="(value) => updateBrandSetting('border_radius', value)"
                default-value="md"
                :options="borderRadiusOptions"
                :label="t('web.branding.border_radius')"
                :display-map="borderRadiusDisplayMap"
                :icon-map="borderRadiusIconMap" />
              <CycleButton
                :model-value="modelValue.font_family"
                @update:model-value="(value) => updateBrandSetting('font_family', value as FontFamilyType)"
                :default-value="FontFamily.SANS"
                :options="fontOptions"
                :label="t('web.branding.font_family')"
                :display-map="fontDisplayMap"
                :icon-map="fontIconMap" />
              <!-- Heading font (#3646): optional separate font for headings -->
              <CycleButton
                :model-value="modelValue.heading_font ?? modelValue.font_family"
                @update:model-value="(value) => updateBrandSetting('heading_font', value as FontFamilyType)"
                :default-value="FontFamily.SANS"
                :options="fontOptions"
                :label="t('web.branding.heading_font')"
                :display-map="fontDisplayMap"
                :icon-map="fontIconMap" />
            </div>

            <!-- Theme presets (#3646): one-click designed token combinations -->
            <div
              class="flex shrink-0 items-center gap-1.5"
              role="group"
              :aria-label="t('web.branding.theme_presets')">
              <button
                v-for="preset in presets"
                :key="preset.id"
                type="button"
                @click="applyPreset(preset)"
                :title="preset.name"
                :aria-label="preset.name"
                :aria-pressed="activePresetId === preset.id"
                class="size-6 rounded-full border-2 shadow-sm transition-transform hover:scale-110 focus:ring-2 focus:ring-brand-500 focus:ring-offset-1 focus:outline-none"
                :class="activePresetId === preset.id
                  ? 'border-brand-500'
                  : 'border-white ring-1 ring-gray-200 dark:border-gray-700 dark:ring-gray-600'"
                :style="{
                  background: `linear-gradient(135deg, ${preset.tokens.primary_color} 0 50%, ${preset.tokens.secondary_color} 50% 100%)`,
                }"></button>
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
                duration-200 hover:bg-brand-700 focus:ring-2 focus:ring-brand-500
                focus:ring-offset-2 focus:outline-none
                disabled:cursor-not-allowed disabled:opacity-50
                sm:w-auto sm:text-sm
                dark:focus:ring-brand-400 dark:focus:ring-offset-0">
              <OIcon
                v-if="isLoading"
                collection="mdi"
                name="loading"
                class="mr-2 -ml-1 size-4 animate-spin motion-reduce:animate-none" />
              <OIcon
                v-else
                collection="mdi"
                name="content-save"
                class="mr-2 -ml-1 size-4" />
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
