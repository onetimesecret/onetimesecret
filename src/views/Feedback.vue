<script setup lang="ts">
import FeedbackForm from '@/components/FeedbackForm.vue';

</script>

<template>
  <section class="mb-8">
    <h3 class="text-2xl font-semibold mb-4 text-gray-900 dark:text-gray-100"
        aria-label="Feedback Form">
        Give us your feedback
    </h3>

    <FeedbackForm :showRedButton="true" />

    <div class="container">
      <!-- New section for founder's message -->
      <div class="mb-6 bg-gray-50 dark:bg-gray-800 p-6 rounded-lg border border-gray-200 dark:border-gray-700">
        <h2 class="text-xl font-semibold mb-3 text-gray-800 dark:text-gray-200">A Note from Delano, Founder of Onetime Secret</h2>
        <p class="text-gray-600 dark:text-gray-400 mb-3">
          Hey there, thanks for stopping by our feedback page. Your input isn't just welcome - it's crucial.
        </p>
        <p class="text-gray-600 dark:text-gray-400 mb-3">
          We've built this tool to help you share sensitive info securely, and your real-world experiences are crucial for focusing our efforts. It helps us figure out what to work on next and how to make the service better for everyone.
        </p>
        <p class="text-gray-600 dark:text-gray-400">
          Thanks for helping Onetime Secret improve. It means a lot.
        </p>
        <p class="text-gray-600 dark:text-gray-400 mt-3">
          - Delano
        </p>
      </div>
    </div>

  </section>

</template>
