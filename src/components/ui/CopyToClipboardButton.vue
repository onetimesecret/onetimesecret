<script setup lang="ts">
  import OIcon from '@/components/icons/OIcon.vue';

  defineProps<{
    isCopied: boolean;
  }>();
</script>

<template>
  <button
    @click="$emit('click')"
    class="p-1.5 rounded-md text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-200 hover:bg-gray-100 dark:hover:bg-gray-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brand-500 transition-colors duration-150"
    :class="{
      'text-green-500 dark:text-green-400': isCopied,
    }"
    :title="isCopied ? 'Copied!' : 'Copy to clipboard'">
    <OIcon
      collection="material-symbols"
      :name="isCopied ? 'check' : 'content-copy-outline'"
      class="w-4 h-4" />
  </button>
</template>
