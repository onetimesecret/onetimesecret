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
  </section>
</template>
