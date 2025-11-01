<!-- src/views/account/region/CurrentRegion.vue -->

<script setup lang="ts">
import { computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useJurisdictionStore } from '@/stores/jurisdictionStore';
import OIcon from '@/components/icons/OIcon.vue';
import JurisdictionInfo from '@/components/modals/settings/JurisdictionInfo.vue';
import SettingsLayout from '@/components/layout/SettingsLayout.vue';

const { t } = useI18n();
const jurisdictionStore = useJurisdictionStore();

const currentJurisdiction = computed(() => jurisdictionStore.getCurrentJurisdiction);

onMounted(async () => {
  jurisdictionStore.init();
});
</script>

<template>
  <SettingsLayout>
    <div class="space-y-6">
      <!-- Current Region -->
      <section
        class="rounded-lg border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
        <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
          <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
            {{ t('web.regions.your-region') }}
          </h2>
        </div>

        <div class="p-6">
          <div
            class="rounded-lg border-2 border-brand-200 bg-brand-50 p-6 dark:border-brand-800 dark:bg-brand-900/20">
            <div class="flex items-center gap-4">
              <div
                class="flex size-16 shrink-0 items-center justify-center rounded-full bg-brand-100 dark:bg-brand-900/30">
                <OIcon
                  v-if="currentJurisdiction?.icon"
                  :collection="currentJurisdiction.icon.collection"
                  :name="currentJurisdiction.icon.name"
                  class="size-8 text-brand-600 dark:text-brand-400"
                  aria-hidden="true" />
              </div>
              <div class="flex-1">
                <p class="text-xl font-semibold text-gray-900 dark:text-white">
                  {{ currentJurisdiction?.display_name }}
                </p>
                <p class="mt-1 text-sm text-gray-600 dark:text-gray-400">
                  {{
                    t('data-center-location-currentjurisdiction-identif', [
                      currentJurisdiction?.identifier,
                    ])
                  }}
                </p>
              </div>
              <div
                class="rounded-full bg-green-100 px-3 py-1 text-sm font-medium text-green-800 dark:bg-green-900/30 dark:text-green-400">
                {{ t('web.regions.active') }}
              </div>
            </div>
          </div>

          <!-- Jurisdiction Details -->
          <div v-if="currentJurisdiction" class="mt-6">
            <JurisdictionInfo :jurisdiction="currentJurisdiction" />
          </div>
        </div>
      </section>
    </div>
  </SettingsLayout>
</template>
