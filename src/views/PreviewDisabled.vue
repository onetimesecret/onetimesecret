<!-- src/views/PreviewDisabled.vue -->

<script setup lang="ts">
  import DisabledHomepage from '@/apps/secret/views/DisabledHomepage.vue';
  import { ref } from 'vue';

  const expanded = ref(false);
</script>

<template>
  <div>
    <div
      role="status"
      data-testid="preview-disabled-notice"
      class="border-b border-amber-300 bg-amber-50 px-4 py-2 text-sm
        text-amber-900 dark:border-amber-700 dark:bg-amber-950
        dark:text-amber-100">
      <div class="container mx-auto flex max-w-3xl items-start gap-3">
        <svg
          class="mt-0.5 size-4 flex-shrink-0"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          viewBox="0 0 24 24"
          aria-hidden="true">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M12 9v3.75m9-.75a9 9 0 11-18 0 9 9 0 0118 0zm-9 3.75h.008v.008H12v-.008z" />
        </svg>
        <div class="flex-1">
          <button
            type="button"
            :aria-expanded="expanded"
            aria-controls="preview-disabled-details"
            class="flex w-full items-center justify-between gap-2 text-left font-semibold
              hover:underline focus:outline-none focus:ring-2 focus:ring-amber-500"
            @click="expanded = !expanded">
            <span>Preview — not the real disabled screen</span>
            <span class="text-xs font-normal opacity-75">
              {{ expanded ? 'Hide' : 'Read more' }}
              <span aria-hidden="true">{{ expanded ? '▴' : '▾' }}</span>
            </span>
          </button>
          <p
            v-if="expanded"
            id="preview-disabled-details"
            class="mt-1">
            This route renders the disabled-homepage view with the live masthead so
            operators can verify branding env vars (BRAND_LOGO_URL, LOGO_SHOW_NAME,
            BRAND_PRODUCT_NAME, LOGO_PROMINENT) without changing backend settings.
            The site is fully operational.
          </p>
        </div>
      </div>
    </div>

    <DisabledHomepage />
  </div>
</template>
