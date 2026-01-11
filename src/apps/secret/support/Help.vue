<!-- src/apps/secret/support/Help.vue -->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import { RouterLink } from 'vue-router';

const { t } = useI18n();
</script>

<template>
  <div class="container mx-auto max-w-2xl px-4 py-8">
    <section aria-labelledby="help-section-title">
    <h1
      id="help-section-title"
      class="mb-6 text-2xl font-semibold text-gray-900 dark:text-gray-100">
      {{ t('web.help.title') }}
    </h1>

    <!-- Sign-in Troubleshooting -->
    <div class="space-y-6">
      <div
        class="overflow-hidden rounded-lg bg-white shadow-md dark:bg-gray-800"
        role="region"
        aria-labelledby="signin-help">
        <div class="p-6">
          <h2
            id="signin-help"
            class="mb-4 text-xl font-semibold text-gray-800 dark:text-gray-200">
            {{ t('web.help.signin_troubleshooting') }}
          </h2>
          <div class="space-y-4 text-gray-600 dark:text-gray-400">
            <div>
              <h3 class="mb-2 font-medium text-gray-800 dark:text-gray-200">
                {{ t('web.help.magic_link_not_arriving') }}
              </h3>
              <ul class="ml-4 list-disc space-y-1">
                <li>{{ t('web.help.check_spam_folder') }}</li>
                <li>{{ t('web.help.check_email_spelling') }}</li>
                <li>{{ t('web.help.wait_few_minutes') }}</li>
                <li>{{ t('web.help.try_again') }}</li>
              </ul>
            </div>

            <div>
              <h3 class="mb-2 font-medium text-gray-800 dark:text-gray-200">
                {{ t('web.help.forgot_password') }}
              </h3>
              <p>
                {{ t('web.help.use_magic_link_instead') }}
              </p>
            </div>

            <div>
              <h3 class="mb-2 font-medium text-gray-800 dark:text-gray-200">
                {{ t('web.help.account_locked') }}
              </h3>
              <p>
                {{ t('web.help.account_locked_explanation') }}
              </p>
            </div>
          </div>
        </div>
      </div>

      <!-- Contact Support -->
      <div
        class="overflow-hidden rounded-lg bg-white shadow-md dark:bg-gray-800"
        role="region"
        aria-labelledby="contact-support">
        <div class="p-6">
          <h2
            id="contact-support"
            class="mb-4 text-xl font-semibold text-gray-800 dark:text-gray-200">
            {{ t('web.help.still_need_help') }}
          </h2>
          <p class="mb-4 text-gray-600 dark:text-gray-400">
            {{ t('web.help.contact_us_description') }}
          </p>
          <RouterLink
            to="/feedback"
            class="inline-flex items-center rounded-md bg-brand-600 px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:bg-brand-600 dark:hover:bg-brand-700 dark:focus:ring-offset-gray-800">
            {{ t('web.help.contact_support') }}
          </RouterLink>
        </div>
      </div>
    </div>
    </section>
  </div>
</template>
