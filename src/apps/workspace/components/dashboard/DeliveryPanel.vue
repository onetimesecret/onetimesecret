<!-- src/apps/workspace/components/dashboard/DeliveryPanel.vue -->

<script setup lang="ts">
  /**
   * The "Delivery" companion tab: recipient-facing text + behaviour for this
   * domain, moved out of the brand editor. Two cards — default Language and
   * Reveal instructions (before/after). Both write the shared BrandSettings
   * record via v-model, so the page's single header Save persists them (the same
   * path the old inline "Recipient page content" section used — locale and the
   * two instruction fields all live on BrandSettings).
   *
   * No live preview here by design (the mockup shows none). The reveal
   * instructions DO render on the recipient page via SecretPreview on the Brand
   * tab — that surface is the preview.
   */
  import LanguageSelector from '@/apps/workspace/components/dashboard/LanguageSelector.vue';
  import type { BrandSettings } from '@/schemas/shapes/v3/custom-domain';
  import { Composer, useI18n } from 'vue-i18n';

  const { t } = useI18n();

  const props = defineProps<{
    modelValue: BrandSettings;
    /** Whether the deployment offers per-domain language (hides the whole card). */
    i18nEnabled: boolean;
    previewI18n: Composer;
  }>();

  const emit = defineEmits<{
    (e: 'update:modelValue', value: BrandSettings): void;
  }>();

  const update = <K extends keyof BrandSettings>(key: K, value: BrandSettings[K]) => {
    emit('update:modelValue', { ...props.modelValue, [key]: value });
  };

  // Instruction fields are free text and may be left blank — the recipient page
  // falls back to the built-in copy for the selected language.
  const onInstruction = (
    key: 'instructions_pre_reveal' | 'instructions_post_reveal',
    event: Event
  ) => {
    update(key, (event.target as HTMLInputElement).value as BrandSettings[typeof key]);
  };
</script>

<template>
  <div class="space-y-4">
    <!-- Language -->
    <div
      v-if="i18nEnabled"
      class="rounded-2xl border border-gray-200 bg-white p-[18px] dark:border-gray-700 dark:bg-gray-800">
      <h3 class="font-brand-slab text-base font-bold text-gray-900 dark:text-gray-100">
        {{ t('web.branding.delivery_language') }}
      </h3>
      <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
        {{ t('web.branding.delivery_language_hint') }}
      </p>
      <div class="mt-3">
        <LanguageSelector
          :model-value="modelValue.locale ?? ''"
          :preview-i18n="previewI18n"
          @update:model-value="(value) => update('locale', value as BrandSettings['locale'])" />
      </div>
    </div>

    <!-- Reveal instructions -->
    <div class="rounded-2xl border border-gray-200 bg-white p-[18px] dark:border-gray-700 dark:bg-gray-800">
      <h3 class="font-brand-slab text-base font-bold text-gray-900 dark:text-gray-100">
        {{ t('web.branding.delivery_reveal_instructions') }}
      </h3>
      <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
        {{ t('web.branding.delivery_reveal_instructions_hint') }}
      </p>
      <div class="mt-3 space-y-3">
        <label class="block">
          <span class="text-xs font-semibold text-gray-700 dark:text-gray-300">
            {{ t('web.branding.delivery_before_reveal') }}
          </span>
          <input
            type="text"
            maxlength="500"
            :value="modelValue.instructions_pre_reveal ?? ''"
            @input="(e) => onInstruction('instructions_pre_reveal', e)"
            :placeholder="t('web.branding.example_pre_reveal_instructions')"
            class="mt-1.5 h-11 w-full rounded-lg border border-gray-200 bg-white px-3 text-sm
              text-gray-900 shadow-sm focus:border-brand-500 focus:ring-1 focus:ring-brand-500
              focus:outline-none dark:border-gray-600 dark:bg-gray-900 dark:text-gray-100" />
        </label>
        <label class="block">
          <span class="text-xs font-semibold text-gray-700 dark:text-gray-300">
            {{ t('web.branding.delivery_after_reveal') }}
          </span>
          <input
            type="text"
            maxlength="500"
            :value="modelValue.instructions_post_reveal ?? ''"
            @input="(e) => onInstruction('instructions_post_reveal', e)"
            :placeholder="t('web.branding.example_post_reveal_instructions')"
            class="mt-1.5 h-11 w-full rounded-lg border border-gray-200 bg-white px-3 text-sm
              text-gray-900 shadow-sm focus:border-brand-500 focus:ring-1 focus:ring-brand-500
              focus:outline-none dark:border-gray-600 dark:bg-gray-900 dark:text-gray-100" />
        </label>
      </div>
    </div>
  </div>
</template>
