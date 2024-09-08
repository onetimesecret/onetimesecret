<script setup lang="ts">
interface Props {
  disabled: boolean;
  withAsterisk: boolean;
}

defineProps<Props>();
</script>

<template>
  <button type="submit"
          class="text-xl flex-grow py-2 px-4 rounded
           bg-orange-600 hover:bg-orange-700 text-white
           font-bold disabled:opacity-50 disabled:cursor-not-allowed
           duration-300 ease-in-out transform hover:scale-105 disabled:hover:scale-100"
          :disabled="disabled"
          :aria-label="$t('web.COMMON.button_create_secret')"
          name="kind"
          value="share">
    {{ $t('web.COMMON.button_create_secret') }}<span v-if="withAsterisk">*</span>
  </button>
</template>
