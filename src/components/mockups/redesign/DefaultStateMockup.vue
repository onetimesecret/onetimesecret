<!-- Default State Mockup - Empty Form -->
<script setup lang="ts">
import { ref } from 'vue';

const title = 'Default State - Empty Form';
const description = 'First impression: Clean, focused, minimal distractions. Textarea is the hero.';
</script>

<template>
  <div class="mockup-container">
    <div class="mockup-header">
      <h2 class="text-2xl font-bold text-gray-900 dark:text-white">{{ title }}</h2>
      <p class="text-sm text-gray-600 dark:text-gray-400">{{ description }}</p>
    </div>

    <div class="mx-auto max-w-2xl space-y-6 p-6">
      <!-- Main Form Container -->
      <div class="overflow-visible rounded-lg border border-gray-200 bg-white shadow-lg dark:border-gray-700 dark:bg-slate-900">

        <!-- Content Section -->
        <div class="p-6">
          <!-- Secret Input Section -->
          <div class="relative">
            <label
              id="secretContentLabel"
              class="sr-only">
              Secret Content
            </label>

            <!-- Textarea - Hero Element -->
            <textarea
              readonly
              placeholder="Enter your secret here..."
              aria-labelledby="secretContentLabel"
              style="min-height: 200px; max-height: 400px"
              class="block w-full resize-none rounded-lg border border-gray-200 p-4 font-mono text-base leading-relaxed text-gray-900 placeholder:text-gray-400 focus:border-blue-500 focus:ring-2 focus:ring-blue-500 dark:border-gray-700 dark:bg-slate-800 dark:text-white dark:placeholder:text-gray-500"></textarea>

            <!-- Character Counter (subtle, always visible) -->
            <div class="pointer-events-none absolute bottom-3 right-3 flex select-none items-center gap-1.5 rounded-full bg-white/90 px-3 py-1 text-sm opacity-50 shadow-sm backdrop-blur-sm dark:bg-gray-800/90">
              <span class="font-medium text-gray-600 dark:text-gray-400">
                0 / 10,000
              </span>
            </div>
          </div>
        </div>

        <!-- Divider -->
        <div class="border-t border-gray-200 dark:border-gray-700"></div>

        <!-- Actions Section -->
        <div class="p-6">
          <div class="space-y-4">
            <!-- Primary Action Button (Disabled State) -->
            <button
              disabled
              class="w-full rounded-lg bg-gray-300 px-6 py-3.5 text-base font-semibold text-gray-500 shadow-sm transition-colors duration-200 dark:bg-gray-700 dark:text-gray-500">
              Create Secret Link
            </button>

            <!-- Advanced Options Toggle (Collapsed) -->
            <button
              type="button"
              class="flex w-full items-center justify-between rounded-lg border border-gray-200 bg-gray-50 px-4 py-3 text-left text-sm font-medium text-gray-700 transition-colors hover:bg-gray-100 dark:border-gray-700 dark:bg-slate-800/50 dark:text-gray-300 dark:hover:bg-slate-800">
              <span class="flex items-center gap-2">
                <svg class="size-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
                </svg>
                Advanced options
              </span>
            </button>

            <!-- Trust Indicators (Always Visible) -->
            <div class="flex flex-wrap items-center justify-center gap-3 text-sm text-gray-600 dark:text-gray-400">
              <div class="flex items-center gap-1.5">
                <svg class="size-4 text-green-600 dark:text-green-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
                </svg>
                <span>Encrypted</span>
              </div>
              <span class="text-gray-300 dark:text-gray-600">•</span>
              <div class="flex items-center gap-1.5">
                <svg class="size-4 text-orange-600 dark:text-orange-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17.657 18.657A8 8 0 016.343 7.343S7 9 9 10c0-2 .5-5 2.986-7C14 5 16.09 5.777 17.656 7.343A7.975 7.975 0 0120 13a7.975 7.975 0 01-2.343 5.657z" />
                </svg>
                <span>One-time only</span>
              </div>
              <span class="text-gray-300 dark:text-gray-600">•</span>
              <div class="flex items-center gap-1.5">
                <svg class="size-4 text-blue-600 dark:text-blue-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
                <span>Expires in 7 days</span>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Mockup Annotations -->
      <div class="rounded-lg border border-blue-200 bg-blue-50 p-4 dark:border-blue-800 dark:bg-blue-900/20">
        <h3 class="mb-2 font-semibold text-blue-900 dark:text-blue-200">Design Notes:</h3>
        <ul class="space-y-1 text-sm text-blue-800 dark:text-blue-300">
          <li>✓ Textarea is the largest, most prominent element</li>
          <li>✓ Character counter visible but subtle (low opacity)</li>
          <li>✓ Submit button disabled until content is entered</li>
          <li>✓ Advanced options collapsed by default</li>
          <li>✓ Trust indicators always visible for confidence</li>
          <li>✓ Clean visual hierarchy with clear primary action</li>
        </ul>
      </div>
    </div>
  </div>
</template>

<style scoped>
.mockup-container {
  @apply min-h-screen bg-gray-50 py-8 dark:bg-slate-950;
}

.mockup-header {
  @apply mb-6 text-center;
}
</style>
