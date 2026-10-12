<!-- src/apps/secret/components/form/MarkdownModeSwitch.vue -->

<script setup lang="ts">
  /**
   * Markdown Mode Switch (homepage form)
   *
   * The homepage form's presentation of display_type: a labeled switch with a
   * visible one-line hint, styled like the passphrase field's label and hint,
   * so a first-time visitor reads what it does without a tooltip. The
   * workspace dashboard shows the same field as a chip (MarkdownModeToggle)
   * in its options bar.
   */
  import { useId } from 'vue';
  import { useI18n } from 'vue-i18n';

  const props = withDefaults(
    defineProps<{
      /** Whether Markdown mode is on */
      modelValue: boolean;
      /** Disable while the form is submitting */
      disabled?: boolean;
    }>(),
    {
      disabled: false,
    }
  );

  const emit = defineEmits<{
    (e: 'update:modelValue', value: boolean): void;
  }>();

  const { t } = useI18n();

  const switchId = `markdown-switch-${useId()}`;
  const hintId = `${switchId}-hint`;

  const toggle = () => {
    if (props.disabled) return;
    emit('update:modelValue', !props.modelValue);
  };
</script>

<template>
  <div class="flex items-start gap-3">
    <!-- prettier-ignore-attribute class -->
    <button
      :id="switchId"
      type="button"
      role="switch"
      :aria-checked="modelValue"
      :aria-describedby="hintId"
      :disabled="disabled"
      :class="modelValue ? 'bg-brand-600 dark:bg-brand-500' : 'bg-gray-300 dark:bg-gray-600'"
      class="relative mt-0.5 inline-flex h-5 w-9 shrink-0 cursor-pointer rounded-full
        border-2 border-transparent transition-colors duration-200 ease-in-out
        focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 focus:outline-none
        disabled:cursor-not-allowed disabled:opacity-50 dark:focus:ring-offset-slate-900"
      data-testid="secret-markdown-toggle"
      @click="toggle">
      <span
        aria-hidden="true"
        :class="modelValue ? 'translate-x-4' : 'translate-x-0'"
        class="pointer-events-none inline-block size-4 rounded-full bg-white shadow ring-0
          transition duration-200 ease-in-out"></span>
    </button>
    <div>
      <label
        :for="switchId"
        class="block cursor-pointer font-brand text-sm text-gray-600 dark:text-gray-300">
        {{ t('web.secrets.markdown_mode_label') }}
      </label>
      <p
        :id="hintId"
        class="text-xs text-gray-500 dark:text-gray-400">
        {{ t('web.secrets.markdown_mode_hint') }}
      </p>
    </div>
  </div>
</template>
