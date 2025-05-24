<!-- src/components/icons/logos/DefaultLogo.vue -->

<script setup lang="ts">
  import { computed } from 'vue';
  import { useI18n } from 'vue-i18n';
  import MonotoneJapaneseSecretButton from './MonotoneJapaneseSecretButton.vue';

import { type LogoConfig } from '@/types/ui/layouts';

  /**
   * Props for controlling logo appearance
   */
  const props = withDefaults(
    defineProps<LogoConfig>(),
    {
      size: 64,
      mode: 'light',
      href: '/',
    }
  );

  const { t } = useI18n();

  const ariaLabel = computed(() => props.ariaLabel || t('one-time-secret-literal'));

  const textColor = computed(() => (props.mode === 'dark' ? 'text-white' : 'text-gray-800'));

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
    class="flex items-center gap-3"
    :aria-label="ariaLabel">
    <a
      :href="props.href"
      :alt="ariaLabel"
      class="flex items-center gap-3">
      <MonotoneJapaneseSecretButton
        :size="svgSize"
        :aria-label="ariaLabel"
        class="shrink-0" />
      <div
        v-if="props.showCompanyName && props.companyName"
        class="flex flex-col">
        <span :class="[textSize, textColor, 'font-bold leading-tight']">
          {{ props.companyName }}
        </span>
      </div>
    </a>
  </div>
</template>
