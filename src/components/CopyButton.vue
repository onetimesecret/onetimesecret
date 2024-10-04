<!-- src/components/CopyButton.vue -->

<template>
  <div class="relative inline-block">
    <button @click="copyToClipboard"
            @mouseenter="showTooltip = true"
            @mouseleave="showTooltip = false"
            class="text-gray-600 hover:text-gray-900 dark:text-gray-400 dark:hover:text-white focus:outline-none"
            :aria-label="copied ? 'Copied' : 'Copy to clipboard'">
      <svg v-if="!copied"
           class="w-5 h-5"
           fill="none"
           stroke="currentColor"
           viewBox="0 0 24 24"
           xmlns="http://www.w3.org/2000/svg">
        <path stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z">
        </path>
      </svg>
      <svg v-else
           class="w-5 h-5 text-green-500"
           fill="none"
           stroke="currentColor"
           viewBox="0 0 24 24"
           xmlns="http://www.w3.org/2000/svg">
        <path stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M5 13l4 4L19 7"></path>
      </svg>
    </button>
    <div v-if="showTooltip"
         class="absolute z-10 px-2 py-1 text-sm text-white bg-gray-900 rounded-md bottom-full left-1/2 transform -translate-x-1/2 -translate-y-2">
      {{ copied ? 'Copied!' : 'Copy to clipboard' }}
    </div>
  </div>
</template>


<script setup lang="ts">
import { ref, onBeforeUnmount } from 'vue';

interface Props {
  text: string;
  interval?: number;
}

const props = withDefaults(defineProps<Props>(), {
  text: '',
  interval: 2000
});

const copied = ref(false);
const showTooltip = ref(false);
let tooltipTimeout: number | null = null;

const copyToClipboard = () => {
  navigator.clipboard.writeText(props.text).then(() => {
    copied.value = true;
    showTooltip.value = true;

    if (tooltipTimeout) clearTimeout(tooltipTimeout);

    setTimeout(() => {
      copied.value = false;
      showTooltip.value = false;
    }, props.interval);
  });
};

onBeforeUnmount(() => {
  if (tooltipTimeout) clearTimeout(tooltipTimeout);
});
</script>
