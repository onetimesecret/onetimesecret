<!-- Active State Mockup - With Content Entered -->
<script setup lang="ts">
const title = 'Active State - Content Entered';
const description = 'User has entered content. Smart suggestion appears. Submit button is now enabled.';

const sampleContent = `sk-live-abc123xyz789def456ghi012jkl345mno678pqr901stu234vwx567`;
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

            <!-- Textarea with Content -->
            <textarea
              readonly
              :value="sampleContent"
              aria-labelledby="secretContentLabel"
              style="min-height: 200px; max-height: 400px"
              class="block w-full resize-none rounded-lg border border-green-200 p-4 font-mono text-base leading-relaxed text-gray-900 ring-2 ring-green-500/20 placeholder:text-gray-400 dark:border-green-800 dark:bg-slate-800 dark:text-white dark:ring-green-400/20"></textarea>

            <!-- Character Counter (Active with green indicator) -->
            <div class="pointer-events-none absolute bottom-3 right-3 flex select-none items-center gap-1.5 rounded-full bg-white/90 px-3 py-1 text-sm shadow-sm backdrop-blur-sm dark:bg-gray-800/90">
              <span class="size-2.5 rounded-full bg-emerald-400 dark:bg-emerald-500"></span>
              <span class="font-medium text-gray-600 dark:text-gray-400">
                61 / 10,000
              </span>
            </div>
          </div>

          <!-- Smart Suggestion (Appears after content entered) -->
          <div class="mt-4 animate-fade-in rounded-lg border border-blue-200 bg-blue-50 p-4 dark:border-blue-800 dark:bg-blue-900/20">
            <div class="flex items-start gap-3">
              <div class="shrink-0">
                <svg class="size-5 text-blue-600 dark:text-blue-400" fill="currentColor" viewBox="0 0 20 20">
                  <path d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" />
                </svg>
              </div>
              <div class="flex-1">
                <p class="text-sm font-medium text-blue-900 dark:text-blue-200">
                  Consider adding a passphrase for extra security
                </p>
                <p class="mt-1 text-xs text-blue-700 dark:text-blue-300">
                  Recommended for sensitive credentials like API keys
                </p>
              </div>
              <button
                type="button"
                class="shrink-0 rounded text-sm font-medium text-blue-600 hover:text-blue-800 dark:text-blue-400 dark:hover:text-blue-300">
                Add →
              </button>
            </div>
          </div>
        </div>

        <!-- Divider -->
        <div class="border-t border-gray-200 dark:border-gray-700"></div>

        <!-- Actions Section -->
        <div class="p-6">
          <div class="space-y-4">
            <!-- Primary Action Button (Now Enabled) -->
            <button
              class="w-full rounded-lg bg-blue-600 px-6 py-3.5 text-base font-semibold text-white shadow-sm transition-all duration-200 hover:bg-blue-700 hover:shadow-md focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 dark:bg-blue-500 dark:hover:bg-blue-600">
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
              <span class="rounded-full bg-gray-200 px-2 py-0.5 text-xs text-gray-600 dark:bg-gray-700 dark:text-gray-400">
                Optional
              </span>
            </button>

            <!-- Trust Indicators -->
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

            <!-- Auto-save Indicator -->
            <div class="flex items-center justify-center gap-2 text-xs text-gray-500 dark:text-gray-500">
              <svg class="size-3 text-green-500" fill="currentColor" viewBox="0 0 20 20">
                <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd" />
              </svg>
              <span>Draft saved</span>
            </div>
          </div>
        </div>
      </div>

      <!-- Mockup Annotations -->
      <div class="rounded-lg border border-blue-200 bg-blue-50 p-4 dark:border-blue-800 dark:bg-blue-900/20">
        <h3 class="mb-2 font-semibold text-blue-900 dark:text-blue-200">Design Notes:</h3>
        <ul class="space-y-1 text-sm text-blue-800 dark:text-blue-300">
          <li>✓ Textarea shows subtle green border/ring when valid</li>
          <li>✓ Character counter now prominent with green status indicator</li>
          <li>✓ Smart suggestion appears contextually (detected API key pattern)</li>
          <li>✓ Submit button now enabled and visually prominent</li>
          <li>✓ "Optional" badge on advanced options reduces anxiety</li>
          <li>✓ Auto-save confirmation provides peace of mind</li>
          <li>✓ Fade-in animation for suggestion (smooth, not jarring)</li>
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

@keyframes fade-in {
  from {
    opacity: 0;
    transform: translateY(-10px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

.animate-fade-in {
  animation: fade-in 300ms ease-out;
}
</style>
