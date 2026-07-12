<!-- src/apps/workspace/components/dashboard/brand/BrandEditor.vue -->

<script setup lang="ts">
  /**
   * Three-path brand editor. A path switcher over a two-column layout: the left
   * panel swaps by path (Simple = functional; Match / Advanced = "coming soon"
   * teasers) while the preview column on the right stays fixed.
   *
   * All paths are a view over the SAME `brandSettings` record — switching paths
   * never mutates it, so work carries over. Only Simple writes; the teasers are
   * inert. Nothing goes live until the parent saves.
   */
  import type { BrandSettings, ImageProps } from '@/schemas/shapes/v3/custom-domain';
  import { ref } from 'vue';
  import { Composer, useI18n } from 'vue-i18n';

  import BrandAdvancedTeaser from './BrandAdvancedTeaser.vue';
  import BrandMatchTeaser from './BrandMatchTeaser.vue';
  import BrandPathSwitcher from './BrandPathSwitcher.vue';
  import BrandPreviewColumn from './BrandPreviewColumn.vue';
  import ComingSoonPanel from './ComingSoonPanel.vue';
  import type { BrandPath } from './paths';
  import SimpleBrandPanel from './SimpleBrandPanel.vue';

  const { t } = useI18n();

  // Props are consumed directly in the template (modelValue, logoImage, …); no
  // script-side reference is needed, so defineProps isn't assigned to a var.
  withDefaults(
    defineProps<{
      modelValue: BrandSettings;
      logoImage?: ImageProps | null;
      // Return the persisted image / a truthy success flag (or undefined on a
      // wrapped-handler failure) — ImageUploadModal keys close/keep-open on it.
      onLogoUpload: (file: File) => Promise<unknown>;
      onLogoRemove: () => Promise<unknown>;
      previewI18n: Composer;
      secretIdentifier?: string;
    }>(),
    { secretIdentifier: 'abcd', logoImage: null }
  );

  const emit = defineEmits<{
    (e: 'update:modelValue', value: BrandSettings): void;
  }>();

  // Default to Simple — the quick happy path. Switching never touches
  // brandSettings; the panel is purely a view over the same record.
  const activePath = ref<BrandPath>('simple');
</script>

<template>
  <div>
    <BrandPathSwitcher v-model="activePath" />

    <div class="mt-4 grid grid-cols-1 items-start gap-4 lg:grid-cols-2">
      <!-- Left: path panel (swaps) -->
      <div>
        <SimpleBrandPanel
          v-if="activePath === 'simple'"
          :model-value="modelValue"
          :logo-image="logoImage"
          :on-logo-upload="onLogoUpload"
          :on-logo-remove="onLogoRemove"
          @update:model-value="(value) => emit('update:modelValue', value)" />

        <ComingSoonPanel
          v-else-if="activePath === 'match'"
          :title="t('web.branding.path_match')"
          :blurb="t('web.branding.coming_soon_match_blurb')">
          <BrandMatchTeaser />
        </ComingSoonPanel>

        <ComingSoonPanel
          v-else
          :title="t('web.branding.path_advanced')"
          :blurb="t('web.branding.coming_soon_advanced_blurb')">
          <BrandAdvancedTeaser />
        </ComingSoonPanel>

        <p class="mt-3 px-1 text-xs leading-relaxed text-gray-400">
          {{ t('web.branding.paths_carryover_hint') }}
        </p>
      </div>

      <!-- Right: preview (fixed) -->
      <BrandPreviewColumn
        :brand-settings="modelValue"
        :logo-image="logoImage"
        :on-logo-upload="onLogoUpload"
        :on-logo-remove="onLogoRemove"
        :secret-identifier="secretIdentifier"
        :preview-i18n="previewI18n" />
    </div>
  </div>
</template>
