<script setup lang="ts">
import FeedbackSection from '@/components/colonel/FeedbackSection.vue';
import { useColonelStore } from '@/stores/colonelStore';
import { computed, onMounted } from 'vue';
import { storeToRefs } from 'pinia';

const tabs = [
  { name: 'Stats', href: '#stats' },
  { name: 'Customers', href: '#customers' },
  { name: 'Feedback', href: '#feedback' },
  { name: 'Misc', href: '#misc' },
];

const feedbackSections = computed(() => {
  return [
    { title: 'Today', count: details?.value?.counts.today_feedback_count, feedback: details?.value?.today_feedback },
    { title: 'Yesterday', count: details?.value?.counts.yesterday_feedback_count, feedback: details?.value?.yesterday_feedback },
    { title: 'Past 14 Days', count: details?.value?.counts.older_feedback_count, feedback: details?.value?.older_feedback },
  ];
});

const store = useColonelStore();
const { details, isLoading } = storeToRefs(store);
const { fetch } = store; // Actions are extracted directly

onMounted(fetch);
</script>

<template>
  <div class="overflow-hidden rounded-lg bg-white shadow-lg dark:bg-gray-800">
    <div
      id="primaryTabs"
      class="sticky top-0 z-10 border-b border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
      <nav class="flex overflow-x-auto">
        <a
          v-for="tab in tabs"
          :key="tab.href"
          :href="tab.href"
          class="px-3 py-2 text-sm font-medium text-gray-600 hover:text-brand-500 dark:text-gray-300 dark:hover:text-brand-400">
          {{ tab.name }}
        </a>
      </nav>
    </div>

    <div v-if="isLoading">Loading...</div>

    <div v-else class="p-6">
      <div
        id="stats"
        class="mb-8">
        <!-- Session messages component would go here -->

        <div class="mb-4 rounded-lg bg-gray-100 p-4 dark:bg-gray-700">
          <p class="text-gray-800 dark:text-gray-200">
            Sessions: <span class="font-bold">{{ details?.counts.session_count }}</span> (active in the past 5
            minutes)
          </p>
        </div>

        <h3 class="mb-2 text-xl font-bold text-gray-800 dark:text-gray-200">
          Secrets ({{ details?.counts.secret_count }})
        </h3>

        <p class="text-gray-800 dark:text-gray-200">
          Metadata /
          Secrets:
          {{ details?.counts.metadata_count }}/{{ details?.counts.secret_count }}
          ({{ details?.counts.secrets_created }}/{{ details?.counts.secrets_shared }}/{{ details?.counts.emails_sent }} total)
        </p>
      </div>

      <div
        id="feedback"
        class="mb-8">
        <h3 class="mb-2 text-lg font-bold text-gray-800 dark:text-gray-200">
          User Feedback (Total: {{ details?.counts.feedback_count }})
        </h3>

        <div class="overflow-hidden bg-white text-sm shadow dark:bg-gray-800 sm:rounded-lg">
          <div class="divide-y divide-gray-200 dark:divide-gray-700">
            <FeedbackSection
              v-for="section in feedbackSections"
              :key="section.title"
              :title="section.title"
              :count="section.count ?? 0"
              :feedback="section.feedback ?? []"
            />
          </div>
        </div>
      </div>

      <div
        id="customers"
        class="mb-8">
        <h3 class="mb-2 text-xl font-bold text-gray-800 dark:text-gray-200">
          Customers ({{ details?.counts.recent_customer_count }} of {{ details?.counts.customer_count }})
        </h3>
        <ul
          class="divide-y divide-gray-200 overflow-hidden bg-white shadow dark:divide-gray-700 dark:bg-gray-800 sm:rounded-lg">
          <li
            v-for="customer in details?.recent_customers"
            :key="customer.custid"
            class="px-4 py-3 sm:px-6"
            :title="customer.verified ? 'verified' : 'not verified'">
            <div class="flex items-center justify-between">
              <p class="text-sm font-medium text-gray-900 dark:text-gray-100">
                <strong>{{ customer.custid }}</strong>
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

      <div
        id="misc"
        class="mb-8">
        <h3 class="mb-2 mt-6 text-xl font-bold text-gray-800 dark:text-gray-200">
          Redis Info
        </h3>
        <pre
          class="overflow-x-auto rounded-lg bg-gray-100 p-4 text-sm text-gray-800 dark:bg-gray-700 dark:text-gray-200">{{ details?.redis_info }}</pre>
      </div>
    </div>
  </div>
</template>
