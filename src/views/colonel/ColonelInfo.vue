<script setup lang="ts">
  import FeedbackSection from '@/components/colonel/FeedbackSection.vue';
  import OIcon from '@/components/icons/OIcon.vue';
  import { useColonelInfoStore } from '@/stores/colonelInfoStore';
  import { storeToRefs } from 'pinia';
  import { computed, onMounted } from 'vue';
  import { useI18n } from 'vue-i18n';
  const { t } = useI18n();

  const feedbackSections = computed(() => [
      {
        title: t('today'),
        count: details?.value?.counts.today_feedback_count,
        feedback: details?.value?.today_feedback,
      },
      {
        title: t('yesterday'),
        count: details?.value?.counts.yesterday_feedback_count,
        feedback: details?.value?.yesterday_feedback,
      },
      {
        title: t('past-14-days'),
        count: details?.value?.counts.older_feedback_count,
        feedback: details?.value?.older_feedback,
      },
    ]);

  const store = useColonelInfoStore();
  const { details, isLoading } = storeToRefs(store);
  const { fetch } = store; // Actions are extracted directly

  onMounted(fetch);
</script>

<template>
  <div class="">
    <div
      v-if="isLoading"
      class="p-4 text-center">
      {{ t('web.LABELS.loading') }}
    </div>

    <div v-else>
      <div class="mb-6">
        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-bold text-gray-900 dark:text-white">
              {{ t('web.colonel.recentActivity') }}
            </h1>
            <p class="mt-2 text-sm text-gray-600 dark:text-gray-400">
              {{ t('web.colonel.actions.viewActivityDesc') }}
            </p>
          </div>
        </div>
      </div>

      <!-- Quick Navigation Bar -->
      <div
        id="top"
        class="mb-4 border-l-4 border-brand-500 pl-3 text-sm">
        <h4
          class="mb-2 text-xs font-semibold uppercase tracking-wide text-gray-600 dark:text-gray-400">
          {{ t('quick-navigation') }}
        </h4>
        <div class="flex flex-wrap gap-2">
          <a
            href="#feedback"
            class="inline-flex items-center font-medium text-brand-600 hover:text-brand-700 hover:underline dark:text-brand-400 dark:hover:text-brand-300">
            {{ t('feedback') }}
          </a>
          <span class="text-gray-400">•</span>
          <a
            href="#customers"
            class="inline-flex items-center font-medium text-brand-600 hover:text-brand-700 hover:underline dark:text-brand-400 dark:hover:text-brand-300">
            {{ t('customers') }}
          </a>
          <span class="text-gray-400">•</span>
          <a
            href="#redis"
            class="inline-flex items-center font-medium text-brand-600 hover:text-brand-700 hover:underline dark:text-brand-400 dark:hover:text-brand-300">
            {{ t('redis-info') }}
          </a>
        </div>
      </div>

      <!-- Activity Summary -->
      <div
        class="mb-6 rounded-lg border border-brand-200 bg-brand-50 p-4 dark:border-brand-700 dark:bg-brand-900/20">
        <div class="flex items-center justify-between">
          <div class="flex items-center space-x-3">
            <div class="h-3 w-3 rounded-full bg-green-400"></div>
            <div>
              <h3 class="text-sm font-medium text-gray-900 dark:text-white">Activity Overview</h3>
              <p class="text-xs text-gray-600 dark:text-gray-400">
                {{ details?.counts.session_count }} active sessions •
                {{ details?.counts.feedback_count }} feedback items •
                {{ details?.counts.recent_customer_count }} recent customers
              </p>
              <p class="mt-1 text-xs text-gray-500 dark:text-gray-500">
                Last updated: {{ new Date().toLocaleString() }}
              </p>
            </div>
          </div>
          <div class="text-right flex-shrink-0">
            <a
              href="/colonel"
              class="text-xs text-brand-600 hover:text-brand-700 dark:text-brand-400">
              View Dashboard →
            </a>
          </div>
        </div>
      </div>

      <!-- Feedback Section -->
      <div
        id="feedback"
        class="mb-6">
        <h3 class="mb-3 flex items-center text-lg font-semibold text-gray-900 dark:text-white">
          <span>Feedback ({{ details?.counts.feedback_count }})</span>
          <a
            href="#top"
            class="ml-2"
            ><OIcon
              collection="heroicons"
              name="arrow-up"
              size="4"
          /></a>
        </h3>

        <ul class="overflow-hidden bg-white text-xs shadow dark:bg-gray-800 sm:rounded-lg">
          <li
            v-for="section in feedbackSections"
            :key="section.title"
            class="border-b border-gray-200 last:border-b-0 dark:border-gray-700">
            <FeedbackSection
              :title="section.title"
              :count="section.count ?? 0"
              :feedback="section.feedback ?? []" />
          </li>
        </ul>
      </div>

      <!-- Customers Section -->
      <div
        id="customers"
        class="mb-6">
        <h3 class="mb-3 flex items-center text-lg font-semibold text-gray-900 dark:text-white">
          <span>
            Recent Customers ({{ details?.counts.recent_customer_count }}/{{
              details?.counts.customer_count
            }})
          </span>
          <a
            href="#top"
            class="ml-2"
            ><OIcon
              collection="heroicons"
              name="arrow-up"
              size="4"
          /></a>
        </h3>
        <ul class="space-y-3">
          <li
            v-for="customer in details?.recent_customers"
            :key="customer.custid"
            class="rounded-lg bg-white p-4 shadow dark:bg-gray-800">
            <div class="flex items-center justify-between">
              <div class="min-w-0 flex-1">
                <div class="flex items-center space-x-2">
                  <span class="truncate font-medium text-gray-900 dark:text-gray-100 max-w-xs">{{
                    customer.custid
                  }}</span>
                  <span
                    v-if="customer.verified"
                    class="inline-flex items-center rounded-full bg-green-100 px-2 py-0.5 text-xs font-medium text-green-800 dark:bg-green-900/20 dark:text-green-400">
                    Verified
                  </span>
                  <span
                    v-else
                    class="inline-flex items-center rounded-full bg-yellow-100 px-2 py-0.5 text-xs font-medium text-yellow-800 dark:bg-yellow-900/20 dark:text-yellow-400">
                    Unverified
                  </span>
                </div>
                <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">{{ customer.stamp }}</p>
              </div>
              <div class="text-right flex-shrink-0">
                <div class="text-sm font-medium text-gray-900 dark:text-gray-100">{{
                  customer.planid
                }}</div>
                <p class="text-xs text-gray-500 dark:text-gray-400 whitespace-nowrap">
                  {{ customer.secrets_created }} created • {{ customer.secrets_shared }} shared •
                  {{ customer.emails_sent }} emails
                </p>
              </div>
            </div>
          </li>
        </ul>
      </div>

      <!-- Redis Info Section -->
      <div
        id="redis"
        class="mb-6">
        <h3 class="mb-3 flex items-center text-lg font-semibold text-gray-900 dark:text-white">
          <span>{{ t('redis-info') }}</span>
          <a
            href="#top"
            class="ml-2"
            ><OIcon
              collection="heroicons"
              name="arrow-up"
              size="4"
          /></a>
        </h3>
        <div class="rounded-lg bg-white shadow dark:bg-gray-800">
          <div class="max-h-64 overflow-y-auto p-4">
            <pre class="text-xs text-gray-800 dark:text-gray-200">{{ details?.dbclient_info }}</pre>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
