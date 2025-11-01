<!-- src/views/account/settings/AdvancedSettings.vue -->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import { WindowService } from '@/services/window.service';
import OIcon from '@/components/icons/OIcon.vue';
import AccountDeleteButtonWithModalForm from '@/components/account/AccountDeleteButtonWithModalForm.vue';
import SettingsLayout from '@/components/layout/SettingsLayout.vue';

const { t } = useI18n();
const windowProps = WindowService.getMultiple(['cust']);
</script>

<template>
  <SettingsLayout>
    <div class="space-y-8">
    <!-- Data Export -->
    <!-- <section
      class="rounded-lg border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
      <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
        <div class="flex items-center gap-3">
          <OIcon
            collection="heroicons"
            name="arrow-down-tray-solid"
            class="size-5 text-gray-500 dark:text-gray-400"
            aria-hidden="true" />
          <div>
            <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
              {{ t('web.settings.advanced.data-export') }}
            </h2>
            <p class="text-sm text-gray-600 dark:text-gray-400">
              {{ t('web.settings.advanced.export-your-data') }}
            </p>
          </div>
        </div>
      </div>

      <div class="p-6">
        <p class="mb-4 text-sm text-gray-600 dark:text-gray-400">
          {{ t('web.settings.advanced.export-description') }}
        </p>

        <button
          type="button"
          class="inline-flex items-center gap-2 rounded-lg border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 transition-colors hover:bg-gray-50 dark:border-gray-600 dark:bg-gray-700 dark:text-gray-300 dark:hover:bg-gray-600">
          <OIcon
            collection="heroicons"
            name="arrow-down-tray-solid"
            class="size-4"
            aria-hidden="true" />
          {{ t('web.settings.advanced.request-data-export') }}
        </button>

        <div class="mt-4 rounded-lg bg-blue-50 p-4 dark:bg-blue-900/20">
          <div class="flex gap-3">
            <OIcon
              collection="heroicons"
              name="information-circle-solid"
              class="size-5 shrink-0 text-blue-600 dark:text-blue-400"
              aria-hidden="true" />
            <div class="text-sm text-blue-700 dark:text-blue-300">
              <p class="font-medium">{{ t('web.settings.advanced.export-info') }}</p>
              <p class="mt-1">
                {{ t('web.settings.advanced.export-info-description') }}
              </p>
            </div>
          </div>
        </div>
      </div>
    </section> -->

    <!-- Privacy Settings -->
    <section
      class="rounded-lg border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
      <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
        <div class="flex items-start gap-3">
          <OIcon
            collection="heroicons"
            name="shield-check-solid"
            class="mt-0.5 size-5 shrink-0 text-gray-500 dark:text-gray-400"
            aria-hidden="true" />
          <div class="min-w-0 flex-1">
            <h2 class="text-lg font-semibold leading-tight text-gray-900 dark:text-white">
              {{ t('web.settings.advanced.privacy') }}
            </h2>
            <p class="mt-1 text-sm leading-tight text-gray-600 dark:text-gray-400">
              {{ t('web.settings.advanced.manage-privacy-settings') }}
            </p>
          </div>
        </div>
      </div>

      <div class="p-6">
        <div class="space-y-4">
          <!-- No Analytics Statement -->
          <div class="flex items-center justify-between">
            <div class="flex-1">
              <div class="mb-2 flex items-center gap-2">
                <p class="font-medium text-gray-900 dark:text-white">
                  {{ t('web.settings.advanced.your-privacy') }}
                </p>
                <span
                  class="inline-flex items-center rounded-full bg-green-100 px-2.5 py-0.5 text-xs font-medium text-green-800 dark:bg-green-900/30 dark:text-green-400">
                  {{ t('web.settings.advanced.non-negotiable') }}
                </span>
              </div>
              <p class="text-sm font-medium text-gray-700 dark:text-gray-300">
                {{ t('web.settings.advanced.no-analytics-statement') }}
              </p>
              <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
                {{ t('web.settings.advanced.privacy-explanation') }}
              </p>
            </div>

            <!-- Disabled Toggle -->
            <div
              role="switch"
              aria-checked="false"
              aria-disabled="true"
              aria-label="Analytics collection is always disabled"
              class="relative inline-flex h-6 w-11 shrink-0 cursor-not-allowed rounded-full border-2 border-transparent bg-gray-200 opacity-50 dark:bg-gray-700">
              <span
                aria-hidden="true"
                class="pointer-events-none inline-block size-5 translate-x-0 transform rounded-full bg-white shadow ring-0 dark:bg-gray-300" ></span>
            </div>
          </div>
        </div>
      </div>
    </section>

    <!-- Danger Zone -->
    <section
      class="rounded-lg border-2 border-red-200 bg-white dark:border-red-800 dark:bg-gray-800">
      <div class="border-b-2 border-red-200 px-6 py-4 dark:border-red-800">
        <div class="flex items-center gap-3">
          <OIcon
            collection="heroicons"
            name="exclamation-triangle-solid"
            class="size-5 text-red-600 dark:text-red-400"
            aria-hidden="true" />
          <h2 class="text-lg font-semibold text-red-600 dark:text-red-400">
            {{ t('web.COMMON.danger_zone') }}
          </h2>
        </div>
      </div>

      <div class="p-6">
        <div
          class="rounded-lg border border-red-200 bg-red-50 p-6 dark:border-red-800 dark:bg-red-900/20">
          <div class="mb-4 flex items-start gap-3">
            <OIcon
              collection="heroicons"
              name="trash-solid"
              class="size-6 shrink-0 text-red-600 dark:text-red-400"
              aria-hidden="true" />
            <div>
              <h3 class="font-semibold text-red-900 dark:text-red-300">
                {{ t('web.auth.close-account.title') }}
              </h3>
              <p class="mt-1 text-sm text-red-700 dark:text-red-400">
                {{ t('web.settings.delete_account.permanently_delete_your_account') }}
              </p>
            </div>
          </div>

          <div class="mb-6 space-y-2 text-sm text-red-700 dark:text-red-400">
            <p class="font-medium">
              {{ t('web.settings.advanced.deletion-warning-title') }}
            </p>
            <ul class="list-inside list-disc space-y-1 pl-4">
              <li>{{ t('web.settings.advanced.deletion-warning-secrets') }}</li>
              <li>{{ t('web.settings.advanced.deletion-warning-metadata') }}</li>
              <li>{{ t('web.settings.advanced.deletion-warning-api-keys') }}</li>
              <li>{{ t('web.settings.advanced.deletion-warning-irreversible') }}</li>
            </ul>
          </div>

          <AccountDeleteButtonWithModalForm
            v-if="windowProps.cust"
            :cust="windowProps.cust" />
        </div>
      </div>
    </section>
    </div>
  </SettingsLayout>
</template>
