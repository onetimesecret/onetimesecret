<!-- src/apps/workspace/account/region/AvailableRegions.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
  import { storeToRefs } from 'pinia';
  import SettingsLayout from '@/apps/workspace/layouts/SettingsLayout.vue';
  import JurisdictionList from '@/shared/components/modals/settings/JurisdictionList.vue';
  import { useJurisdictionStore } from '@/shared/stores/jurisdictionStore';
  import { computed, onMounted } from 'vue';

  const { t } = useI18n();
  const { brand_product_name } = storeToRefs(useBootstrapStore());
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
            {{ t('web.regions.available_regions') }}
          </h2>
          <p class="mt-1 text-sm text-gray-600 dark:text-gray-400">
            {{ t('web.regions.explore_other_regions') }}
          </p>
        </div>

        <div class="p-6">
          <JurisdictionList
            :jurisdictions="jurisdictions"
            :current-jurisdiction="currentJurisdiction" />
        </div>
      </section>

      <!-- Changing Regions Guidance -->
      <section
        class="rounded-lg border border-amber-200 bg-amber-50 dark:border-amber-800/50 dark:bg-amber-900/20">
        <div class="border-b border-amber-200 px-6 py-4 dark:border-amber-800/50">
          <h2 class="text-lg font-semibold text-amber-900 dark:text-amber-200">
            {{ t('web.regions.changing_regions_title') }}
          </h2>
        </div>

        <div class="space-y-4 p-6">
          <p class="text-sm text-amber-800 dark:text-amber-300">
            {{ t('web.regions.changing_regions_description') }}
          </p>

          <div class="rounded-md bg-white/60 p-4 dark:bg-gray-800/40">
            <p class="text-sm font-medium text-gray-900 dark:text-gray-100">
              {{ t('web.regions.changing_regions_how_to') }}
            </p>
            <p class="mt-2 text-sm text-gray-600 dark:text-gray-400">
              {{ t('web.regions.changing_regions_billing_note', { product_name: brand_product_name }) }}
            </p>
          </div>

          <p class="text-sm text-amber-700 dark:text-amber-400">
            {{ t('web.regions.changing_regions_subscription_note') }}
          </p>
        </div>
      </section>
    </div>
  </SettingsLayout>
</template>
