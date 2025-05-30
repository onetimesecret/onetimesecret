<script setup lang="ts">
  import ColonelNavigation from '@/components/colonel/ColonelNavigation.vue';
  import FeedbackSection from '@/components/colonel/FeedbackSection.vue';
  import OIcon from '@/components/icons/OIcon.vue';
  import { useColonelInfoStore } from '@/stores/colonelInfoStore';
  import { storeToRefs } from 'pinia';
  import { computed, onMounted } from 'vue';
  import { useI18n } from 'vue-i18n';
  const { t } = useI18n();

  const feedbackSections = computed(() => {
    return [
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
    ];
  });

  const store = useColonelInfoStore();
  const { details, isLoading } = storeToRefs(store);
  const { fetch } = store; // Actions are extracted directly

  onMounted(fetch);
</script>

<template>
  <div class="min-h-screen bg-gray-50 dark:bg-gray-900">
    <!-- Header with navigation -->
    <ColonelNavigation />

    <!-- Main content -->
    <main class="mx-auto max-w-5xl px-3 py-6 sm:px-4 lg:px-6">
      <div class="overflow-hidden rounded-lg bg-white shadow-lg dark:bg-gray-800">
        <div
          v-if="isLoading"
          class="p-4 text-center">
          {{ t('web.LABELS.loading') }}
        </div>

        <div
          v-else
          class="p-4">
          <!-- Quick Navigation Bar -->
          <div class="mb-4 border-l-4 border-brand-500 pl-3">
            <h4
              class="mb-2 text-xs font-semibold uppercase tracking-wide text-gray-600 dark:text-gray-400">
              {{ t('quick-navigation') }}
            </h4>
            <div class="flex flex-wrap gap-2">
              <a
                href="#stats"
                class="inline-flex items-center text-xs font-medium text-brand-600 hover:text-brand-700 hover:underline dark:text-brand-400 dark:hover:text-brand-300">
                Stats
              </a>
              <span class="text-gray-400">•</span>
              <a
                href="#feedback"
                class="inline-flex items-center text-xs font-medium text-brand-600 hover:text-brand-700 hover:underline dark:text-brand-400 dark:hover:text-brand-300">
                {{ t('feedback') }}
              </a>
              <span class="text-gray-400">•</span>
              <a
                href="#customers"
                class="inline-flex items-center text-xs font-medium text-brand-600 hover:text-brand-700 hover:underline dark:text-brand-400 dark:hover:text-brand-300">
                {{ t('customers') }}
              </a>
              <span class="text-gray-400">•</span>
              <a
                href="#redis"
                class="inline-flex items-center text-xs font-medium text-brand-600 hover:text-brand-700 hover:underline dark:text-brand-400 dark:hover:text-brand-300">
                {{ t('redis-info') }}
              </a>
            </div>
          </div>

          <!-- Stats Overview -->
          <div
            id="stats"
            class="mb-6">
            <!-- Stats Cards -->
            <div class="grid gap-4 sm:grid-cols-2">
              <!-- Active Sessions Card -->
              <div
                class="rounded-lg border border-brand-200 bg-brand-50 p-3 dark:border-brand-700 dark:bg-brand-900/20">
                <div class="flex items-center">
                  <div class="flex-shrink-0">
                    <div class="h-2 w-2 rounded-full bg-green-400"></div>
                  </div>
                  <p class="ml-2 text-xs text-gray-800 dark:text-gray-200">
                    Sessions:
                    <span>{{ details?.counts.session_count }}</span>
                    {{ t('web.colonel.active-in-the-past-5-minutes-0') }}
                  </p>
                </div>
              </div>

              <!-- Secrets Summary Card -->
              <div
                class="rounded-lg border border-gray-200 bg-white p-3 dark:border-gray-700 dark:bg-gray-800">
                <h3 class="text-xs font-bold text-gray-800 dark:text-gray-200">
                  {{ details?.counts.secret_count }} Secrets
                </h3>
                <p class="mt-1 text-xs text-gray-600 dark:text-gray-400">
                  {{ details?.counts.metadata_count }} metadata,
                  {{ details?.counts.secrets_created }} created,
                  {{ details?.counts.secrets_shared }} shared,
                  {{ details?.counts.emails_sent }} emails
                </p>
              </div>
            </div>
          </div>

          <!-- Feedback Section -->
          <div
            id="feedback"
            class="mb-6">
            <h3 class="mb-2 flex items-center text-sm font-bold text-gray-800 dark:text-gray-200">
              <span>Feedback ({{ details?.counts.feedback_count }})</span>
              <a
                href="#"
                class="ml-2"
                ><OIcon
                  collection="heroicons"
                  name="arrow-up"
                  size="4"
              /></a>
            </h3>

            <div class="overflow-hidden bg-white text-xs shadow dark:bg-gray-800 sm:rounded-lg">
              <div class="divide-y divide-gray-200 dark:divide-gray-700">
                <FeedbackSection
                  v-for="section in feedbackSections"
                  :key="section.title"
                  :title="section.title"
                  :count="section.count ?? 0"
                  :feedback="section.feedback ?? []" />
              </div>
            </div>
          </div>

          <!-- Customers Section -->
          <div
            id="customers"
            class="mb-6">
            <h3 class="mb-2 flex items-center text-sm font-bold text-gray-800 dark:text-gray-200">
              <span
                >Recent Customers ({{ details?.counts.recent_customer_count }}/{{
                  details?.counts.customer_count
                }})</span
              >
              <a
                href="#"
                class="ml-2"
                ><OIcon
                  collection="heroicons"
                  name="arrow-up"
                  size="4"
              /></a>
            </h3>
            <ul
              class="divide-y divide-gray-200 overflow-hidden bg-white shadow dark:divide-gray-700 dark:bg-gray-800 sm:rounded-lg">
              <li
                v-for="customer in details?.recent_customers"
                :key="customer.custid"
                class="px-3 py-2 sm:px-4"
                :title="t('web.colonel.customer-verified-verified-not-verified-0')">
                <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between">
                  <p class="text-xs font-medium text-gray-900 dark:text-gray-100">
                    <strong>{{ customer.custid }}</strong>
                    <span class="ml-1 text-xs text-gray-500 dark:text-gray-400">
                      <em>{{ customer.stamp }}</em
                      >{{ !customer.verified ? '?' : '' }}
                    </span>
                  </p>
                  <p class="text-xs text-gray-500 dark:text-gray-400">
                    {{ customer.secrets_created }} created, {{ customer.secrets_shared }} shared,
                    {{ customer.emails_sent }} emails,
                    {{ customer.planid }}
                  </p>
                </div>
              </li>
            </ul>
          </div>

          <!-- Redis Info Section -->
          <div
            id="redis"
            class="mb-6">
            <h3 class="mb-2 flex items-center text-sm font-bold text-gray-800 dark:text-gray-200">
              {{ t('redis-info') }}
              <a
                href="#"
                class="ml-2"
                ><OIcon
                  collection="heroicons"
                  name="arrow-up"
                  size="4"
              /></a>
            </h3>
            <div class="max-h-64 overflow-y-auto">
              <pre
                class="overflow-x-auto rounded-lg bg-gray-100 p-3 text-xs text-gray-800 dark:bg-gray-700 dark:text-gray-200"
                >{{ details?.redis_info }}</pre
              >
            </div>
          </div>
        </div>
      </div>
    </main>
  </div>
</template>
