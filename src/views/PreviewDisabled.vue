<!-- src/views/PreviewDisabled.vue -->

<script setup lang="ts">
  import AccessDenied from '@/apps/secret/conceal/AccessDenied.vue';
</script>

<template>
  <div>
    <div
      role="status"
      data-testid="preview-disabled-notice"
      class="border-b border-amber-300 bg-amber-50 px-4 py-3 text-sm
        text-amber-900 dark:border-amber-700 dark:bg-amber-950
        dark:text-amber-100">
      <div class="container mx-auto flex max-w-3xl items-start gap-3">
        <svg
          class="mt-0.5 size-5 flex-shrink-0"
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
        <div>
          <p class="font-semibold">Preview — not the real disabled screen</p>
          <p class="mt-1">
            This route renders the disabled-homepage view with the live masthead so
            operators can verify branding env vars (LOGO_URL, LOGO_SHOW_NAME,
            SITE_NAME, LOGO_PROMINENT) without changing backend settings. The site
            is fully operational.
          </p>
        </div>
      </div>
    </div>

    <AccessDenied />
  </div>
</template>
