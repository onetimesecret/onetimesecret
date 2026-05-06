<!-- src/apps/colonel/components/ColonelFetchError.vue -->

<script setup lang="ts">
  defineProps<{
    schema: string;
    resource: string;
  }>();

  const isDev = import.meta.env.DEV;
</script>

<template>
  <div
    role="alert"
    data-testid="colonel-fetch-error"
    class="rounded-lg border border-amber-200 bg-amber-50 p-6 dark:border-amber-800 dark:bg-amber-950">
    <p class="font-medium text-amber-900 dark:text-amber-200">
      Failed to load {{ resource }}.
    </p>
    <p class="mt-2 text-sm text-amber-800 dark:text-amber-300">
      The server response did not match the expected format. The full error
      has been reported (see browser console in development, or Sentry in
      production). Please share this with your administrator.
    </p>
    <p
      v-if="isDev"
      class="mt-3 font-mono text-xs text-amber-700 dark:text-amber-400">
      [dev] Schema: {{ schema }} — full Zod issues are in the console.
    </p>
  </div>
</template>
