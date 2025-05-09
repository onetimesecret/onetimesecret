<!-- src/components/secrets/SecretLinkLine.vue -->

<script setup lang="ts">
import { ref } from 'vue';

const isCopied = ref(false);
const displayLink = ref('https://link');
const handleCopy = () => {
  navigator.clipboard.writeText(displayLink.value);
  isCopied.value = true;
  setTimeout(() => {
    isCopied.value = false;
  }, 2000);
};

</script>

<template>
  <div class="flex items-center w-full">
    <div class="relative flex-1 group/link">
      <div
        class="flex items-center p-2 pr-12 bg-gray-50 dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-md hover:border-gray-300 dark:hover:border-gray-600 transition-all">
        <OIcon
          collection="heroicons"
          name="link-solid"
          class="mr-2 size-4 text-blue-500 dark:text-blue-400" />
        <span class="text-sm text-gray-800 dark:text-gray-200 font-mono truncate">
          {{ displayLink }}
        </span>
      </div>
      <button
        @click="handleCopy"
        class="absolute right-0 top-0 bottom-0 p-2 px-3 rounded-r-md bg-gray-100 dark:bg-gray-700 border-l border-gray-200 dark:border-gray-600 hover:bg-gray-200 dark:hover:bg-gray-600 transition-all"
        :class="
          isCopied
            ? 'bg-emerald-50 dark:bg-emerald-800/30 text-emerald-600 dark:text-emerald-400'
            : ''
        ">
        <OIcon
          collection="material-symbols"
          :name="isCopied ? 'check' : 'content-copy-outline'"
          class="size-4" />
      </button>
    </div>
  </div>
</template>
