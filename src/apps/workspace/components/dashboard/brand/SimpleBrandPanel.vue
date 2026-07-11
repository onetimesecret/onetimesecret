<!-- src/apps/workspace/components/dashboard/brand/SimpleBrandPanel.vue -->

<script setup lang="ts">
  /**
   * The functional "Simple" path: the quick happy path for branding a domain.
   * Logo, brand color, corners, and body font — all inline. Color/corners/font
   * write the shared BrandSettings record via v-model, so switching paths never
   * loses work. (Heading font is not exposed here; the recipient render falls
   * back to the body font, and a separate heading choice returns with the
   * Advanced path.)
   *
   * Logo is the exception: BrandLogoField uploads/removes immediately via the
   * useBranding callbacks (its own API endpoint), not through v-model/Save. Same
   * behavior as clicking the preview image — this just surfaces it in the form.
   *
   * secondary_color is intentionally NOT exposed here: it has no live consumer
   * yet (useBrandTheme injects a `--color-brand2-*` scale onto <html>, but no
   * view renders it — the #3646 "last mile"), so editing it would change nothing
   * a recipient sees. It returns to the UI when a branded surface actually paints
   * with it. background_color/text_color are deferred for the same reason.
   *
   * Corners write `border_radius` (the field the recipient preview actually
   * honors via the locally-scoped `--radius-brand`); `corner_style` is left
   * untouched since `border_radius` supersedes it (identityStore.cornerClass).
   */
  import type { BrandSettings, ImageProps } from '@/schemas/shapes/v3/custom-domain';
  import ColorPicker from '@/shared/components/common/ColorPicker.vue';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import {
    borderRadiusDisplayMap,
    FontFamily,
    fontDisplayMap,
    fontFamilyStacks,
    fontOptions,
    type FontFamily as FontFamilyType,
  } from '@/shared/utils/brand-helpers';
  import { checkBrandContrast } from '@/utils/brand-palette';
  import { computed } from 'vue';
  import { useI18n } from 'vue-i18n';

  import BrandLogoField from './BrandLogoField.vue';

  const { t } = useI18n();

  const props = defineProps<{
    modelValue: BrandSettings;
    logoImage?: ImageProps | null;
    onLogoUpload: (file: File) => Promise<void>;
    onLogoRemove: () => Promise<void>;
  }>();

  const emit = defineEmits<{
    (e: 'update:modelValue', value: BrandSettings): void;
  }>();

  const updateBrandSetting = <K extends keyof BrandSettings>(key: K, value: BrandSettings[K]) => {
    emit('update:modelValue', { ...props.modelValue, [key]: value });
  };

  const onFontChange = (event: Event) => {
    const value = (event.target as HTMLSelectElement).value as FontFamilyType;
    updateBrandSetting('font_family', value as BrandSettings['font_family']);
  };

  // Corner options map to border_radius presets (Square→none, Rounded→md,
  // Pill→full). Labels reuse borderRadiusDisplayMap (hardcoded English). Each
  // shows a single-corner tabler glyph (cornerStyleIconMap) rather than a full
  // box, which reads more clearly as "corner treatment".
  const cornerOptions = [
    { id: 'none', label: borderRadiusDisplayMap.none, icon: 'tabler-border-corner-square' },
    { id: 'md', label: borderRadiusDisplayMap.md, icon: 'tabler-border-corner-rounded' },
    { id: 'full', label: borderRadiusDisplayMap.full, icon: 'tabler-border-corner-pill' },
  ] as const;

  const activeCorner = computed(() => {
    const radius = props.modelValue.border_radius;
    return radius == null || radius === '' ? null : String(radius);
  });

  // Primary legibility warning. Note: checkBrandContrast reports max(vs-white,
  // vs-black) — the auto-picked button-text contrast — whose minimum across all
  // hues is ~4.58, just above the 4.5 AA threshold, so passesAA is effectively
  // always true and this warning is vestigial (kept as a safety net if the
  // threshold ever tightens). Display only — it never blocks the save (WCAG
  // contrast is not gated on save).
  const contrastCheck = computed(() => checkBrandContrast(props.modelValue.primary_color ?? ''));
  const showContrastWarning = computed(() => !contrastCheck.value.passesAA);
  const contrastRatioDisplay = computed(() => contrastCheck.value.ratio.toFixed(1));

  // Body font falls back to Sans, matching the recipient render.
  const bodyFont = computed(() => props.modelValue.font_family ?? FontFamily.SANS);
</script>

<template>
  <div class="rounded-2xl border border-gray-200 bg-white p-[18px] dark:border-gray-700 dark:bg-gray-800">
    <div class="flex items-baseline gap-2">
      <h2 class="font-brand-slab text-base font-bold text-gray-900 dark:text-gray-100">
        {{ t('web.branding.your_brand') }}
      </h2>
      <span class="text-xs text-gray-500 dark:text-gray-400">
        {{ t('web.branding.your_brand_subtitle') }}
      </span>
    </div>

    <!-- Logo. Upload/Remove apply immediately (not on Save) — see BrandLogoField. -->
    <div class="mt-3.5">
      <BrandLogoField
        :logo-image="logoImage"
        :on-logo-upload="onLogoUpload"
        :on-logo-remove="onLogoRemove" />
    </div>

    <!-- Brand color -->
    <div class="mt-3.5">
      <div class="text-xs font-semibold text-gray-700 dark:text-gray-300">
        {{ t('web.branding.brand_color') }}
      </div>
      <div class="mt-1.5 flex items-center gap-2.5">
        <ColorPicker
          :model-value="modelValue.primary_color ?? undefined"
          @update:model-value="(value) => updateBrandSetting('primary_color', value)"
          name="brand[primary_color]"
          variant="sketch"
          disable-alpha
          :label="t('web.branding.brand_color')"
          id="simple-brand-color" />
      </div>
      <!-- WCAG contrast warning (primary vs white) — advisory only, never blocks save -->
      <div
        v-if="showContrastWarning"
        class="mt-2 flex w-fit items-center gap-1.5 rounded-md bg-amber-50 px-2 py-1 text-xs
          text-amber-700 dark:bg-amber-900/30 dark:text-amber-300"
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

    <!-- Corners -->
    <div class="mt-3.5">
      <div class="text-xs font-semibold text-gray-700 dark:text-gray-300">
        {{ t('web.branding.corners') }}
      </div>
      <div
        class="mt-1.5 grid grid-cols-3 gap-2"
        role="group"
        :aria-label="t('web.branding.corners')">
        <button
          v-for="corner in cornerOptions"
          :key="corner.id"
          type="button"
          @click="updateBrandSetting('border_radius', corner.id)"
          :aria-pressed="activeCorner === corner.id"
          class="flex items-center gap-2 rounded-lg border px-2.5 py-2 transition-colors
            hover:border-gray-400"
          :class="activeCorner === corner.id
            ? 'border-brand-500 border-2'
            : 'border-gray-200 dark:border-gray-600'">
          <OIcon
            collection=""
            :name="corner.icon"
            class="size-5 shrink-0 text-gray-600 dark:text-gray-300"
            aria-hidden="true" />
          <span class="text-xs font-semibold text-gray-700 dark:text-gray-300">{{ corner.label }}</span>
        </button>
      </div>
    </div>

    <!-- Font -->
    <div class="mt-3.5">
      <label class="block">
        <span class="text-xs font-semibold text-gray-700 dark:text-gray-300">
          {{ t('web.branding.font_family') }}
        </span>
        <select
          :value="bodyFont"
          @change="onFontChange"
          class="mt-1.5 h-11 w-full rounded-lg border border-gray-200 bg-white px-3 text-sm
            text-gray-900 shadow-sm focus:border-brand-500 focus:ring-1 focus:ring-brand-500
            focus:outline-none dark:border-gray-600 dark:bg-gray-900 dark:text-gray-100">
          <option
            v-for="font in fontOptions"
            :key="`body-${font}`"
            :value="font"
            :style="{ fontFamily: fontFamilyStacks[font] }">
            {{ fontDisplayMap[font] }}
          </option>
        </select>
      </label>
    </div>
  </div>
</template>
