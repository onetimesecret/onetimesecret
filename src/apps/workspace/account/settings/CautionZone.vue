<!-- src/apps/workspace/account/settings/CautionZone.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import AccountDeleteButtonWithModalForm from '@/apps/workspace/components/account/AccountDeleteButtonWithModalForm.vue';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import SettingsLayout from '@/apps/workspace/layouts/SettingsLayout.vue';
  import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
  import { storeToRefs } from 'pinia';

  const { t } = useI18n();
  const bootstrapStore = useBootstrapStore();
  const { cust } = storeToRefs(bootstrapStore);
</script>

<template>
  <SettingsLayout>
    <div class="space-y-8">
      <!-- Caution Zone -->
      <section
        class="rounded-lg border-2 border-red-200 bg-white dark:border-red-800 dark:bg-gray-800">
        <div class="border-b-2 border-red-200 px-6 py-4 dark:border-red-800">
          <div class="flex items-center gap-3">
            <!-- no-symbol: Reserved exclusively for destructive/irreversible actions -->
            <OIcon
              collection="heroicons"
              name="no-symbol-solid"
              class="size-6 text-red-600 dark:text-red-400"
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
                  {{ t('web.auth.close_account.title') }}
                </h3>
                <p class="mt-1 text-sm text-red-700 dark:text-red-400">
                  {{ t('web.settings.delete_account.permanently_delete_your_account') }}
                </p>
              </div>
            </div>



            <AccountDeleteButtonWithModalForm
              v-if="cust"
              :cust="cust" />
          </div>
        </div>
      </section>
    </div>
  </SettingsLayout>
</template>
