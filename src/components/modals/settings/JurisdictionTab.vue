<template>
  <div>
    <section class="space-y-4 pb-6 border-b border-gray-200 dark:border-gray-700"
             aria-labelledby="data-region-heading">
      <h3 id="data-region-heading"
          class="text-lg font-semibold text-gray-900 dark:text-white">
        Data Region
      </h3>
      <div class="rounded-lg bg-gray-50 dark:bg-gray-800 p-4">
        <div class="flex items-center gap-4">
          <div class="flex items-center gap-2">
            <Icon icon="carbon:location-filled"
                  class="h-5 w-5 text-gray-500 dark:text-gray-400"
                  aria-hidden="true" />
            <span class="text-sm font-medium text-gray-700 dark:text-gray-300">
              Current Region
            </span>
          </div>
        </div>
      </div>
    </section>
    <section class="space-y-6"
             aria-labelledby="jurisdiction-heading">
      <header class="flex flex-col space-y-1">
        <h3 id="jurisdiction-heading"
            class="text-lg font-semibold text-gray-900 dark:text-white">
          Jurisdiction
        </h3>
        <p v-if="cust?.custid"
           class="text-sm text-gray-500 dark:text-gray-400">
          Account ID: {{ cust.custid }}
        </p>
      </header>

      <div class="rounded-lg bg-gray-50 p-6 dark:bg-gray-800 prose prose-base dark:prose-invert max-w-none">
        <div class="space-y-4">
          <div class="flex items-center gap-2">
            <Icon :icon="currentJurisdiction.icon"
                  class="h-5 w-5 flex-shrink-0"
                  aria-hidden="true" />
            <p class="text-gray-700  dark:text-gray-200 m-0">
              Your data for this account is located in the
              <strong class="font-medium">{{ currentJurisdiction.display_name }}</strong>
            </p>
          </div>

          <p class="text-gray-600 dark:text-gray-300 m-0">
            This is determined by the domain you're accessing:
            <span class="px-2 py-1 bg-gray-100 dark:bg-gray-700 rounded text-base">
              {{ currentJurisdiction.domain }}
            </span>
          </p>

          <div class="space-y-2">
            <p class="text-gray-600 dark:text-gray-300 m-0">
              Accounts in each location are completely separate with no data shared between them.
              You can create an account with the same email address in more than one location.
            </p>

            <p class="text-gray-600 dark:text-gray-300 m-0">
              To learn more, please
              <a :href="`${supportHost}/docs`"
                 class="text-brand-600 hover:text-brand-500 dark:text-brand-400 dark:hover:text-brand-300 font-medium"
                 target="_blank"
                 rel="noopener">
                visit our documentation
              </a>
              or
              <RouterLink to="/feedback"
                          class="text-brand-600 hover:text-brand-500 dark:text-brand-400 dark:hover:text-brand-300 font-medium">
                contact us
              </RouterLink>.
            </p>
          </div>
        </div>
      </div>

      <div class="space-y-3">
        <h4 class="text-sm font-medium text-gray-700 dark:text-gray-300">
          Available Jurisdictions
        </h4>

        <ul
            class="divide-y divide-gray-100 dark:divide-gray-700 rounded-lg border border-gray-200 dark:border-gray-700">
          <li v-for="jurisdiction in jurisdictions"
              :key="jurisdiction.identifier"
              class="flex items-center gap-3 p-3 hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors">
            <Icon :icon="jurisdiction.icon"
                  class="h-5 w-5 flex-shrink-0 text-gray-400 dark:text-gray-500"
                  aria-hidden="true" />

            <a :href="`https://${jurisdiction.domain}/signup`"
               :class="{
                'font-medium': currentJurisdiction.identifier === jurisdiction.identifier
              }"
               class="flex-grow text-gray-700 dark:text-gray-200 hover:text-brand-600 dark:hover:text-brand-400 text-sm">
              {{ jurisdiction.display_name }}
            </a>

            <span v-if="currentJurisdiction.identifier === jurisdiction.identifier"
                  class="inline-flex items-center rounded-full bg-brand-50 dark:bg-brand-900/20 px-2 py-1 text-xs font-medium text-brand-700 dark:text-brand-300"
                  aria-label="Current jurisdiction">
              Current
            </span>
          </li>
        </ul>
      </div>
    </section>
  </div>
</template>

<script setup lang="ts">
import { useWindowProp } from '@/composables/useWindowProps';
import { useJurisdictionStore } from '@/stores/jurisdictionStore';
import { Icon } from '@iconify/vue';
import { computed } from 'vue';

const cust = useWindowProp('cust');
const supportHost = useWindowProp('support_host');

const jurisdictionStore = useJurisdictionStore();
const currentJurisdiction = computed(() => jurisdictionStore.getCurrentJurisdiction);
const jurisdictions = computed(() => jurisdictionStore.getAllJurisdictions);


</script>
