<!-- src/apps/workspace/account/settings/ApiSettings.vue -->

<script setup lang="ts">
  import APIKeyForm from '@/apps/workspace/components/account/APIKeyForm.vue';
  import SettingsLayout from '@/apps/workspace/layouts/SettingsLayout.vue';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import CopyButton from '@/shared/components/ui/CopyButton.vue';
  import { useAccountStore } from '@/shared/stores/accountStore';
  import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
  import { storeToRefs } from 'pinia';
  import { computed, onMounted } from 'vue';
  import { useI18n } from 'vue-i18n';

  const { t } = useI18n();
  const accountStore = useAccountStore();
  const { account } = storeToRefs(accountStore);
  const bootstrapStore = useBootstrapStore();
  const apiConfig = bootstrapStore.apiConfig;

  // Customer external ID (ur… prefix). This — or the account email — is the
  // only username HTTP Basic auth accepts (Customer.load_by_extid_or_email);
  // org extids and internal UUIDs silently fail to authenticate.
  const customerExtid = computed(() => account.value?.cust?.extid ?? '');

  onMounted(async () => {
    await accountStore.fetch();
  });
</script>

<template>
  <SettingsLayout>
    <div
      v-if="!apiConfig.enabled"
      class="rounded-lg bg-gray-50 p-6 text-center dark:bg-gray-800/60">
      <OIcon
        collection="heroicons"
        name="x-circle-solid"
        class="mx-auto mb-3 size-8 text-gray-400 dark:text-gray-500"
        aria-hidden="true" />
      <p class="text-sm text-gray-600 dark:text-gray-400">
        {{ t('web.settings.api.api_disabled_notice') }}
      </p>
    </div>

    <div
      v-else
      class="space-y-8">
      <!-- API Key Section -->
      <section
        class="rounded-lg border border-gray-200/60 bg-white/60 shadow-sm backdrop-blur-sm dark:border-gray-700/60 dark:bg-gray-800/60">
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

      <!-- API Username Section -->
      <section
        data-testid="api-username-section"
        class="rounded-lg border border-gray-200/60 bg-white/60 shadow-sm backdrop-blur-sm dark:border-gray-700/60 dark:bg-gray-800/60">
        <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
          <div class="flex items-center gap-3">
            <OIcon
              collection="heroicons"
              name="identification"
              class="size-5 text-gray-500 dark:text-gray-400"
              aria-hidden="true" />
            <div>
              <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
                {{ t('web.settings.api.api_username') }}
              </h2>
              <p class="text-sm text-gray-600 dark:text-gray-400">
                {{ t('web.settings.api.api_username_description') }}
              </p>
            </div>
          </div>
        </div>

        <div class="p-6">
          <div
            v-if="customerExtid"
            data-testid="api-username-field"
            class="font-mono text-sm text-gray-800 dark:text-gray-200">
            <div
              class="relative flex items-center overflow-x-auto rounded-md border border-gray-200 bg-gray-50 p-3 dark:border-gray-600 dark:bg-gray-900/50">
              <span class="pr-10 break-all">{{ customerExtid }}</span>
              <div class="absolute top-1/2 right-2 -translate-y-1/2">
                <CopyButton
                  :text="customerExtid"
                  testid="api-username-copy" />
              </div>
            </div>
          </div>
          <p class="mt-2 text-xs font-medium text-gray-500 dark:text-gray-400">
            {{ t('web.settings.api.basic_auth_hint') }}
          </p>
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
