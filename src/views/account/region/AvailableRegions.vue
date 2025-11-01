<!-- src/views/account/region/AvailableRegions.vue -->

<script setup lang="ts">
import { computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useJurisdictionStore } from '@/stores/jurisdictionStore';
import JurisdictionList from '@/components/modals/settings/JurisdictionList.vue';
import SettingsLayout from '@/components/layout/SettingsLayout.vue';

const { t } = useI18n();
const jurisdictionStore = useJurisdictionStore();

const currentJurisdiction = computed(() => jurisdictionStore.getCurrentJurisdiction);
const jurisdictions = computed(() => jurisdictionStore.getAllJurisdictions);

onMounted(async () => {
  jurisdictionStore.init();
});
</script>

<template>
  <SettingsLayout>
    <div class="space-y-6">
      <!-- Available Regions -->
      <section
        class="rounded-lg border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
        <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
          <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
            {{ t('available-regions') }}
          </h2>
          <p class="mt-1 text-sm text-gray-600 dark:text-gray-400">
            {{ t('web.regions.explore-other-regions') }}
          </p>
        </div>

        <div class="p-6">
          <JurisdictionList
            :jurisdictions="jurisdictions"
            :currentJurisdiction="currentJurisdiction" />
        </div>
      </section>
    </div>
  </SettingsLayout>
</template>
