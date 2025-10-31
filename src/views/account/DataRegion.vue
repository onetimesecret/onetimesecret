<!-- src/views/account/DataRegion.vue -->

<script setup lang="ts">
import { computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useJurisdictionStore } from '@/stores/jurisdictionStore';
import OIcon from '@/components/icons/OIcon.vue';
import JurisdictionInfo from '@/components/modals/settings/JurisdictionInfo.vue';
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
    <div class="mx-auto max-w-4xl px-4 py-8 sm:px-6 lg:px-8">
      <!-- Page Header -->
      <div class="mb-8">
        <nav class="mb-4 flex items-center text-sm text-gray-500 dark:text-gray-400">
          <router-link
            to="/account"
            class="hover:text-gray-700 dark:hover:text-gray-200">
            {{ t('your-account') }}
          </router-link>
          <OIcon
            collection="heroicons"
            name="chevron-right-solid"
            class="mx-2 size-4"
            aria-hidden="true" />
          <span class="text-gray-900 dark:text-white">{{ t('data-region') }}</span>
        </nav>

        <div class="flex items-center gap-3 mb-4">
          <OIcon
            collection="heroicons"
            name="globe-americas-solid"
            class="size-8 text-brand-600 dark:text-brand-400"
            aria-hidden="true" />
          <h1 class="text-3xl font-bold text-gray-900 dark:text-white">
            {{ t('data-region') }}
          </h1>
        </div>
        <p class="text-lg text-gray-600 dark:text-gray-400">
          {{ t('web.regions.data-sovereignty-description') }}
        </p>
      </div>

      <div class="space-y-6">
        <!-- Data Sovereignty Notice -->
        <div
          class="rounded-lg border-2 border-blue-200 bg-blue-50 p-6 dark:border-blue-800 dark:bg-blue-900/20">
          <div class="flex gap-4">
            <OIcon
              collection="heroicons"
              name="information-circle-solid"
              class="size-6 shrink-0 text-blue-600 dark:text-blue-400"
              aria-hidden="true" />
            <div class="space-y-3 text-sm text-blue-900 dark:text-blue-100">
              <p class="font-semibold text-base">
                {{ t('web.regions.data-sovereignty-title') }}
              </p>
              <p>{{ t('web.regions.separate-environments-explanation') }}</p>
              <p>{{ t('web.regions.no-data-transfer-policy') }}</p>
              <p class="font-medium">
                {{ t('web.regions.switching-creates-new-account') }}
              </p>
            </div>
          </div>
        </div>

        <!-- Current Region -->
        <section
          class="rounded-lg border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
          <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
            <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
              {{ t('web.regions.your-current-region') }}
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
                    {{ t('web.regions.trust-title') }}
                  </p>
                  <p class="mt-1">{{ t('web.regions.trust-description') }}</p>
                </div>
              </li>
            </ul>
          </div>
        </section>
      </div>
    </div>
  </SettingsLayout>
</template>
