<!-- src/apps/workspace/account/settings/ApiSettings.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import APIKeyForm from '@/apps/workspace/components/account/APIKeyForm.vue';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import SettingsLayout from '@/apps/workspace/layouts/SettingsLayout.vue';
  import { useAccountStore } from '@/shared/stores/accountStore';
  import { storeToRefs } from 'pinia';
  import { onMounted } from 'vue';

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
                {{ t('web.account.api_key') }}
              </h2>
              <p class="text-sm text-gray-600 dark:text-gray-400">
                {{ t('web.settings.api.manage_api_keys') }}
              </p>
            </div>
          </div>
        </div>

        <div class="p-6">
          <APIKeyForm :apitoken="account?.apitoken ?? undefined" />
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
            <p class="font-medium">
              {{ t('web.settings.api.important_notice') }}
            </p>
            <p class="mt-1">
              {{ t('web.settings.api.regenerating_key_warning') }}
            </p>
          </div>
        </div>
      </div>
    </div>
  </SettingsLayout>
</template>
