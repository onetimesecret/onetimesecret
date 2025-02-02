<script setup lang="ts">
import FeedbackForm from '@/components/FeedbackForm.vue';

</script>

<template>
  <section
    class="mb-8"
    aria-labelledby="feedback-section-title">
    <h3
      id="feedback-section-title"
      lass="text-2xl font-semibold mb-4 text-gray-900 dark:text-gray-100">
      {{ $t('share-your-feedback') }}
    </h3>

    <FeedbackForm :show-red-button="true" />

    <!-- Founder's Message -->
    <div
      class="my-4 overflow-hidden rounded-lg bg-white shadow-md dark:bg-gray-800"
      role="complementary"
      aria-labelledby="founders-message">
      <div class="p-6">
        <h2
          id="founders-message"
          class="mb-4 text-xl font-semibold text-gray-800 dark:text-gray-200">
          {{ $t('a-note-from-delano-founder-of-onetime-secret') }}
        </h2>
        <div class="space-y-3 text-gray-600 dark:text-gray-400">
          <p>
            {{ $t('hey-there-thanks-for-stopping-by-our-feedback-pa') }}
          </p>
          <p>
            {{ $t('weve-built-this-tool-to-help-you-share-sensitive') }}
          </p>
          <p>
            {{ $t('thanks-for-helping-onetime-secret-improve-it-mea') }}
          </p>
          <p class="font-medium">
            - {{ $t('delano') }}
          </p>
        </div>
      </div>
    </div>
  </section>
</template>
