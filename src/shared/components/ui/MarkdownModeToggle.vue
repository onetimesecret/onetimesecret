<!-- src/shared/components/ui/MarkdownModeToggle.vue -->

<script setup lang="ts">
  /**
   * Markdown Mode Toggle
   *
   * A chip-styled switch that turns Markdown formatting on or off for the
   * secret being written. The position is a form setting (display_type on
   * the request), remembered across visits by the caller like the TTL.
   */
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useI18n } from 'vue-i18n';

  const props = withDefaults(
    defineProps<{
      /** Whether Markdown mode is on */
      modelValue: boolean;
      /** Disable while the form is submitting */
      disabled?: boolean;
      /** Brand corner class for the chip */
      cornerClass?: string;
    }>(),
    {
      disabled: false,
      cornerClass: 'rounded-md',
    }
  );

  const emit = defineEmits<{
    (e: 'update:modelValue', value: boolean): void;
  }>();

  const { t } = useI18n();

  const toggle = () => {
    if (props.disabled) return;
    emit('update:modelValue', !props.modelValue);
  };

  const ACTIVE_CLASS =
    'bg-brand-50 text-brand-700 ring-brand-600/30 hover:bg-brand-100 ' +
    'dark:bg-brand-900/30 dark:text-brand-300 dark:ring-brand-400/30 dark:hover:bg-brand-900/50';
  const INACTIVE_CLASS =
    'bg-white/80 text-gray-600 ring-gray-300/70 hover:bg-gray-50 hover:text-gray-800 ' +
    'dark:bg-slate-800/80 dark:text-gray-300 dark:ring-gray-600/70 dark:hover:bg-slate-800 ' +
    'dark:hover:text-gray-100';
</script>

<template>
  <!-- prettier-ignore-attribute class -->
  <button
    type="button"
    role="switch"
    :aria-checked="modelValue"
    :disabled="disabled"
    :title="t('web.secrets.markdown_mode_description')"
    :class="[cornerClass, modelValue ? ACTIVE_CLASS : INACTIVE_CLASS]"
    class="inline-flex items-center gap-1.5 px-2.5 py-1 text-xs font-medium ring-1 transition-all
      ring-inset focus:ring-2 focus:ring-brand-500 focus:outline-none
      disabled:cursor-not-allowed disabled:opacity-50"
    data-testid="secret-markdown-toggle"
    @click="toggle">
    <OIcon
      collection="mdi"
      name="language-markdown"
      class="size-4"
      aria-hidden="true" />
    <span>{{ t('web.secrets.markdown_mode') }}</span>
    <span class="sr-only">{{
      modelValue ? t('web.COMMON.enabled') : t('web.COMMON.disabled')
    }}</span>
  </button>
</template>
