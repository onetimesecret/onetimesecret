<template>
  <div>
    <div class="min-h-screen flex flex-col items-center bg-gray-100 dark:bg-gray-900 px-4 sm:px-6 lg:px-8">
      <div class="flex items-center justify-center flex-grow">
        <div class="max-w-md w-full bg-white dark:bg-gray-800 shadow-md rounded-lg p-8">
          <!-- Added relative and pb-20 -->
          <div class="text-center mb-8">
            <svg class="mx-auto w-20 h-20 text-brand-500"
                 width="60"
                 height="60"
                 viewBox="0 0 24 24"
                 fill="none"
                 xmlns="http://www.w3.org/2000/svg"
                 aria-hidden="true">
              <path d="M10 14L12 12M12 12L14 10M12 12L10 10M12 12L14 14M21 12C21 16.9706 16.9706 21 12 21C7.02944 21 3 16.9706 3 12C3 7.02944 7.02944 3 12 3C16.9706 3 21 7.02944 21 12Z"
                    stroke="currentColor"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round" />
            </svg>
          </div>
          <h1 class="text-3xl font-bold text-gray-800 dark:text-white mb-6 text-center"
              aria-label="404 - Page Not Found">
            404 - Page Not Found
          </h1>
          <p class="text-lg text-gray-600 dark:text-gray-300 mb-20 text-center">
            Oops! The page you are looking for doesn't exist or has been moved.
          </p>

          <div class="text-center">
            <router-link to="/"
                         class="inline-block py-3 px-6 rounded-lg border-2 text-lg font-brand font-medium
              text-brand-500 bg-white border-brand-500
              hover:bg-gray-100
              dark:text-brand-400 dark:bg-gray-700 dark:border-brand-400
              dark:hover:bg-gray-600
              transition duration-300 ease-in-out"
                         aria-label="Return to home page">
              Return home
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


<script setup lang="ts">
import ThemeToggle from '@/components/ThemeToggle.vue';

// No additional script needed for this component
</script>
