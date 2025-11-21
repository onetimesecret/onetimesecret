<!-- Pre-Flight Confirmation Modal Mockup -->
<script setup lang="ts">
const title = 'Pre-Flight Confirmation Modal';
const description = 'Final review before creating the secret. Builds trust and prevents errors.';
</script>

<template>
  <div class="mockup-container">
    <div class="mockup-header">
      <h2 class="text-2xl font-bold text-gray-900 dark:text-white">{{ title }}</h2>
      <p class="text-sm text-gray-600 dark:text-gray-400">{{ description }}</p>
    </div>

    <div class="mx-auto max-w-2xl space-y-6 p-6">
      <!-- Background Content (Dimmed) -->
      <div class="pointer-events-none relative opacity-40">
        <div class="overflow-visible rounded-lg border border-gray-200 bg-white shadow-lg dark:border-gray-700 dark:bg-slate-900">
          <div class="p-6">
            <textarea
              disabled
              value="sk-live-abc123xyz789..."
              style="min-height: 200px"
              class="block w-full resize-none rounded-lg border border-gray-200 p-4 font-mono text-base leading-relaxed text-gray-900 dark:border-gray-700 dark:bg-slate-800 dark:text-white"></textarea>
          </div>
        </div>
      </div>

      <!-- Modal Overlay -->
      <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4 backdrop-blur-sm">
        <!-- Modal Card -->
        <div class="w-full max-w-md animate-scale-in rounded-xl border border-gray-200 bg-white shadow-2xl dark:border-gray-700 dark:bg-slate-900">

          <!-- Modal Header -->
          <div class="border-b border-gray-200 p-6 dark:border-gray-700">
            <div class="flex items-start justify-between">
              <div class="flex items-center gap-3">
                <div class="flex size-10 items-center justify-center rounded-full bg-blue-100 dark:bg-blue-900/30">
                  <svg class="size-6 text-blue-600 dark:text-blue-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                  </svg>
                </div>
                <div>
                  <h3 class="text-lg font-semibold text-gray-900 dark:text-white">
                    Confirm Secret Creation
                  </h3>
                  <p class="text-sm text-gray-500 dark:text-gray-400">
                    Review your settings
                  </p>
                </div>
              </div>
              <button
                type="button"
                class="rounded-lg p-1 text-gray-400 hover:bg-gray-100 hover:text-gray-600 dark:hover:bg-gray-800 dark:hover:text-gray-300">
                <svg class="size-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>
          </div>

          <!-- Modal Body -->
          <div class="space-y-4 p-6">
            <!-- Security Summary -->
            <div>
              <h4 class="mb-3 text-sm font-medium text-gray-700 dark:text-gray-300">
                Your secret will be:
              </h4>
              <div class="space-y-2">
                <!-- Encrypted -->
                <div class="flex items-start gap-3 rounded-lg bg-green-50 p-3 dark:bg-green-900/10">
                  <svg class="size-5 shrink-0 text-green-600 dark:text-green-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
                  </svg>
                  <div class="flex-1">
                    <p class="text-sm font-medium text-green-900 dark:text-green-200">
                      Encrypted end-to-end
                    </p>
                    <p class="text-xs text-green-700 dark:text-green-300">
                      Your data is secure in transit and at rest
                    </p>
                  </div>
                </div>

                <!-- Passphrase Protected -->
                <div class="flex items-start gap-3 rounded-lg bg-blue-50 p-3 dark:bg-blue-900/10">
                  <svg class="size-5 shrink-0 text-blue-600 dark:text-blue-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
                  </svg>
                  <div class="flex-1">
                    <p class="text-sm font-medium text-blue-900 dark:text-blue-200">
                      Passphrase protected
                    </p>
                    <p class="text-xs text-blue-700 dark:text-blue-300">
                      Recipient must enter passphrase to view
                    </p>
                  </div>
                </div>

                <!-- One-time Only -->
                <div class="flex items-start gap-3 rounded-lg bg-orange-50 p-3 dark:bg-orange-900/10">
                  <svg class="size-5 shrink-0 text-orange-600 dark:text-orange-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17.657 18.657A8 8 0 016.343 7.343S7 9 9 10c0-2 .5-5 2.986-7C14 5 16.09 5.777 17.656 7.343A7.975 7.975 0 0120 13a7.975 7.975 0 01-2.343 5.657z" />
                  </svg>
                  <div class="flex-1">
                    <p class="text-sm font-medium text-orange-900 dark:text-orange-200">
                      Viewable only once
                    </p>
                    <p class="text-xs text-orange-700 dark:text-orange-300">
                      Secret will be permanently deleted after viewing
                    </p>
                  </div>
                </div>

                <!-- Expiration -->
                <div class="flex items-start gap-3 rounded-lg bg-purple-50 p-3 dark:bg-purple-900/10">
                  <svg class="size-5 shrink-0 text-purple-600 dark:text-purple-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
                  </svg>
                  <div class="flex-1">
                    <p class="text-sm font-medium text-purple-900 dark:text-purple-200">
                      Expires in 1 day
                    </p>
                    <p class="text-xs text-purple-700 dark:text-purple-300">
                      Secret will be deleted if not viewed within 24 hours
                    </p>
                  </div>
                </div>
              </div>
            </div>

            <!-- Important Notice -->
            <div class="rounded-lg border border-amber-200 bg-amber-50 p-3 dark:border-amber-800 dark:bg-amber-900/10">
              <div class="flex items-start gap-2">
                <svg class="size-5 shrink-0 text-amber-600 dark:text-amber-400" fill="currentColor" viewBox="0 0 20 20">
                  <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd" />
                </svg>
                <p class="text-xs text-amber-800 dark:text-amber-300">
                  <strong>Remember:</strong> Share the passphrase separately from the link for maximum security.
                </p>
              </div>
            </div>
          </div>

          <!-- Modal Footer -->
          <div class="flex gap-3 border-t border-gray-200 p-6 dark:border-gray-700">
            <button
              type="button"
              class="flex-1 rounded-lg border border-gray-300 bg-white px-4 py-2.5 text-sm font-semibold text-gray-700 transition-colors hover:bg-gray-50 dark:border-gray-600 dark:bg-slate-800 dark:text-gray-300 dark:hover:bg-slate-700">
              Go Back
            </button>
            <button
              type="button"
              class="flex-1 rounded-lg bg-blue-600 px-4 py-2.5 text-sm font-semibold text-white shadow-sm transition-all hover:bg-blue-700 hover:shadow-md focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 dark:bg-blue-500 dark:hover:bg-blue-600">
              Create Link
            </button>
          </div>
        </div>
      </div>

      <!-- Mockup Annotations -->
      <div class="rounded-lg border border-blue-200 bg-blue-50 p-4 dark:border-blue-800 dark:bg-blue-900/20">
        <h3 class="mb-2 font-semibold text-blue-900 dark:text-blue-200">Design Notes:</h3>
        <ul class="space-y-1 text-sm text-blue-800 dark:text-blue-300">
          <li>✓ Modal uses backdrop blur for depth and focus</li>
          <li>✓ Security summary uses color-coded cards for quick scanning</li>
          <li>✓ Each security measure has icon + title + explanation</li>
          <li>✓ Important notice about passphrase best practices</li>
          <li>✓ Close button for easy cancellation</li>
          <li>✓ "Go Back" option preserves form data</li>
          <li>✓ Scale-in animation for smooth appearance</li>
          <li>✓ Builds trust through transparency</li>
        </ul>
      </div>
    </div>
  </div>
</template>

<style scoped>
.mockup-container {
  @apply relative min-h-screen bg-gray-50 py-8 dark:bg-slate-950;
}

.mockup-header {
  @apply mb-6 text-center;
}

@keyframes scale-in {
  from {
    opacity: 0;
    transform: scale(0.95);
  }
  to {
    opacity: 1;
    transform: scale(1);
  }
}

.animate-scale-in {
  animation: scale-in 200ms ease-out;
}
</style>
