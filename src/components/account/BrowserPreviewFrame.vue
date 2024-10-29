<template>
  <div class="rounded-xl shadow-2xl overflow-hidden border border-gray-200 dark:border-gray-700">
    <!-- Browser Top Bar -->
    <div class="bg-gray-100 dark:bg-gray-800 border-b border-gray-200 dark:border-gray-700 p-3 flex items-center space-x-2">
      <div class="flex space-x-2">
        <div class="w-3 h-3 rounded-full bg-red-400"></div>
        <div class="w-3 h-3 rounded-full bg-yellow-400"></div>
        <div class="w-3 h-3 rounded-full bg-green-400"></div>
      </div>
      <div class="flex-1 mx-4">
        <div class="bg-white dark:bg-gray-700 rounded-md px-3 py-1.5 text-sm text-gray-600 dark:text-gray-300 flex items-center">
          <svg class="w-4 h-4 mr-2 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
          </svg>
          <span class="text-green-400">https://</span><span class="font-bold">{{ domain }}</span><span class="opacity-50">/secret/abcdef0123456789</span>
        </div>
      </div>
    </div>

    <!-- Preview Badge -->
    <div class="absolute -top-6 left-1/2 transform -translate-x-1/2 z-10 opacity-60">
      <span class="inline-flex items-center px-4 py-1.5 rounded-full text-xs font-medium bg-brandcomp-100 dark:bg-brandcomp-900 text-brand-800 dark:text-brandcomp-200 shadow-sm">
        <svg class="w-4 h-4 mr-1.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z" />
        </svg>
        Preview Mode
      </span>
    </div>

    <!-- Content Area -->
    <div class="bg-white dark:bg-gray-800 p-6">
      <slot></slot>
    </div>
  </div>
</template>

<script setup lang="ts">
defineProps<{
  domain: string;
}>();
</script>
