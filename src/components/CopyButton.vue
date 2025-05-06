<!-- src/components/CopyButton.vue -->

<script setup lang="ts">
  import OIcon from '@/components/icons/OIcon.vue';
  import { ref, computed, onBeforeUnmount } from 'vue';
  import { useI18n } from 'vue-i18n';
  const { t } = useI18n();

  interface Props {
    text: string;
    interval?: number;
    tooltip?: string | undefined;
  }

  const props = withDefaults(defineProps<Props>(), {
    text: '',
    interval: 2000,
    tooltip: undefined,
  });

  const copied = ref(false);
  const showTooltip = ref(false);
  const ariaLabel = copied.value ? t('web.STATUS.copied') : t('web.LABELS.copy_to_clipboard');
  const tooltipText = computed(() => props.tooltip ? props.tooltip : ariaLabel);

  let tooltipTimeout: number | null = null;

  const copyToClipboard = () => {
    navigator.clipboard.writeText(props.text).then(() => {
      copied.value = true;
      showTooltip.value = true;

      if (tooltipTimeout) clearTimeout(tooltipTimeout);

      setTimeout(() => {
        copied.value = false;
        showTooltip.value = false;
      }, props.interval);
    });
  };

  onBeforeUnmount(() => {
    if (tooltipTimeout) clearTimeout(tooltipTimeout);
  });
</script>

<template>
  <div class="relative inline-block">
    <button
      @click="copyToClipboard"
      @mouseenter="showTooltip = true"
      @mouseleave="showTooltip = false"
      class="text-gray-600 hover:text-gray-900 focus:outline-none dark:text-gray-400 dark:hover:text-white"
      :aria-label="ariaLabel">
      <OIcon
        collection="material-symbols"
        :name="copied ? 'check' : 'content-copy-outline'"
        class="size-5" />
    </button>
    <!-- prettier-ignore-attribute class -->
    <div
      v-if="showTooltip"
      class="absolute bottom-1/2 right-full mr-2 z-50 flex items-center gap-2 rounded-md
        bg-slate-900 px-3.5 py-2 text-sm text-white shadow-lg transition-all duration-300
        dark:bg-slate-700"
      :class="{
        'translate-x-1 opacity-0': !showTooltip,
        'translate-x-0 opacity-100': showTooltip,
      }">
      <OIcon
        collection="material-symbols"
        name="check-circle-outline"
        class="size-4 text-green-400" />
      {{ tooltipText }}
    </div>
  </div>
</template>
