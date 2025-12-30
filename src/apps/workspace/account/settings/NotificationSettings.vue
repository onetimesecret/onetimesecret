<!-- src/apps/workspace/account/settings/NotificationSettings.vue -->

<script setup lang="ts">
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import SettingsLayout from '@/apps/workspace/layouts/SettingsLayout.vue';
  import { useAccountStore } from '@/shared/stores/accountStore';
  import { computed, onMounted, ref } from 'vue';
  import { useI18n } from 'vue-i18n';

  const { t } = useI18n();
  const accountStore = useAccountStore();

  const isLoading = ref(false);
  const error = ref<string | null>(null);

  const notifyOnReveal = computed(() => accountStore.account?.cust?.notify_on_reveal ?? false);

  const handleToggleNotifyOnReveal = async () => {
    isLoading.value = true;
    error.value = null;

    try {
      await accountStore.updateNotificationPreference('notify_on_reveal', !notifyOnReveal.value);
    } catch (err) {
      console.error('Error updating notification preference:', err);
      error.value = t('web.settings.notifications.error_updating');
    } finally {
      isLoading.value = false;
    }
  };

  onMounted(async () => {
    await accountStore.fetch();
  });
</script>

<template>
  <SettingsLayout>
    <div class="space-y-8">
      <!-- Error Alert -->
      <div
        v-if="error"
        class="rounded-lg border border-red-200 bg-red-50 p-4 dark:border-red-800 dark:bg-red-900/20">
        <div class="flex items-center gap-2">
          <OIcon
            collection="heroicons"
            name="exclamation-triangle-solid"
            class="size-5 text-red-500"
            aria-hidden="true" />
          <p class="text-sm text-red-700 dark:text-red-300">{{ error }}</p>
        </div>
      </div>

      <!-- Notification Settings -->
      <section
        class="rounded-lg border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
        <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
          <div class="flex items-start gap-3">
            <OIcon
              collection="heroicons"
              name="bell-solid"
              class="mt-0.5 size-5 shrink-0 text-gray-500 dark:text-gray-400"
              aria-hidden="true" />
            <div class="min-w-0 flex-1">
              <h2 class="text-lg font-semibold leading-tight text-gray-900 dark:text-white">
                {{ t('web.settings.notifications.title') }}
              </h2>
              <p class="mt-1 text-sm leading-tight text-gray-600 dark:text-gray-400">
                {{ t('web.settings.notifications.description') }}
              </p>
            </div>
          </div>
        </div>

        <div class="divide-y divide-gray-200 dark:divide-gray-700">
          <!-- Secret Reveal Notifications -->
          <div class="px-6 py-4">
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-3">
                <OIcon
                  collection="heroicons"
                  name="eye-solid"
                  class="size-5 text-gray-500 dark:text-gray-400"
                  aria-hidden="true" />
                <div>
                  <p class="font-medium text-gray-900 dark:text-white">
                    {{ t('web.settings.notifications.reveal_notifications.title') }}
                  </p>
                  <p class="text-sm text-gray-500 dark:text-gray-400">
                    {{ t('web.settings.notifications.reveal_notifications.description') }}
                  </p>
                </div>
              </div>

              <!-- Toggle Switch -->
              <button
                type="button"
                role="switch"
                :aria-checked="notifyOnReveal"
                :disabled="isLoading"
                @click="handleToggleNotifyOnReveal"
                :class="[
                  notifyOnReveal
                    ? 'bg-brand-600 dark:bg-brand-500'
                    : 'bg-gray-200 dark:bg-gray-700',
                  'relative inline-flex h-6 w-11 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50',
                ]"
                :aria-busy="isLoading">
                <span
                  aria-hidden="true"
                  :class="[
                    notifyOnReveal ? 'translate-x-5' : 'translate-x-0',
                    'pointer-events-none inline-block size-5 rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out',
                  ]" ></span>
              </button>
            </div>

            <!-- Help text -->
            <p class="mt-3 text-xs text-gray-500 dark:text-gray-500">
              {{ t('web.settings.notifications.reveal_notifications.help') }}
            </p>
          </div>
        </div>
      </section>

      <!-- Info Box -->
      <section
        class="rounded-lg border border-blue-200 bg-blue-50 p-4 dark:border-blue-800 dark:bg-blue-900/20">
        <div class="flex items-start gap-3">
          <OIcon
            collection="heroicons"
            name="information-circle-solid"
            class="mt-0.5 size-5 shrink-0 text-blue-500 dark:text-blue-400"
            aria-hidden="true" />
          <div class="text-sm text-blue-700 dark:text-blue-300">
            <p>{{ t('web.settings.notifications.privacy_note') }}</p>
          </div>
        </div>
      </section>
    </div>
  </SettingsLayout>
</template>
