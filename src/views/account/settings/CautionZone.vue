<!-- src/views/account/settings/CautionZone.vue -->

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
      <!-- Caution Zone -->
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
              {{ t('web.COMMON.caution_zone') }}
            </h2>
          </div>
        </div>

        <div class="p-6">
          <div
            class="rounded-lg border border-red-200 bg-red-50 p-6 dark:border-red-800 dark:bg-red-900/20">
            <div class="mb-4 flex items-start gap-3">
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
                {{ t('web.settings.caution.deletion-warning-title') }}
              </p>
              <ul class="list-inside list-disc space-y-1 pl-4">
                <li>{{ t('web.settings.caution.deletion-warning-secrets') }}</li>
                <li>{{ t('web.settings.caution.deletion-warning-metadata') }}</li>
                <li>{{ t('web.settings.caution.deletion-warning-api-keys') }}</li>
                <li>{{ t('web.settings.caution.deletion-warning-irreversible') }}</li>
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
