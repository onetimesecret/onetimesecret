<!-- src/apps/secret/support/Feedback.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import { useRoute } from 'vue-router';
  import { computed } from 'vue';
  import FeedbackForm from '@/apps/secret/components/support/FeedbackForm.vue';

  const { t } = useI18n();
  const route = useRoute();

  const reason = computed(
    () => (route.query.reason as string) || ''
  );
</script>

<template>
  <div class="container mx-auto max-w-2xl px-4 py-8">
    <section aria-labelledby="feedback-section-title">
    <h1
      id="feedback-section-title"
      class="mb-6 text-2xl font-semibold text-gray-900 dark:text-gray-100">
      {{ t('web.feedback.share_your_feedback') }}
    </h1>

    <FeedbackForm :show-red-button="true" :reason="reason" />

    <!-- Founder's Message -->
    <div
      class="my-4 overflow-hidden rounded-lg bg-white shadow-md dark:bg-gray-800"
      role="complementary"
      aria-labelledby="founders-message">
      <div class="p-6">
        <div class="border-l-4 border-brand-500 pl-4 space-y-3 text-gray-500 dark:text-gray-400 italic">
          <p>
            {{ t('web.feedback.founder_note_line1') }}
          </p>
          <p>
            {{ t('web.feedback.founder_note_line2') }}
          </p>
          <p class="font-medium not-italic text-gray-700 dark:text-gray-300">
            — {{ t('web.feedback.delano') }}
          </p>
        </div>
      </div>
    </div>
    </section>
  </div>
</template>
