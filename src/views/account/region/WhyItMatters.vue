<!-- src/views/account/region/WhyItMatters.vue -->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import OIcon from '@/components/icons/OIcon.vue';
import SettingsLayout from '@/components/layout/SettingsLayout.vue';

const { t } = useI18n();
</script>

<template>
  <SettingsLayout>
    <div class="space-y-6">
      <!-- Why Data Sovereignty Matters -->
      <section
        class="rounded-lg border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
        <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
          <h2 class="flex items-center gap-2 text-lg font-semibold text-gray-900 dark:text-white">
            <OIcon
              collection="heroicons"
              name="shield-check-solid"
              class="size-5 text-brand-600 dark:text-brand-400"
              aria-hidden="true" />
            {{ t('web.regions.why-it-matters') }}
          </h2>
        </div>

        <div class="p-6">
          <ul class="space-y-4 text-sm text-gray-600 dark:text-gray-400">
            <li class="flex gap-3">
              <OIcon
                collection="heroicons"
                name="check-circle-solid"
                class="size-5 shrink-0 text-green-600 dark:text-green-400"
                aria-hidden="true" />
              <div>
                <p class="font-medium text-gray-900 dark:text-white">
                  {{ t('web.regions.trust-title') }}
                </p>
                <p class="mt-1">{{ t('web.regions.trust-description') }}</p>
              </div>
            </li>
            <li class="flex gap-3">
              <OIcon
                collection="heroicons"
                name="check-circle-solid"
                class="size-5 shrink-0 text-green-600 dark:text-green-400"
                aria-hidden="true" />
              <div>
                <p class="font-medium text-gray-900 dark:text-white">
                  {{ t('web.regions.privacy-title') }}
                </p>
                <p class="mt-1">{{ t('web.regions.privacy-description') }}</p>
              </div>
            </li>
            <li class="flex gap-3">
              <OIcon
                collection="heroicons"
                name="check-circle-solid"
                class="size-5 shrink-0 text-green-600 dark:text-green-400"
                aria-hidden="true" />
              <div>
                <p class="font-medium text-gray-900 dark:text-white">
                  {{ t('web.regions.compliance-title') }}
                </p>
                <p class="mt-1">{{ t('web.regions.compliance-description') }}</p>
              </div>
            </li>
            <li class="flex gap-3">
              <OIcon
                collection="heroicons"
                name="check-circle-solid"
                class="size-5 shrink-0 text-green-600 dark:text-green-400"
                aria-hidden="true" />
              <div>
                <p class="font-medium text-gray-900 dark:text-white">
                  {{ t('web.regions.performance-title') }}
                </p>
                <p class="mt-1">{{ t('web.regions.performance-description') }}</p>
              </div>
            </li>
          </ul>
        </div>
      </section>
    </div>
  </SettingsLayout>
</template>
