<!-- src/shared/components/logos/LegacyLogo.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
  import { storeToRefs } from 'pinia';
  import OnetimeSecretIcon from '@/shared/components/icons/OnetimeSecretIcon.vue';
import { type LogoConfig } from '@/types/ui/layouts';
  import { computed } from 'vue';

  /**
   * Props for controlling logo appearance
   */
  const props = withDefaults(
    defineProps<LogoConfig & { isColonelArea?: boolean }>(),
    {
      size: 64,
      href: '/',
      isColonelArea: false,
    }
  );

  const { t } = useI18n();
  const { brand_product_name } = storeToRefs(useBootstrapStore());

  const ariaLabel = computed(() => props.ariaLabel || t('web.homepage.one_time_secret_literal', { product_name: brand_product_name.value }));

  const svgSize = computed(() =>
    typeof props.size === 'number' && props.size > 0 ? props.size : 64
  );

  const textSize = computed(() => {
    if (props.size <= 32) return 'text-sm';
    if (props.size <= 48) return 'text-base';
    if (props.size <= 64) return 'text-lg';
    return 'text-xl';
  });
</script>

<template>
  <div
    class="flex items-center gap-3 font-brand"
    :aria-label="ariaLabel">
    <a
      :href="props.href"
      :aria-label="ariaLabel"
      class="flex items-center gap-3">
      <!-- Logo Mark -->
      <OnetimeSecretIcon
        :size="svgSize"
        :aria-label="ariaLabel"
        :title="t('web.branding.default_logo_icon')"
        class="shrink-0 text-brand-500 dark:text-white" />
      <!-- Text Mark -->
      <!-- Company Name -->
      <div
        v-if="props.showSiteName && props.siteName"
        class="relative flex flex-col">
        <div :class="[textSize, 'font-brand font-bold leading-tight']">
          {{ props.siteName }}
        </div>
        <!-- Colonel Overlay -->
        <div
          v-if="props.isColonelArea"
          class="pointer-events-none absolute inset-0 flex items-center justify-center">
          <span
            class="-rotate-6 transform-gpu rounded-lg bg-brand-500 px-2 py-1 text-sm font-bold tracking-widest text-white shadow-lg dark:bg-brand-600/90"
            style="transform-origin: center;">
            Colonels Only
          </span>
        </div>
        <!-- Tagline -->
        <div
          class="text-xs text-gray-500 transition-colors dark:text-gray-400"
          aria-hidden="true">
          {{ props.tagLine || t('web.COMMON.tagline') }}
        </div>
      </div>
    </a>
  </div>
</template>
