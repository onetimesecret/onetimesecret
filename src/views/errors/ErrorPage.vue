<script setup lang="ts">

</script>


<template>

  <div class="mb-8">
    <svg class="w-32 h-32 mx-auto text-red-500 dark:text-red-400"
         fill="none"
         stroke="currentColor"
         viewBox="0 0 24 24"
         xmlns="http://www.w3.org/2000/svg"
         width="128"
         height="128">
      <path stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
    </svg>
  </div>

  <h2 class="text-3xl font-bold mb-4 text-gray-800 dark:text-gray-200">
    {{ $t('web.COMMON.oops') }} Something went wrong
  </h2>

  <p class="text-lg mb-6 text-gray-600 dark:text-gray-400">
    We're sorry, but an unexpected error occurred while processing your request. Our team has been
    notified and we're working to fix it.
  </p>

  <nav class="mb-8">
    <a href="/"
       class="inline-block px-6 py-3 bg-brand-500 text-white rounded-lg hover:bg-brand-600 transition-colors duration-300 dark:bg-brand-600 dark:hover:bg-brand-700 shadow-md hover:shadow-lg">
      Return to Home
    </a>
  </nav>

</template>
