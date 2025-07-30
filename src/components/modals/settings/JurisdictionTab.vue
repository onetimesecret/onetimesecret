<script setup lang="ts">
import { WindowService } from '@/services/window.service';
import { useJurisdictionStore } from '@/stores/jurisdictionStore';
import OIcon from '@/components/icons/OIcon.vue';
import { computed } from 'vue';

import JurisdictionInfo from './JurisdictionInfo.vue';
import JurisdictionList from './JurisdictionList.vue';

const cust = WindowService.get('cust');

const jurisdictionStore = useJurisdictionStore();
const currentJurisdiction = computed(() => jurisdictionStore.getCurrentJurisdiction);
const jurisdictions = computed(() => jurisdictionStore.getAllJurisdictions);
const customerId = computed(() => cust?.custid);
</script>

<template>
  <div class="mx-auto max-w-4xl space-y-8 px-4 sm:px-6">
    <!-- Data Region Section -->
    <section
      class="space-y-4 border-b border-gray-200 pb-6 dark:border-gray-700"
      aria-labelledby="data-region-heading">
      <h3
        id="data-region-heading"
        class="text-lg font-semibold text-gray-900 dark:text-white">
        {{ $t('data-region') }}
      </h3>
      <div class="rounded-lg bg-gray-50 p-4 dark:bg-gray-800 sm:p-6">
        <div class="flex flex-col items-center gap-4 sm:flex-row sm:gap-6">
          <div class="flex size-16 shrink-0 items-center justify-center rounded-full bg-brand-100 dark:bg-brand-900/30">
            <OIcon
              v-if="currentJurisdiction?.icon"
              :collection="currentJurisdiction?.icon.collection"
              :name="currentJurisdiction?.icon.name"
              class="size-8 text-brand-600 dark:text-brand-400 sm:size-10"
              aria-hidden="true"
            />
          </div>
          <div class="space-y-1 text-center sm:text-left">
            <div class="text-base font-medium text-gray-900 dark:text-white">
              {{ currentJurisdiction?.display_name }}
            </div>
            <div class="text-sm text-gray-500 dark:text-gray-400">
              {{ $t('data-center-location-currentjurisdiction-identif', [currentJurisdiction?.identifier]) }}
            </div>
          </div>
        </div>
      </div>
    </section>

    <!-- Jurisdiction Section -->
    <section
      class="space-y-6"
      aria-labelledby="jurisdiction-heading">
      <header class="space-y-1">
        <h3
          id="jurisdiction-heading"
          class="text-lg font-semibold text-gray-900 dark:text-white">
          {{ $t('jurisdiction') }}
        </h3>
        <p
          v-if="customerId"
          class="text-sm text-gray-500 dark:text-gray-400">
          {{ $t('account-id-customerid') }}: {{ customerId }}
        </p>
      </header>

      <!-- Info Card -->
      <div class="prose prose-base max-w-none rounded-lg bg-gray-50 p-4 dark:prose-invert dark:bg-gray-800 sm:p-6">
        <div class="space-y-4">
          <JurisdictionInfo
            v-if="currentJurisdiction"
            :jurisdiction="currentJurisdiction"
          />
        </div>
      </div>

      <!-- Jurisdiction List -->
      <div class="space-y-3">
        <h4 class="text-sm font-medium text-gray-700 dark:text-gray-300">
          {{ $t('available-regions') }}
        </h4>

        <JurisdictionList
          :jurisdictions="jurisdictions"
          :currentJurisdiction="currentJurisdiction"
        />
      </div>
    </section>
  </div>
</template>
