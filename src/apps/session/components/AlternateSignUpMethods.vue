<!-- src/apps/session/components/AlternateSignUpMethods.vue -->

<script setup lang="ts">
import OIcon from '@/shared/components/icons/OIcon.vue';
import { computed } from 'vue'

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

<template>
  <!-- Alternate sign up methods -->
  <div class="mt-6">
    <div class="relative">
      <div class="absolute inset-0 flex items-center">
        <div class="w-full border-t border-gray-300 dark:border-gray-700"></div>
      </div>
      <div class="relative flex justify-center">
        <span class="bg-white px-2 text-sm text-gray-500 dark:bg-gray-800 dark:text-gray-400">
          Or continue with
        </span>
      </div>
    </div>

    <div class="relative mt-8">
      <div class="absolute inset-0 z-10 flex items-center justify-center">
        <div
          class="rotate-[-15deg] rounded-md bg-brand-600 px-4 py-2 font-brand text-lg font-bold
             text-white opacity-65 shadow-lg dark:bg-brand-400 dark:text-gray-700">
          Coming Soon
        </div>
      </div>

      <div class="z-5 absolute inset-0 bg-gray-50/50 dark:bg-gray-800/50"></div>
      <div :class="gridClass">
        <button
          v-for="provider in alternateProviders"
          :key="provider.name"
          class="inline-flex w-full cursor-not-allowed items-center justify-center rounded-md border border-gray-300 bg-gray-100 px-4
                py-2 text-sm font-medium text-gray-400 shadow-sm
                transition-colors duration-200 focus:outline-none
                dark:border-gray-700 dark:bg-gray-800 dark:text-gray-500"
          :aria-label="`Sign up with ${provider.name} (coming soon)`"
          disabled>
          <OIcon
            collection="heroicons"
            :name="provider.icon"
            class="size-5"
            aria-hidden="true" />
          <span class="ml-2">{{ provider.name }}</span>
        </button>
      </div>
    </div>
  </div>
</template>
