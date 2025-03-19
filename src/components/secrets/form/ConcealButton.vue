<script setup lang="ts">
  import { computed, ref } from 'vue';

  interface Props {
    disabled: boolean;
    withAsterisk: boolean;
    primaryColor: string;
    cornerClass: string;
  }

  defineEmits<{
    (e: 'click'): void; // Simplify - we don't need the event
  }>();

  const props = defineProps<Props>();

  const buttonColor = ref(props.primaryColor ?? '#dc4a22');

  // Compute aria attributes based on form validity
  const ariaDescription = computed(() => (props.disabled ? 'form_incomplete_description' : ''));
</script>

<template>
  <button
    type="submit"
    :style="{ backgroundColor: buttonColor }"
    :class="[cornerClass, 'group relative grow']"
    class="rounded px-4 py-2 text-xl font-bold text-white transition-all duration-200 ease-in-out hover:scale-105 hover:bg-orange-700 disabled:cursor-not-allowed disabled:opacity-50 disabled:hover:scale-100"
    :disabled="disabled"
    :aria-label="$t('web.COMMON.button_create_secret')"
    @click.prevent="$emit('click')"
    name="kind"
    value="conceal">
    {{ $t('web.COMMON.button_create_secret') }}<span v-if="withAsterisk">*</span>

    <!-- Screenreader only -->
    <span
      v-if="ariaDescription"
      class="sr-only"
      role="status">
      {{ ariaDescription }}
    </span>
  </button>
</template>
