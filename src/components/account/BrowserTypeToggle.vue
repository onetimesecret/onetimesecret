<!-- src/components/account/BrowserTypeToggle.vue -->
<template>
  <div class="flex items-center justify-center space-x-3 mb-4">
    <button
      class="px-3 py-1.5 rounded-lg text-sm font-medium transition-colors"
      :class="[
        modelValue === 'safari'
          ? 'bg-brand-100 text-brand-700 dark:bg-brand-900 dark:text-brand-100'
          : 'text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200'
      ]"
      @click="$emit('update:modelValue', 'safari')"
      aria-label="Switch to Safari preview"
    >
      Safari
    </button>

    <button
      class="px-3 py-1.5 rounded-lg text-sm font-medium transition-colors"
      :class="[
        modelValue === 'edge'
          ? 'bg-brand-100 text-brand-700 dark:bg-brand-900 dark:text-brand-100'
          : 'text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200'
      ]"
      @click="$emit('update:modelValue', 'edge')"
      aria-label="Switch to Edge preview"
    >
      Edge
    </button>
  </div>
</template>

<script setup lang="ts">
defineProps<{
  modelValue: 'safari' | 'edge'
}>();

defineEmits<{
  (e: 'update:modelValue', value: 'safari' | 'edge'): void
}>();
</script>
