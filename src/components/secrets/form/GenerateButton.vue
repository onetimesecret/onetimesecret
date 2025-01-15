<script setup lang="ts">
  interface Props {
    disabled: boolean;
  }

  defineEmits<{
    (e: 'click'): void;
  }>();

  defineProps<Props>();
</script>

<template>
  <button type="submit"
          class="generate-btn group w-12 overflow-hidden whitespace-nowrap rounded bg-brand-100 px-4 py-2 pr-6 text-base font-medium text-white transition-all duration-200 ease-in-out hover:w-56 hover:bg-gray-600 disabled:cursor-not-allowed disabled:bg-gray-400 disabled:opacity-50 disabled:hover:w-12 disabled:hover:scale-100 disabled:hover:bg-gray-400 dark:bg-gray-700 dark:hover:bg-gray-600 dark:disabled:bg-gray-700 dark:disabled:hover:bg-gray-700"
          :disabled="disabled"
          :aria-label="$t('web.COMMON.button_generate_secret_short')"
          :title="disabled ? $t('web.COMMON.generate_password_disabled') : ''"
          @click.prevent="$emit('click')"
          name="kind"
          value="generate">
    <span class="transition-margin mr-0 inline-block opacity-80 duration-200 ease-in-out group-hover:mr-2"
          aria-hidden="true">🔑</span>
    <span class="opacity-0 transition-opacity duration-200 ease-in-out group-hover:opacity-100">
      {{ $t('web.COMMON.button_generate_secret_short') }}
    </span>
  </button>
</template>
