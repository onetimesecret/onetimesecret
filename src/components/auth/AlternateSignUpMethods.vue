<template>

  <!-- Alternate sign up methods -->
  <div class="mt-6">
    <div class="relative">
      <div class="absolute inset-0 flex items-center">
        <div class="w-full border-t border-gray-300 dark:border-gray-700"></div>
      </div>
      <div class="relative flex justify-center">
        <span class="px-2 bg-white text-sm text-gray-500 dark:bg-gray-800 dark:text-gray-400">
          Or continue with
        </span>
      </div>
    </div>

    <div class="relative mt-8">
      <div class="absolute inset-0 z-10 flex items-center justify-center">
        <div
             class="rounded-md px-4 py-2 font-brand font-bold text-lg text-white bg-brand-600
             dark:bg-brand-400 dark:text-gray-700 transform rotate-[-15deg] shadow-lg opacity-65">
          Coming Soon
        </div>
      </div>

      <div class="absolute inset-0 bg-gray-50 bg-opacity-50 dark:bg-gray-800 dark:bg-opacity-50 z-5"></div>
      <div :class="gridClass">
        <button v-for="provider in alternateProviders"
                :key="provider.name"
                class="inline-flex w-full justify-center items-center rounded-md border px-4 py-2 text-sm font-medium
                shadow-sm bg-gray-100 text-gray-400 border-gray-300 cursor-not-allowed
                dark:bg-gray-800 dark:text-gray-500 dark:border-gray-700
                focus:outline-none transition-colors duration-200"
                :aria-label="`Sign up with ${provider.name} (coming soon)`"
                disabled>
          <Icon :icon="provider.icon"
                class="h-5 w-5"
                aria-hidden="true" />
          <span class="ml-2">{{ provider.name }}</span>
        </button>
      </div>
    </div>

  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { Icon } from '@iconify/vue';

// Define the type for the alternate providers
interface Provider {
  name: string;
  icon: string;
}

// Props for the component
const props = defineProps<{
  alternateProviders: Provider[];
}>();

const gridClass = computed(() => {
  const colsCount = props.alternateProviders.length
  return `grid gap-3 grid-cols-${colsCount}`
})

</script>
