<script setup lang="ts">
interface Props {
  disabled: boolean;
}

defineProps<Props>();
</script>

<template>

  <button type="submit"
          class="generate-btn text-base py-2 px-4 pr-6 rounded
           bg-brand-100 dark:bg-gray-700
           hover:bg-gray-600 dark:hover:bg-gray-600
           text-white font-medium transition-all duration-300 ease-in-out transform
           w-12 hover:w-56 overflow-hidden whitespace-nowrap group
           disabled:opacity-50 disabled:cursor-not-allowed
           disabled:bg-gray-400 dark:disabled:bg-gray-700
           disabled:hover:bg-gray-400 dark:disabled:hover:bg-gray-700
           disabled:hover:scale-100 disabled:hover:w-12"
          :disabled="disabled"
          :aria-label="$t('web.COMMON.button_generate_secret_short')"
          :title="disabled ? $t('web.COMMON.generate_password_disabled') : ''"
          name="kind"
          value="generate">
    <span class="inline-block transition-margin duration-300 ease-in-out mr-0 group-hover:mr-2 opacity-80"
          aria-hidden="true">🔑</span>
    <span class="opacity-0 transition-opacity duration-300 ease-in-out group-hover:opacity-100">
      {{ $t('web.COMMON.button_generate_secret_short') }}
    </span>
  </button>
</template>
