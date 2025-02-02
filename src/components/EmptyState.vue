<!-- src/components/EmptyState.vue -->
<script setup lang="ts">
defineProps<{
  actionRoute?: string;
  actionText?: string;
}>();
</script>

<template>
  <div class="py-12 text-center">
    <div class="mx-auto flex size-12 items-center justify-center rounded-full bg-gray-100 p-3 dark:bg-gray-800">
      <svg
        xmlns="http://www.w3.org/2000/svg"
        width="64"
        height="64"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="2">
        <path d="M21 12H3M3 12V19H21V12M3 12L5 5H19L21 12" />
        <path d="M9 12V19M15 12V19" />
      </svg>
    </div>
    <h3 class="mt-4 text-lg font-medium text-gray-900 dark:text-gray-100">
      <slot name="title">
        {{ $t('web.dashboard.title_no_recent_secrets') }}
      </slot>
    </h3>
    <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
      <slot name="description">
        <div>{{ $t('web.dashboard.get-started-by-creating-your-first-secret') }}</div>
        <div>{{ $t('theyll-appear-here-once-youve-shared-them') }}</div>
      </slot>
    </p>
    <div class="mt-6">
      <slot name="actionLabel">
        <router-link
          :to="actionRoute || '/'"
          class="inline-flex items-center rounded-md border border-transparent bg-brand-600 px-4 py-2 font-brand text-base font-medium text-white shadow-sm hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:focus:ring-offset-gray-900">
          <svg
            class="mr-2 w-4 h-4"
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M12 4v16m8-8H4"
            />
          </svg>
          {{ actionText || 'Continue' }}
        </router-link>
      </slot>
    </div>
  </div>
</template>
