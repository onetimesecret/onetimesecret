<template>

    <div class="bg-white dark:bg-gray-800 shadow-lg rounded-lg overflow-hidden">
      <div
        id="primaryTabs"
        class="border-b border-gray-200 dark:border-gray-700 sticky top-0 bg-white dark:bg-gray-800 z-10"
      >
        <nav class="flex overflow-x-auto">
          <a
            v-for="tab in tabs"
            :key="tab.href"
            :href="tab.href"
            class="text-gray-600 dark:text-gray-300 hover:text-brand-500 dark:hover:text-brand-400 px-3 py-2 font-medium text-sm"
          >
            {{ tab.name }}
          </a>
        </nav>
      </div>

      <div class="p-6">
        <div id="stats" class="mb-8">
          <!-- Session messages component would go here -->

          <div class="bg-gray-100 dark:bg-gray-700 rounded-lg p-4 mb-4">
            <p class="text-gray-800 dark:text-gray-200">
              Sessions: <span class="font-bold">{{ colonelData?.counts.session_count }}</span> (active in the past 5
              minutes)
            </p>
          </div>

          <h3 class="text-xl font-bold mb-2 text-gray-800 dark:text-gray-200">
            Secrets ({{ colonelData?.counts.secret_count }})
          </h3>

          <p class="text-gray-800 dark:text-gray-200">
            Metadata /
            Secrets:
            {{ colonelData?.counts.metadata_count }}/{{ colonelData?.counts.secret_count }}
            ({{ colonelData?.counts.secrets_created }}/{{ colonelData?.counts.secrets_shared }}/{{ colonelData?.counts.emails_sent }} total)
          </p>
        </div>

        <div id="feedback" class="mb-8">
          <h3 class="text-lg font-bold mb-2 text-gray-800 dark:text-gray-200">
            User Feedback (Total: {{ colonelData?.counts.feedback_count }})
          </h3>

          <div class="bg-white dark:bg-gray-800 shadow overflow-hidden sm:rounded-lg text-sm">
            <div class="divide-y divide-gray-200 dark:divide-gray-700">
              <FeedbackSection
                v-for="section in feedbackSections"
                :key="section.title"
                :title="section.title"
                :count="section.count"
                :feedback="section.feedback"
              />
            </div>
          </div>
        </div>

        <div id="customers" class="mb-8">
          <h3 class="text-xl font-bold mb-2 text-gray-800 dark:text-gray-200">
            Customers ({{ colonelData?.counts.recent_customer_count }} of {{ colonelData?.counts.customer_count }})
          </h3>
          <ul
            class="bg-white dark:bg-gray-800 shadow overflow-hidden sm:rounded-lg divide-y divide-gray-200 dark:divide-gray-700"
          >
            <li
              v-for="customer in colonelData?.recent_customers"
              :key="customer.custid"
              class="px-4 py-3 sm:px-6"
              :title="customer.verified ? 'verified' : 'not verified'"
            >
              <div class="flex items-center justify-between">
                <p class="text-sm font-medium text-gray-900 dark:text-gray-100">
                  <strong>{{ customer.custid }}</strong>{{ customer.colonel ? '*' : '' }}
                </p>
                <p class="text-sm text-gray-500 dark:text-gray-400">
                  {{ customer.secrets_created }}/{{ customer.secrets_shared }}/{{ customer.emails_sent }} [{{ customer.planid }}]
                </p>
              </div>
              <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
                <em>{{ customer.stamp }}</em>{{ !customer.verified ? '?' : '' }}
              </p>
            </li>
          </ul>
        </div>

        <div id="misc" class="mb-8">

          <h3 class="text-xl font-bold mt-6 mb-2 text-gray-800 dark:text-gray-200">Redis Info</h3>
          <pre
            class="bg-gray-100 dark:bg-gray-700 p-4 rounded-lg overflow-x-auto text-sm text-gray-800 dark:text-gray-200"
          >{{ colonelData?.redis_info }}</pre>
        </div>
      </div>
    </div>

</template>

<script setup lang="ts">
import { onMounted, computed } from 'vue';
import FeedbackSection from '@/components/colonel/FeedbackSection.vue';
import { ColonelData } from '@/types/onetime'


const tabs = [
  { name: 'Stats', href: '#stats' },
  { name: 'Customers', href: '#customers' },
  { name: 'Feedback', href: '#feedback' },
  { name: 'Misc', href: '#misc' },
];

const feedbackSections = computed(() => {
  if (!colonelData.value) return [];
  return [
    { title: 'Today', count: colonelData.value.counts.today_feedback_count, feedback: colonelData.value.today_feedback },
    { title: 'Yesterday', count: colonelData.value.counts.yesterday_feedback_count, feedback: colonelData.value.yesterday_feedback },
    { title: 'Past 14 Days', count: colonelData.value.counts.older_feedback_count, feedback: colonelData.value.older_feedback },
  ];
});

import { useFetchDataRecord } from '@/utils/fetchData';


const { record: colonelData, fetchData: fetchColonelData } = useFetchDataRecord<ColonelData>({
  url: '/api/v2/colonel',
});

onMounted(fetchColonelData);
</script>
