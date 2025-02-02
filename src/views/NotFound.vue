<script setup lang="ts">
import ThemeToggle from '@/components/ThemeToggle.vue';

// No additional script needed for this component
</script>


<template>
  <div>
    <div class="flex min-h-screen flex-col items-center bg-gray-100 px-4 dark:bg-gray-900 sm:px-6 lg:px-8">
      <div class="flex grow items-center justify-center">
        <div class="w-full max-w-md rounded-lg bg-white p-8 shadow-md dark:bg-gray-800">
          <!-- Added relative and pb-20 -->
          <div class="mb-8 text-center">
            <svg
              class="mx-auto size-20 text-brand-500"
              width="60"
              height="60"
              viewBox="0 0 24 24"
              fill="none"
              xmlns="http://www.w3.org/2000/svg"
              aria-hidden="true">
              <path
                d="M10 14L12 12M12 12L14 10M12 12L10 10M12 12L14 14M21 12C21 16.9706 16.9706 21 12 21C7.02944 21 3 16.9706 3 12C3 7.02944 7.02944 3 12 3C16.9706 3 21 7.02944 21 12Z"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
              />
            </svg>
          </div>
          <h1
            class="mb-6 text-center text-3xl font-bold text-gray-800 dark:text-white"
            :aria-label="$t('404-page-not-found')">
            {{ $t('404-page-not-found-0') }}
          </h1>
          <p class="mb-20 text-center text-lg text-gray-600 dark:text-gray-300">
            {{ $t('oops-the-page-you-are-looking-for-doesnt-exist-o') }}
          </p>

          <div class="text-center">
            <router-link
              to="/"
              class="inline-block rounded-lg border-2 border-brand-500 bg-white px-6 py-3 font-brand
              text-lg font-medium text-brand-500
              transition
              duration-300 ease-in-out hover:bg-gray-100
              dark:border-brand-400
              dark:bg-gray-700 dark:text-brand-400 dark:hover:bg-gray-600"
              aria-label="$t('return-to-home-page')">
              {{ $t('return-home') }}
            </router-link>
          </div>
        </div>
      </div>

      <!-- Move ThemeToggle here and style it -->
      <div class="pb-8">
        <ThemeToggle />
      </div>
    </div>
  </div>
</template>
