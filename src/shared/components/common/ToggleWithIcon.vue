<!-- src/shared/components/common/ToggleWithIcon.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';

const { t } = useI18n();

  interface Props {
    enabled: boolean;
    disabled: boolean;
    ariaDescribedby?: string;
    srLabel?: string;
  }

  const props = defineProps<Props>();

  const emit = defineEmits<{
    (e: 'update:enabled', value: boolean): void
  }>();
</script>

<!--
  Plain `role="switch"` button rather than HeadlessUI's <Switch>: HeadlessUI
  sets aria-describedby from its SwitchGroup/Description context (undefined when
  unwrapped), which stomps a fallthrough/bound aria-describedby. Consumers here
  reference a parent-owned hint <p id="...">, so we control the attrs directly.
  A native button toggles on Space/Enter via click, so no extra key handling.
-->
<template>
  <button
    type="button"
    role="switch"
    :aria-checked="props.enabled"
    :aria-describedby="ariaDescribedby"
    :disabled="disabled"
    @click="emit('update:enabled', !props.enabled)"
    :class="[
      props.enabled ? 'bg-brand-600' : 'bg-gray-200',
      disabled ? 'cursor-not-allowed opacity-50' : 'cursor-pointer',
      'relative inline-flex h-6 w-11 shrink-0 rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2'
    ]">
    <span class="sr-only">{{ srLabel ?? t('web.branding.use_setting') }}</span>
    <span
      :class="[
        enabled ? 'translate-x-5' : 'translate-x-0',
        'pointer-events-none relative inline-block size-5 rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out',
      ]">
      <span
        :class="[
          enabled ? 'opacity-0 duration-100 ease-out' : 'opacity-100 duration-200 ease-in',
          'absolute inset-0 flex size-full items-center justify-center transition-opacity',
        ]"
        aria-hidden="true">
        <svg
          class="size-3 text-gray-400"
          fill="none"
          viewBox="0 0 12 12">
          <path
            d="M4 8l2-2m0 0l2-2M6 6L4 4m2 2l2 2"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round" />
        </svg>
      </span>
      <span
        :class="[
          enabled ? 'opacity-100 duration-200 ease-in' : 'opacity-0 duration-100 ease-out',
          'absolute inset-0 flex size-full items-center justify-center transition-opacity',
        ]"
        aria-hidden="true">
        <svg
          class="size-3 text-brand-600"
          fill="currentColor"
          viewBox="0 0 12 12">
          <path
            d="M3.707 5.293a1 1 0 00-1.414 1.414l1.414-1.414zM5 8l-.707.707a1 1 0 001.414 0L5 8zm4.707-3.293a1 1 0 00-1.414-1.414l1.414 1.414zm-7.414 2l2 2 1.414-1.414-2-2-1.414 1.414zm3.414 2l4-4-1.414-1.414-4 4 1.414 1.414z" />
        </svg>
      </span>
    </span>
  </button>
</template>
