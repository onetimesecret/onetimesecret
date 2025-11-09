<!-- src/views/account/settings/PrivacySettings.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import OIcon from '@/components/icons/OIcon.vue';
  import SettingsLayout from '@/components/layout/SettingsLayout.vue';

  const { t } = useI18n();
</script>

<template>
  <SettingsLayout>
    <div class="space-y-8">
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
                {{ t('web.settings.privacy.title') }}
              </h2>
              <p class="mt-1 text-sm leading-tight text-gray-600 dark:text-gray-400">
                {{ t('web.settings.privacy.manage-privacy-settings') }}
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
                    {{ t('web.settings.privacy.your-privacy') }}
                  </p>
                  <span
                    class="inline-flex items-center rounded-full bg-green-100 px-2.5 py-0.5 text-xs font-medium text-green-800 dark:bg-green-900/30 dark:text-green-400">
                    {{ t('web.settings.privacy.non-negotiable') }}
                  </span>
                </div>
                <p class="text-sm font-medium text-gray-700 dark:text-gray-300">
                  {{ t('web.settings.privacy.no-analytics-statement') }}
                </p>
                <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
                  {{ t('web.settings.privacy.explanation') }}
                </p>
              </div>

              <!-- Disabled Toggle (in "on" position) -->
              <div
                role="switch"
                aria-checked="true"
                aria-disabled="true"
                aria-label="Privacy protection is always enabled"
                class="relative inline-flex h-6 w-11 shrink-0 cursor-not-allowed rounded-full border-2 border-transparent bg-green-600 opacity-50 dark:bg-green-500">
                <span
                  aria-hidden="true"
                  class="pointer-events-none inline-block size-5 translate-x-5 transform rounded-full bg-white shadow ring-0"></span>
              </div>
            </div>
          </div>
        </div>
      </section>
    </div>
  </SettingsLayout>
</template>
