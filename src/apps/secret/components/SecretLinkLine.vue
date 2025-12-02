<!-- src/apps/secret/components/SecretLinkLine.vue -->

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
  <div class="flex w-full items-center">
    <div class="group/link relative flex-1">
      <div
        class="flex items-center rounded-md border border-gray-200 bg-gray-50 p-2 pr-12 transition-all hover:border-gray-300 dark:border-gray-700 dark:bg-gray-800 dark:hover:border-gray-600">
        <OIcon
          collection="heroicons"
          name="link-solid"
          class="mr-2 size-4 text-blue-500 dark:text-blue-400" />
        <span class="truncate font-mono text-sm text-gray-800 dark:text-gray-200">
          {{ displayLink }}
        </span>
      </div>
      <button
        @click="handleCopy"
        class="absolute inset-y-0 right-0 rounded-r-md border-l border-gray-200 bg-gray-100 p-2 px-3 transition-all hover:bg-gray-200 dark:border-gray-600 dark:bg-gray-700 dark:hover:bg-gray-600"
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
