<!-- src/apps/workspace/components/dashboard/brand/BrandHomepageTiles.vue -->

<script setup lang="ts">
  /**
   * The two small homepage previews below the recipient preview: the branded
   * "enabled" homepage (visitors can create secrets) and the neutral "disabled"
   * homepage (delivery-only). Both render the EDITED domain's tokens via inline
   * styles derived from `brandSettings` — never the operator's injected <html>
   * theme — so the tiles stay truthful to what the admin is editing.
   *
   * The homepage toggle itself lives on the domain's delivery/config surface;
   * these tiles just illustrate both states so the admin sees what it governs.
   */
  import type { BrandSettings, ImageProps } from '@/schemas/shapes/v3/custom-domain';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { borderRadiusToCss } from '@/shared/utils/brand-helpers';
  import { computed } from 'vue';
  import { useI18n } from 'vue-i18n';

  const { t } = useI18n();

  const props = defineProps<{
    brandSettings: BrandSettings;
    logoImage?: ImageProps | null;
  }>();

  const primary = computed(() => props.brandSettings.primary_color ?? 'var(--color-brand-500)');
  const radius = computed(() => borderRadiusToCss(props.brandSettings.border_radius) ?? '0.5rem');
  const btnTextColor = computed(() =>
    (props.brandSettings.button_text_light ?? true) ? '#ffffff' : '#111827'
  );

  // Solid primary logo mark. (No secondary_color accent: it has no live consumer
  // yet, so the preview mustn't imply one — see SimpleBrandPanel.)
  const logoStyle = computed(() => ({
    borderRadius: radius.value,
    background: primary.value,
  }));

  const isValidLogo = computed(
    () => !!props.logoImage?.encoded && !!props.logoImage?.content_type
  );
  const logoSrc = computed(() =>
    isValidLogo.value
      ? `data:${props.logoImage?.content_type};base64,${props.logoImage?.encoded}`
      : ''
  );
</script>

<template>
  <div class="grid grid-cols-2 gap-2.5">
    <!-- Homepage · enabled (branded) -->
    <div class="overflow-hidden rounded-xl border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
      <div
        class="border-b border-gray-200 bg-gray-100 px-3 py-2 text-[10.5px] font-semibold
          tracking-wide text-gray-500 uppercase dark:border-gray-700 dark:bg-gray-700 dark:text-gray-300">
        {{ t('web.branding.preview_homepage_enabled') }}
      </div>
      <div class="p-3">
        <div class="flex items-center gap-2">
          <span
            class="flex size-6 shrink-0 items-center justify-center overflow-hidden text-[8px] font-extrabold text-white"
            :style="logoStyle">
            <img
              v-if="isValidLogo"
              :src="logoSrc"
              alt=""
              class="size-full object-contain" />
            <OIcon
              v-else
              collection="mdi"
              name="shield-lock"
              class="size-3.5" />
          </span>
          <span class="text-xs font-semibold text-gray-800 dark:text-gray-200">
            {{ t('web.branding.tile_share_secret') }}
          </span>
        </div>
        <div
          class="mt-2.5 h-8 bg-gray-100 dark:bg-gray-700"
          :style="{ borderRadius: radius }"></div>
        <div
          class="mt-2 py-1.5 text-center text-[11px] font-medium"
          :style="{ borderRadius: radius, background: primary, color: btnTextColor }">
          {{ t('web.branding.tile_create_link') }}
        </div>
      </div>
    </div>

    <!-- Homepage · disabled (neutral, delivery-only) -->
    <div class="overflow-hidden rounded-xl border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
      <div
        class="border-b border-gray-200 bg-gray-100 px-3 py-2 text-[10.5px] font-semibold
          tracking-wide text-gray-500 uppercase dark:border-gray-700 dark:bg-gray-700 dark:text-gray-300">
        {{ t('web.branding.preview_homepage_disabled') }}
      </div>
      <div class="flex min-h-[92px] flex-col items-center justify-center gap-1.5 bg-gray-50 p-3 dark:bg-gray-900">
        <OIcon
          collection="mdi"
          name="lock-outline"
          class="size-4 text-gray-400" />
        <span class="text-center text-[11px] font-medium text-gray-500 dark:text-gray-400">
          {{ t('web.branding.tile_delivery_only') }}
        </span>
        <span class="text-center text-[10px] text-gray-400">
          {{ t('web.branding.tile_no_create') }}
        </span>
      </div>
    </div>
  </div>
</template>
