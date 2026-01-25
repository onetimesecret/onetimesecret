<!-- src/apps/workspace/account/AccountSettings.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import SettingsLayout from '@/apps/workspace/layouts/SettingsLayout.vue';
  import { computed } from 'vue';
  import { useRoute } from 'vue-router';
  import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
  import { storeToRefs } from 'pinia';

  const { t } = useI18n();
  const route = useRoute();

  // Check if billing is enabled
  const bootstrapStore = useBootstrapStore();
  const { billing_enabled } = storeToRefs(bootstrapStore);
  const billingEnabled = computed(() => billing_enabled.value === true);

  // Base tabs always shown
  const baseTabs = [
    {
      name: 'password',
      label: 'web.auth.change_password.title',
      path: '/account/settings/password',
    },
    {
      name: 'close',
      label: 'web.auth.close_account.title',
      path: '/account/settings/close',
    },
  ];

  // Billing tab only shown when enabled
  const billingTab = {
    name: 'billing',
    label: 'web.nav.settings.billing',
    path: '/billing/overview',
  };

  // Computed tabs list - inserts billing before 'close' when enabled
  const tabs = computed(() => {
    if (!billingEnabled.value) {
      return baseTabs;
    }

    // Insert billing tab before 'close' (robust to baseTabs reordering)
    const newTabs = [...baseTabs];
    const closeIndex = newTabs.findIndex((tab) => tab.name === 'close');
    newTabs.splice(closeIndex !== -1 ? closeIndex : newTabs.length, 0, billingTab);
    return newTabs;
  });
</script>

<template>
  <SettingsLayout>
    <div class="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
      <div class="mb-8">
        <h1 class="text-3xl font-bold text-gray-900 dark:text-white">
          {{ t('web.account.settings') }}
        </h1>
      </div>

      <div class="mb-6">
        <div class="border-b border-gray-200 dark:border-gray-700">
          <nav
            class="-mb-px flex space-x-8"
            aria-label="Tabs">
            <router-link
              v-for="tab in tabs"
              :key="tab.name"
              :to="tab.path"
              class="whitespace-nowrap border-b-2 px-1 py-4 text-sm font-medium"
              :class="[
                route.path.includes(tab.name)
                  ? 'border-brand-500 text-brand-600 dark:border-brand-400 dark:text-brand-400'
                  : 'border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700 dark:text-gray-400 dark:hover:border-gray-600 dark:hover:text-gray-300',
              ]">
              {{ t(tab.label) }}
            </router-link>
          </nav>
        </div>
      </div>

      <div class="mt-6">
        <router-view />
      </div>
    </div>
  </SettingsLayout>
</template>
