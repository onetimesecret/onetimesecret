
<template>
  <button
    type="submit"
    class="grow rounded bg-orange-600 px-4 py-2
           text-xl font-bold text-white
           transition-all duration-200 ease-in-out
           hover:scale-105 hover:bg-orange-700 disabled:cursor-not-allowed disabled:opacity-50 disabled:hover:scale-100"
    :disabled="disabled"
    :aria-label="$t('web.COMMON.button_create_secret')"
    name="kind"
    value="share"
  >
    {{ $t('web.COMMON.button_create_secret') }}<span v-if="withAsterisk">*</span>
  </button>
</template>

<script setup lang="ts">
interface Props {
  disabled: boolean;
  withAsterisk: boolean;
}

defineProps<Props>();
</script>
