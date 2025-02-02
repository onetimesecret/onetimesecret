<script setup lang="ts">
defineProps<{
  modelValue: boolean | null | undefined;  // Update type to allow nullable values
  disabled?: boolean;
}>();

const emit = defineEmits<{
  'update:modelValue': [value: boolean];
}>();
</script>

<template>
  <button
    type="button"
    :class="[
      'relative inline-flex h-6 w-11 shrink-0 cursor-pointer rounded-full border-2 border-transparent',
      'transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-brandcomp-500 focus:ring-offset-2',
      {
        'bg-brandcomp-600': modelValue,
        'bg-gray-200 dark:bg-gray-700': !modelValue,
        'cursor-not-allowed opacity-50': disabled
      }
    ]"
    :disabled="disabled"
    role="switch"
    :aria-checked="!!modelValue"
    @click="emit('update:modelValue', !modelValue)">
    <span class="sr-only">
      {{ modelValue ? 'Disable' : 'Enable' }} {{ $t('homepage-access') }}
    </span>
    <span
      :class="[
        'pointer-events-none inline-block size-5 rounded-full bg-white shadow ring-0',
        'transition duration-200 ease-in-out',
        modelValue ? 'translate-x-5' : 'translate-x-0'
      ]"></span>
    <!-- Loading spinner -->
    <span
      v-if="disabled"
      class="absolute inset-0 flex items-center justify-center">
      <svg
        class="size-4 animate-spin text-white"
        xmlns="http://www.w3.org/2000/svg"
        fill="none"
        viewBox="0 0 24 24">
        <circle
          class="opacity-25"
          cx="12"
          cy="12"
          r="10"
          stroke="currentColor"
          stroke-width="4"
        />
        <path
          class="opacity-75"
          fill="currentColor"
          d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
        />
      </svg>
    </span>
  </button>
</template>
