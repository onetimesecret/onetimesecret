<!-- src/apps/secret/components/form/ConcealButton.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import { computed } from 'vue';

const { t } = useI18n();

  interface Props {
    disabled: boolean;
    withAsterisk: boolean;
    cornerClass: string;
  }

  defineEmits<{
    (e: 'click'): void;
  }>();

  const props = defineProps<Props>();

  // Compute aria attributes based on form validity
  const ariaDescription = computed(() => (props.disabled ? 'form_incomplete_description' : ''));
</script>

<template>
  <button
    type="submit"
    :class="[cornerClass, 'group relative grow']"
    class="bg-brand-500 hover:bg-brand-600 rounded px-4 py-2 text-xl font-bold text-white transition-all duration-200 ease-in-out hover:scale-105 disabled:cursor-not-allowed disabled:opacity-50 disabled:hover:scale-100"
    :disabled="disabled"
    :aria-label="t('web.COMMON.button_create_secret')"
    @click.prevent="$emit('click')"
    name="kind"
    value="conceal">
    {{ t('web.COMMON.button_create_secret') }}<span v-if="withAsterisk">*</span>

    <!-- Screenreader only -->
    <span
      v-if="ariaDescription"
      class="sr-only"
      role="status">
      {{ ariaDescription }}
    </span>
  </button>
</template>
