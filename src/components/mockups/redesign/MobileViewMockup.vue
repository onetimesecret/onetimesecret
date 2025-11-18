<!-- Mobile View Mockup -->
<script setup lang="ts">
const title = 'Mobile View - Responsive Design';
const description = 'Optimized for one-handed operation on mobile devices. Single column, large touch targets.';

const sampleContent = `sk-live-abc123xyz789def456`;
</script>

<template>
  <div class="mockup-container">
    <div class="mockup-header">
      <h2 class="text-2xl font-bold text-gray-900 dark:text-white">{{ title }}</h2>
      <p class="text-sm text-gray-600 dark:text-gray-400">{{ description }}</p>
    </div>

    <div class="flex justify-center gap-6 p-6">
      <!-- Mobile Device Frame 1: Default State -->
      <div class="mobile-frame">
        <div class="mobile-screen">
          <!-- Mobile Header -->
          <div class="sticky top-0 z-10 border-b border-gray-200 bg-white px-4 py-3 dark:border-gray-700 dark:bg-slate-900">
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-2">
                <svg class="size-6 text-brand-600" fill="currentColor" viewBox="0 0 20 20">
                  <path d="M10 2a5 5 0 00-5 5v2a2 2 0 00-2 2v5a2 2 0 002 2h10a2 2 0 002-2v-5a2 2 0 00-2-2H7V7a3 3 0 015.905-.75 1 1 0 001.937-.5A5.002 5.002 0 0010 2z" />
                </svg>
                <span class="font-semibold text-gray-900 dark:text-white">OneTime</span>
              </div>
              <button class="rounded-lg p-2 hover:bg-gray-100 dark:hover:bg-gray-800">
                <svg class="size-5 text-gray-600 dark:text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16M4 18h16" />
                </svg>
              </button>
            </div>
          </div>

          <!-- Mobile Content -->
          <div class="space-y-4 p-4">
            <!-- Textarea - Mobile Optimized -->
            <div class="relative">
              <textarea
                readonly
                placeholder="Enter your secret here..."
                style="min-height: 180px"
                class="block w-full resize-none rounded-lg border border-gray-200 p-4 text-base leading-relaxed text-gray-900 placeholder:text-gray-400 focus:border-blue-500 focus:ring-2 focus:ring-blue-500 dark:border-gray-700 dark:bg-slate-800 dark:text-white dark:placeholder:text-gray-500"></textarea>

              <div class="pointer-events-none absolute bottom-3 right-3 flex select-none items-center gap-1.5 rounded-full bg-white/90 px-2.5 py-1 text-xs shadow-sm backdrop-blur-sm opacity-50 dark:bg-gray-800/90">
                <span class="font-medium text-gray-600 dark:text-gray-400">
                  0 / 10K
                </span>
              </div>
            </div>

            <!-- Advanced Options Toggle (Collapsed) -->
            <button
              type="button"
              class="flex w-full items-center justify-between rounded-lg border border-gray-200 bg-gray-50 px-4 py-3.5 text-left text-sm font-medium text-gray-700 dark:border-gray-700 dark:bg-slate-800/50 dark:text-gray-300">
              <span class="flex items-center gap-2">
                <svg class="size-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
                </svg>
                Advanced options
              </span>
              <span class="text-xs text-gray-500">Optional</span>
            </button>

            <!-- Trust Indicators (Compact) -->
            <div class="rounded-lg bg-gray-50 p-3 dark:bg-slate-800/50">
              <div class="flex items-center justify-center gap-2 text-xs text-gray-600 dark:text-gray-400">
                <svg class="size-4 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
                </svg>
                <span>Encrypted</span>
                <span class="text-gray-300">•</span>
                <svg class="size-4 text-orange-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17.657 18.657A8 8 0 016.343 7.343S7 9 9 10c0-2 .5-5 2.986-7C14 5 16.09 5.777 17.656 7.343A7.975 7.975 0 0120 13a7.975 7.975 0 01-2.343 5.657z" />
                </svg>
                <span>One-time</span>
              </div>
            </div>
          </div>

          <!-- Sticky Bottom Button -->
          <div class="sticky bottom-0 border-t border-gray-200 bg-white p-4 dark:border-gray-700 dark:bg-slate-900">
            <button
              disabled
              class="w-full rounded-lg bg-gray-300 py-3.5 text-base font-semibold text-gray-500 dark:bg-gray-700">
              Create Secret Link
            </button>
          </div>

          <div class="p-2 text-center text-xs text-gray-500">
            Default State
          </div>
        </div>
      </div>

      <!-- Mobile Device Frame 2: Active with Content -->
      <div class="mobile-frame">
        <div class="mobile-screen">
          <!-- Mobile Header -->
          <div class="sticky top-0 z-10 border-b border-gray-200 bg-white px-4 py-3 dark:border-gray-700 dark:bg-slate-900">
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-2">
                <svg class="size-6 text-brand-600" fill="currentColor" viewBox="0 0 20 20">
                  <path d="M10 2a5 5 0 00-5 5v2a2 2 0 00-2 2v5a2 2 0 002 2h10a2 2 0 002-2v-5a2 2 0 00-2-2H7V7a3 3 0 015.905-.75 1 1 0 001.937-.5A5.002 5.002 0 0010 2z" />
                </svg>
                <span class="font-semibold text-gray-900 dark:text-white">OneTime</span>
              </div>
              <button class="rounded-lg p-2 hover:bg-gray-100 dark:hover:bg-gray-800">
                <svg class="size-5 text-gray-600 dark:text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16M4 18h16" />
                </svg>
              </button>
            </div>
          </div>

          <!-- Mobile Content -->
          <div class="space-y-4 p-4">
            <!-- Textarea with Content -->
            <div class="relative">
              <textarea
                readonly
                :value="sampleContent"
                style="min-height: 180px"
                class="block w-full resize-none rounded-lg border border-green-200 p-4 text-base leading-relaxed text-gray-900 ring-2 ring-green-500/20 dark:border-green-800 dark:bg-slate-800 dark:text-white dark:ring-green-400/20"></textarea>

              <div class="pointer-events-none absolute bottom-3 right-3 flex select-none items-center gap-1.5 rounded-full bg-white/90 px-2.5 py-1 text-xs shadow-sm backdrop-blur-sm dark:bg-gray-800/90">
                <span class="size-2 rounded-full bg-emerald-400"></span>
                <span class="font-medium text-gray-600 dark:text-gray-400">
                  29 / 10K
                </span>
              </div>
            </div>

            <!-- Smart Suggestion (Mobile) -->
            <div class="rounded-lg border border-blue-200 bg-blue-50 p-3 dark:border-blue-800 dark:bg-blue-900/20">
              <div class="flex items-start gap-2">
                <svg class="size-5 shrink-0 text-blue-600" fill="currentColor" viewBox="0 0 20 20">
                  <path d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" />
                </svg>
                <div class="flex-1">
                  <p class="text-xs font-medium text-blue-900 dark:text-blue-200">
                    Add a passphrase?
                  </p>
                  <p class="mt-0.5 text-xs text-blue-700 dark:text-blue-300">
                    Recommended for API keys
                  </p>
                </div>
                <button class="shrink-0 text-xs font-medium text-blue-600">
                  Add
                </button>
              </div>
            </div>

            <!-- Advanced Options Toggle -->
            <button
              type="button"
              class="flex w-full items-center justify-between rounded-lg border border-gray-200 bg-gray-50 px-4 py-3.5 text-left text-sm font-medium text-gray-700 dark:border-gray-700 dark:bg-slate-800/50 dark:text-gray-300">
              <span class="flex items-center gap-2">
                <svg class="size-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
                </svg>
                Advanced options
              </span>
            </button>

            <!-- Trust Indicators -->
            <div class="rounded-lg bg-gray-50 p-3 dark:bg-slate-800/50">
              <div class="flex items-center justify-center gap-2 text-xs text-gray-600 dark:text-gray-400">
                <svg class="size-4 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
                </svg>
                <span>Encrypted</span>
                <span class="text-gray-300">•</span>
                <svg class="size-4 text-orange-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17.657 18.657A8 8 0 016.343 7.343S7 9 9 10c0-2 .5-5 2.986-7C14 5 16.09 5.777 17.656 7.343A7.975 7.975 0 0120 13a7.975 7.975 0 01-2.343 5.657z" />
                </svg>
                <span>One-time</span>
              </div>
            </div>

            <!-- Auto-save indicator -->
            <div class="flex items-center justify-center gap-1.5 text-xs text-gray-500">
              <svg class="size-3 text-green-500" fill="currentColor" viewBox="0 0 20 20">
                <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd" />
              </svg>
              <span>Saved</span>
            </div>
          </div>

          <!-- Sticky Bottom Button (Enabled) -->
          <div class="sticky bottom-0 border-t border-gray-200 bg-white p-4 shadow-lg dark:border-gray-700 dark:bg-slate-900">
            <button
              class="w-full rounded-lg bg-blue-600 py-3.5 text-base font-semibold text-white shadow-sm active:bg-blue-700 dark:bg-blue-500">
              Create Secret Link
            </button>
          </div>

          <div class="p-2 text-center text-xs text-gray-500">
            Active State
          </div>
        </div>
      </div>
    </div>

    <!-- Mockup Annotations -->
    <div class="mx-auto max-w-4xl rounded-lg border border-blue-200 bg-blue-50 p-4 dark:border-blue-800 dark:bg-blue-900/20">
      <h3 class="mb-2 font-semibold text-blue-900 dark:text-blue-200">Mobile Design Notes:</h3>
      <div class="grid gap-4 md:grid-cols-2">
        <ul class="space-y-1 text-sm text-blue-800 dark:text-blue-300">
          <li>✓ Single column layout (no grid on mobile)</li>
          <li>✓ Larger touch targets (48x48px minimum)</li>
          <li>✓ Sticky header and footer for navigation</li>
          <li>✓ Textarea auto-resizes to content</li>
          <li>✓ Compact trust indicators save space</li>
          <li>✓ Bottom sheet for advanced options (better than accordion)</li>
        </ul>
        <ul class="space-y-1 text-sm text-blue-800 dark:text-blue-300">
          <li>✓ Character counter uses abbreviated format (10K vs 10,000)</li>
          <li>✓ Smart suggestion more compact but still clear</li>
          <li>✓ One-handed operation friendly</li>
          <li>✓ No horizontal scrolling required</li>
          <li>✓ Submit button always accessible at bottom</li>
          <li>✓ Reduced text sizes for smaller screens</li>
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

.mobile-frame {
  @apply relative h-[700px] w-[375px] shrink-0 overflow-hidden rounded-[3rem] border-[14px] border-gray-800 bg-gray-800 shadow-2xl dark:border-gray-700;
}

.mobile-screen {
  @apply flex h-full flex-col overflow-y-auto bg-white dark:bg-slate-900;
}

/* Mobile notch simulation */
.mobile-frame::before {
  content: '';
  @apply absolute left-1/2 top-0 z-20 h-7 w-40 -translate-x-1/2 rounded-b-2xl bg-gray-800 dark:bg-gray-700;
}
</style>
