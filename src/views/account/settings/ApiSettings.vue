<!-- src/views/account/settings/ApiSettings.vue -->

<script setup lang="ts">
import { onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccountStore } from '@/stores/accountStore';
import { storeToRefs } from 'pinia';
import OIcon from '@/components/icons/OIcon.vue';
import APIKeyForm from '@/components/account/APIKeyForm.vue';
import SettingsLayout from '@/components/layout/SettingsLayout.vue';

const { t } = useI18n();
const accountStore = useAccountStore();
const { account } = storeToRefs(accountStore);

onMounted(async () => {
  await accountStore.fetch();
});
</script>

<template>
  <SettingsLayout>
    <div class="space-y-8">
    <!-- API Key Section -->
    <section
      class="rounded-lg border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
      <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
        <div class="flex items-center gap-3">
          <OIcon
            collection="heroicons"
            name="key-solid"
            class="size-5 text-gray-500 dark:text-gray-400"
            aria-hidden="true" />
          <div>
            <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
              {{ t('api-key') }}
            </h2>
            <p class="text-sm text-gray-600 dark:text-gray-400">
              {{ t('web.settings.api.manage_api_keys') }}
            </p>
          </div>
        </div>
      </div>

      <div class="p-6">
        <APIKeyForm :apitoken="account?.apitoken" />
      </div>
    </section>

    <!-- API Documentation -->
    <section
      class="rounded-lg border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
      <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
        <div class="flex items-center gap-3">
          <OIcon
            collection="heroicons"
            name="book-open-solid"
            class="size-5 text-gray-500 dark:text-gray-400"
            aria-hidden="true" />
          <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
            {{ t('web.settings.api.documentation') }}
          </h2>
        </div>
      </div>

      <div class="p-6">
        <p class="mb-4 text-sm text-gray-600 dark:text-gray-400">
          {{ t('web.settings.api.documentation-description') }}
        </p>

        <div class="space-y-3">
          <a
            href="/docs/api"
            target="_blank"
            rel="noopener noreferrer"
            class="flex items-center justify-between rounded-lg border border-gray-200 p-4 transition-colors hover:bg-gray-50 dark:border-gray-700 dark:hover:bg-gray-700">
            <div class="flex items-center gap-3">
              <OIcon
                collection="heroicons"
                name="document-text-solid"
                class="size-5 text-gray-400 dark:text-gray-500"
                aria-hidden="true" />
              <div>
                <p class="font-medium text-gray-900 dark:text-white">
                  {{ t('web.settings.api.rest-api-reference') }}
                </p>
                <p class="text-sm text-gray-500 dark:text-gray-400">
                  {{ t('web.settings.api.complete-api-documentation') }}
                </p>
              </div>
            </div>
            <OIcon
              collection="heroicons"
              name="arrow-top-right-on-square-solid"
              class="size-5 text-gray-400 dark:text-gray-500"
              aria-hidden="true" />
          </a>

          <a
            href="https://github.com/onetimesecret/onetimesecret/tree/develop/docs/api"
            target="_blank"
            rel="noopener noreferrer"
            class="flex items-center justify-between rounded-lg border border-gray-200 p-4 transition-colors hover:bg-gray-50 dark:border-gray-700 dark:hover:bg-gray-700">
            <div class="flex items-center gap-3">
              <OIcon
                collection="heroicons"
                name="code-bracket"
                class="size-5 text-gray-400 dark:text-gray-500"
                aria-hidden="true" />
              <div>
                <p class="font-medium text-gray-900 dark:text-white">
                  {{ t('web.settings.api.code-examples') }}
                </p>
                <p class="text-sm text-gray-500 dark:text-gray-400">
                  {{ t('web.settings.api.example-code-and-libraries') }}
                </p>
              </div>
            </div>
            <OIcon
              collection="heroicons"
              name="arrow-top-right-on-square-solid"
              class="size-5 text-gray-400 dark:text-gray-500"
              aria-hidden="true" />
          </a>
        </div>
      </div>
    </section>

    <!-- API Best Practices -->
    <section
      class="rounded-lg border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
      <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
        <div class="flex items-center gap-3">
          <OIcon
            collection="heroicons"
            name="shield-check-solid"
            class="size-5 text-gray-500 dark:text-gray-400"
            aria-hidden="true" />
          <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
            {{ t('web.settings.api.security-best-practices') }}
          </h2>
        </div>
      </div>

      <div class="p-6">
        <ul class="space-y-3 text-sm text-gray-600 dark:text-gray-400">
          <li class="flex gap-3">
            <OIcon
              collection="heroicons"
              name="check-circle-solid"
              class="size-5 shrink-0 text-green-600 dark:text-green-400"
              aria-hidden="true" />
            {{ t('web.settings.api.never-commit-api-keys') }}
          </li>
          <li class="flex gap-3">
            <OIcon
              collection="heroicons"
              name="check-circle-solid"
              class="size-5 shrink-0 text-green-600 dark:text-green-400"
              aria-hidden="true" />
            {{ t('web.settings.api.use-environment-variables') }}
          </li>
          <li class="flex gap-3">
            <OIcon
              collection="heroicons"
              name="check-circle-solid"
              class="size-5 shrink-0 text-green-600 dark:text-green-400"
              aria-hidden="true" />
            {{ t('web.settings.api.rotate-keys-regularly') }}
          </li>
          <li class="flex gap-3">
            <OIcon
              collection="heroicons"
              name="check-circle-solid"
              class="size-5 shrink-0 text-green-600 dark:text-green-400"
              aria-hidden="true" />
            {{ t('web.settings.api.use-https-only') }}
          </li>
          <li class="flex gap-3">
            <OIcon
              collection="heroicons"
              name="check-circle-solid"
              class="size-5 shrink-0 text-green-600 dark:text-green-400"
              aria-hidden="true" />
            {{ t('web.settings.api.monitor-api-usage') }}
          </li>
        </ul>
      </div>
    </section>

    <!-- Warning Notice -->
    <div class="rounded-lg bg-yellow-50 p-4 dark:bg-yellow-900/20">
      <div class="flex gap-3">
        <OIcon
          collection="heroicons"
          name="exclamation-triangle-solid"
          class="size-5 shrink-0 text-yellow-600 dark:text-yellow-400"
          aria-hidden="true" />
        <div class="text-sm text-yellow-800 dark:text-yellow-300">
          <p class="font-medium">{{ t('web.settings.api.important-notice') }}</p>
          <p class="mt-1">
            {{ t('web.settings.api.regenerating-key-warning') }}
          </p>
        </div>
      </div>
    </div>
    </div>
  </SettingsLayout>
</template>
