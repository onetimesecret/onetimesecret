<!-- src/components/account/BrowserTypeToggle.vue -->

<script setup lang="ts">
defineProps<{
  modelValue: 'safari' | 'edge'
}>();

defineEmits<{
  (e: 'update:modelValue', value: 'safari' | 'edge'): void
}>();
</script>

<template>
  <div class="mb-4 flex items-center justify-center space-x-3">
    <button
      class="rounded-lg px-3 py-1.5 text-sm font-medium transition-colors"
      :class="[
        modelValue === 'safari'
          ? 'bg-brand-100 text-brand-700 dark:bg-brand-900 dark:text-brand-100'
          : 'text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200'
      ]"
      @click="$emit('update:modelValue', 'safari')"
      :aria-label="$t('switch-to-safari-preview')">
      {{ $t('safari') }}
    </button>

    <button
      class="rounded-lg px-3 py-1.5 text-sm font-medium transition-colors"
      :class="[
        modelValue === 'edge'
          ? 'bg-brand-100 text-brand-700 dark:bg-brand-900 dark:text-brand-100'
          : 'text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200'
      ]"
      @click="$emit('update:modelValue', 'edge')"
      :aria-label="$t('switch-to-edge-preview')">
      {{ $t('edge') }}
    </button>
  </div>
</template>
