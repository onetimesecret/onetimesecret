<template>
  <div class="space-y-8">
    <!-- Data Region Section -->
    <section
      class="space-y-4 pb-6 border-b border-gray-200 dark:border-gray-700"
      aria-labelledby="data-region-heading"
    >
      <h3
        id="data-region-heading"
        class="text-lg font-semibold text-gray-900 dark:text-white"
      >
        Data Region
      </h3>
      <div class="rounded-lg bg-gray-50 dark:bg-gray-800 p-6">
        <div class="flex items-center gap-6">
          <div class="h-16 w-16 flex-shrink-0 rounded-full bg-brand-100 dark:bg-brand-900/30 flex items-center justify-center">
            <Icon
              :icon="currentJurisdiction.icon"
              class="h-10 w-10 text-brand-600 dark:text-brand-400"
              aria-hidden="true"
            />
          </div>
          <div class="space-y-1">
            <div class="text-base font-medium text-gray-900 dark:text-white">
              {{ currentJurisdiction.display_name }}
            </div>
            <div class="text-sm text-gray-500 dark:text-gray-400">
              Data center location: {{ currentJurisdiction.identifier }}
            </div>
          </div>
        </div>
      </div>
    </section>

    <!-- Jurisdiction Section -->
    <section
      class="space-y-6"
      aria-labelledby="jurisdiction-heading"
    >
      <header class="space-y-1">
        <h3
          id="jurisdiction-heading"
          class="text-lg font-semibold text-gray-900 dark:text-white"
        >
          Jurisdiction
        </h3>
        <p
          v-if="customerId"
          class="text-sm text-gray-500 dark:text-gray-400"
        >
          Account ID: {{ customerId }}
        </p>
      </header>

      <!-- Info Card -->
      <div class="rounded-lg bg-gray-50 p-6 dark:bg-gray-800 prose prose-base dark:prose-invert max-w-none">
        <div class="space-y-4">
          <JurisdictionInfo
            :jurisdiction="currentJurisdiction"
            :support-host="supportHost"
          />
        </div>
      </div>

      <!-- Jurisdiction List -->
      <div class="space-y-3">
        <h4 class="text-sm font-medium text-gray-700 dark:text-gray-300">
          Available Regions
        </h4>

        <JurisdictionList
          :jurisdictions="jurisdictions"
          :current-jurisdiction="currentJurisdiction"
        />
      </div>
    </section>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue';
import { Icon } from '@iconify/vue';
import { useWindowProp } from '@/composables/useWindowProps';
import { useJurisdictionStore } from '@/stores/jurisdictionStore';
import JurisdictionInfo from './JurisdictionInfo.vue';
import JurisdictionList from './JurisdictionList.vue';

const cust = useWindowProp('cust');
const supportHost = useWindowProp('support_host');

const jurisdictionStore = useJurisdictionStore();
const currentJurisdiction = computed(() => jurisdictionStore.getCurrentJurisdiction);
const jurisdictions = computed(() => jurisdictionStore.getAllJurisdictions);
const customerId = computed(() => cust.value?.custid);
</script>
