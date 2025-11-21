<!-- Advanced Options Expanded Mockup -->
<script setup lang="ts">
const title = 'Advanced Options - Expanded';
const description = 'Power users can access additional configuration: passphrase, TTL presets, recipient email.';

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

            <textarea
              readonly
              :value="sampleContent"
              aria-labelledby="secretContentLabel"
              style="min-height: 200px; max-height: 400px"
              class="block w-full resize-none rounded-lg border border-green-200 p-4 font-mono text-base leading-relaxed text-gray-900 ring-2 ring-green-500/20 placeholder:text-gray-400 dark:border-green-800 dark:bg-slate-800 dark:text-white dark:ring-green-400/20"></textarea>

            <div class="pointer-events-none absolute bottom-3 right-3 flex select-none items-center gap-1.5 rounded-full bg-white/90 px-3 py-1 text-sm shadow-sm backdrop-blur-sm dark:bg-gray-800/90">
              <span class="size-2.5 rounded-full bg-emerald-400 dark:bg-emerald-500"></span>
              <span class="font-medium text-gray-600 dark:text-gray-400">
                61 / 10,000
              </span>
            </div>
          </div>
        </div>

        <!-- Divider -->
        <div class="border-t border-gray-200 dark:border-gray-700"></div>

        <!-- Advanced Options Section (EXPANDED) -->
        <div class="bg-gray-50 dark:bg-slate-800/50">
          <button
            type="button"
            class="flex w-full items-center justify-between px-6 py-4 text-left text-sm font-medium text-gray-700 dark:text-gray-300">
            <span class="flex items-center gap-2">
              <svg class="size-4 rotate-90 transition-transform" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
              </svg>
              Advanced options
            </span>
            <span class="text-xs text-gray-500 dark:text-gray-500">
              Click to collapse
            </span>
          </button>

          <!-- Advanced Options Panel -->
          <div class="space-y-6 px-6 pb-6">

            <!-- Passphrase Field -->
            <div>
              <div class="mb-2 flex items-center justify-between">
                <label
                  for="passphrase"
                  class="flex items-center gap-2 text-sm font-medium text-gray-700 dark:text-gray-300">
                  Passphrase
                  <span class="text-xs font-normal text-gray-500">(optional)</span>
                  <button
                    type="button"
                    class="inline-flex size-4 items-center justify-center rounded-full bg-gray-200 text-xs text-gray-600 hover:bg-gray-300 dark:bg-gray-700 dark:text-gray-400 dark:hover:bg-gray-600"
                    title="What is a passphrase?">
                    ?
                  </button>
                </label>
              </div>

              <!-- Hint text -->
              <p class="mb-2 text-xs text-gray-500 dark:text-gray-400">
                Minimum 8 characters • Mix of uppercase and lowercase recommended
              </p>

              <!-- Passphrase Input with Toggle -->
              <div class="relative">
                <input
                  id="passphrase"
                  type="password"
                  value="MySecure123"
                  readonly
                  class="w-full rounded-lg border border-gray-200 bg-white py-2.5 pl-4 pr-24 text-sm text-gray-900 focus:border-blue-500 focus:ring-2 focus:ring-blue-500 dark:border-gray-700 dark:bg-slate-800 dark:text-white"
                  placeholder="Enter passphrase..." />

                <!-- Visibility Toggle -->
                <button
                  type="button"
                  class="absolute inset-y-0 right-12 flex items-center px-3 text-gray-400 hover:text-gray-600 dark:hover:text-gray-300">
                  <svg class="size-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z" />
                  </svg>
                </button>

                <!-- Generate Button -->
                <button
                  type="button"
                  class="absolute inset-y-0 right-2 flex items-center rounded-md px-2 text-xs font-medium text-blue-600 hover:text-blue-700 dark:text-blue-400 dark:hover:text-blue-300">
                  <svg class="mr-1 size-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
                  </svg>
                  Gen
                </button>
              </div>

              <!-- Strength Meter -->
              <div class="mt-2">
                <div class="mb-1 flex items-center gap-2">
                  <div class="h-1.5 flex-1 overflow-hidden rounded-full bg-gray-200 dark:bg-gray-700">
                    <div class="h-full w-2/3 rounded-full bg-amber-400 transition-all duration-300"></div>
                  </div>
                  <span class="text-xs font-medium text-amber-600 dark:text-amber-400">
                    Medium
                  </span>
                </div>

                <!-- Requirements Checklist -->
                <div class="flex flex-wrap gap-x-4 gap-y-1 text-xs text-gray-600 dark:text-gray-400">
                  <div class="flex items-center gap-1">
                    <svg class="size-3 text-green-500" fill="currentColor" viewBox="0 0 20 20">
                      <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd" />
                    </svg>
                    8+ characters
                  </div>
                  <div class="flex items-center gap-1">
                    <svg class="size-3 text-green-500" fill="currentColor" viewBox="0 0 20 20">
                      <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd" />
                    </svg>
                    Uppercase
                  </div>
                  <div class="flex items-center gap-1">
                    <svg class="size-3 text-green-500" fill="currentColor" viewBox="0 0 20 20">
                      <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd" />
                    </svg>
                    Lowercase
                  </div>
                  <div class="flex items-center gap-1">
                    <svg class="size-3 text-green-500" fill="currentColor" viewBox="0 0 20 20">
                      <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd" />
                    </svg>
                    Number
                  </div>
                  <div class="flex items-center gap-1 opacity-50">
                    <svg class="size-3 text-gray-400" fill="currentColor" viewBox="0 0 20 20">
                      <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd" />
                    </svg>
                    Symbol
                  </div>
                </div>
              </div>
            </div>

            <!-- Expiration Section -->
            <div>
              <label class="mb-2 flex items-center gap-2 text-sm font-medium text-gray-700 dark:text-gray-300">
                Expiration
                <button
                  type="button"
                  class="inline-flex size-4 items-center justify-center rounded-full bg-gray-200 text-xs text-gray-600 hover:bg-gray-300 dark:bg-gray-700 dark:text-gray-400 dark:hover:bg-gray-600"
                  title="When will this secret expire?">
                  ?
                </button>
              </label>

              <!-- TTL Presets (Visual Buttons) -->
              <div class="mb-3 flex gap-2">
                <button
                  type="button"
                  class="flex-1 rounded-lg border border-gray-200 bg-white py-2.5 text-center text-sm font-medium text-gray-700 transition-all hover:border-blue-500 hover:bg-blue-50 dark:border-gray-700 dark:bg-slate-800 dark:text-gray-300 dark:hover:border-blue-500 dark:hover:bg-blue-900/20">
                  <div class="text-xs text-gray-500 dark:text-gray-400">Quick</div>
                  <div class="font-semibold">1 Hour</div>
                </button>
                <button
                  type="button"
                  class="flex-1 rounded-lg border-2 border-blue-500 bg-blue-50 py-2.5 text-center text-sm font-medium text-blue-700 dark:border-blue-500 dark:bg-blue-900/20 dark:text-blue-300">
                  <div class="text-xs">Standard</div>
                  <div class="font-semibold">1 Day</div>
                </button>
                <button
                  type="button"
                  class="flex-1 rounded-lg border border-gray-200 bg-white py-2.5 text-center text-sm font-medium text-gray-700 transition-all hover:border-blue-500 hover:bg-blue-50 dark:border-gray-700 dark:bg-slate-800 dark:text-gray-300 dark:hover:border-blue-500 dark:hover:bg-blue-900/20">
                  <div class="text-xs text-gray-500 dark:text-gray-400">Extended</div>
                  <div class="font-semibold">1 Week</div>
                </button>
              </div>

              <!-- Custom Dropdown -->
              <div>
                <label class="mb-1 text-xs text-gray-600 dark:text-gray-400">Or choose custom:</label>
                <select
                  class="w-full rounded-lg border border-gray-200 bg-white py-2.5 pl-4 pr-10 text-sm text-gray-700 focus:border-blue-500 focus:ring-2 focus:ring-blue-500 dark:border-gray-700 dark:bg-slate-800 dark:text-gray-300">
                  <option>1 minute</option>
                  <option>5 minutes</option>
                  <option>30 minutes</option>
                  <option>1 hour</option>
                  <option selected>1 day</option>
                  <option>3 days</option>
                  <option>1 week</option>
                  <option>2 weeks</option>
                  <option>30 days</option>
                </select>
              </div>
            </div>

            <!-- Recipient Email (Optional) -->
            <div>
              <label
                for="recipient"
                class="mb-2 flex items-center gap-2 text-sm font-medium text-gray-700 dark:text-gray-300">
                Send to recipient
                <span class="text-xs font-normal text-gray-500">(optional)</span>
              </label>
              <div class="relative">
                <div class="pointer-events-none absolute inset-y-0 left-3 flex items-center">
                  <svg class="size-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
                  </svg>
                </div>
                <input
                  id="recipient"
                  type="email"
                  readonly
                  class="w-full rounded-lg border border-gray-200 bg-white py-2.5 pl-10 pr-4 text-sm text-gray-900 focus:border-blue-500 focus:ring-2 focus:ring-blue-500 dark:border-gray-700 dark:bg-slate-800 dark:text-white"
                  placeholder="recipient@example.com" />
              </div>
              <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
                We'll email the link to this address
              </p>
            </div>

          </div>
        </div>

        <!-- Divider -->
        <div class="border-t border-gray-200 dark:border-gray-700"></div>

        <!-- Actions Section -->
        <div class="p-6">
          <div class="space-y-4">
            <button
              class="w-full rounded-lg bg-blue-600 px-6 py-3.5 text-base font-semibold text-white shadow-sm transition-all duration-200 hover:bg-blue-700 hover:shadow-md focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 dark:bg-blue-500 dark:hover:bg-blue-600">
              Create Secret Link
            </button>

            <div class="flex flex-wrap items-center justify-center gap-3 text-sm text-gray-600 dark:text-gray-400">
              <div class="flex items-center gap-1.5">
                <svg class="size-4 text-green-600 dark:text-green-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
                </svg>
                <span>Encrypted</span>
              </div>
              <span class="text-gray-300 dark:text-gray-600">•</span>
              <div class="flex items-center gap-1.5">
                <svg class="size-4 text-green-600 dark:text-green-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
                </svg>
                <span>Passphrase protected</span>
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
                <span>Expires in 1 day</span>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Mockup Annotations -->
      <div class="rounded-lg border border-blue-200 bg-blue-50 p-4 dark:border-blue-800 dark:bg-blue-900/20">
        <h3 class="mb-2 font-semibold text-blue-900 dark:text-blue-200">Design Notes:</h3>
        <ul class="space-y-1 text-sm text-blue-800 dark:text-blue-300">
          <li>✓ Passphrase field with real-time strength meter and requirements checklist</li>
          <li>✓ Visual TTL presets (buttons) for common use cases</li>
          <li>✓ Custom dropdown for specific time periods</li>
          <li>✓ Inline help icons (?') for contextual explanations</li>
          <li>✓ Generate passphrase button for convenience</li>
          <li>✓ Trust indicators update based on settings (added "Passphrase protected")</li>
          <li>✓ All fields clearly labeled as optional to reduce anxiety</li>
          <li>✓ Collapsible panel doesn't break flow</li>
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
