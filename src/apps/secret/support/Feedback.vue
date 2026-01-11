<!-- src/apps/secret/support/Feedback.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
import FeedbackForm from '@/apps/secret/components/support/FeedbackForm.vue';

const { t } = useI18n();

</script>

<template>
  <div class="container mx-auto max-w-2xl px-4 py-8">
    <section aria-labelledby="feedback-section-title">
    <h1
      id="feedback-section-title"
      class="mb-6 text-2xl font-semibold text-gray-900 dark:text-gray-100">
      {{ t('web.feedback.share_your_feedback') }}
    </h1>

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
          {{ t('web.feedback.a_note_from_delano_founder_of_onetime_secret') }}
        </h2>
        <div class="space-y-3 text-gray-600 dark:text-gray-400">
          <p>
            {{ t('web.feedback.hey_there_thanks_for_stopping_by_our_feedback_pa') }}
          </p>
          <p>
            {{ t('web.feedback.weve_built_this_tool_to_help_you_share_sensitive') }}
          </p>
          <p>
            {{ t('web.feedback.thanks_for_helping_onetime_secret_improve_it_mea') }}
          </p>
          <p class="font-medium">
            - {{ t('web.feedback.delano') }}
          </p>
        </div>
      </div>
    </div>
    </section>
  </div>
</template>
