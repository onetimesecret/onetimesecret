<!-- src/views/colonel/ColonelUsers.vue -->

<script setup lang="ts">
  import FeedbackSection from '@/components/colonel/FeedbackSection.vue';
  import OIcon from '@/components/icons/OIcon.vue';
  import { useColonelInfoStore } from '@/stores/colonelInfoStore';
  import { onMounted } from 'vue';
  import { storeToRefs } from 'pinia';
  // import { useI18n } from 'vue-i18n';
  // const { t } = useI18n();

  const navTabs = [
    'users',
    'domains',
    'settings',
    'welcome,'
  ];

  const store = useColonelInfoStore();
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
          v-for="tab in navTabs"
          :key="tab.href"
          :href="tab.href"
          class="mx-1 border-b-2 border-transparent px-4 py-3 text-sm font-semibold text-gray-700 transition-colors duration-150 first:ml-0 hover:border-brand-500 hover:text-brand-600 focus:border-brand-500 focus:outline-none dark:text-gray-200 dark:hover:border-brand-400 dark:hover:text-brand-400">
          {{ tab.name }}
        </a>
      </nav>
    </div>

    <div v-if="isLoading">Loading...</div>

    <div
      v-else
      class="p-6">
      <div
        id="stats"
        class="mb-8">
        <div class="mb-6 border-l-4 border-brand-500 pl-4">
          <h4
            class="mb-3 text-sm font-semibold uppercase tracking-wide text-gray-600 dark:text-gray-400">
            {{ $t('quick-navigation') }}
          </h4>
          <div class="flex flex-wrap gap-2">
            <a
              href="#feedback"
              class="inline-flex items-center text-sm font-medium text-brand-600 hover:text-brand-700 hover:underline dark:text-brand-400 dark:hover:text-brand-300">
              {{ $t('feedback') }}
            </a>
            <span class="text-gray-400">•</span>
            <a
              href="#customers"
              class="inline-flex items-center text-sm font-medium text-brand-600 hover:text-brand-700 hover:underline dark:text-brand-400 dark:hover:text-brand-300">
              {{ $t('customers') }}
            </a>
            <span class="text-gray-400">•</span>
            <a
              href="#redis"
              class="inline-flex items-center text-sm font-medium text-brand-600 hover:text-brand-700 hover:underline dark:text-brand-400 dark:hover:text-brand-300">
              {{ $t('redis-info') }}
            </a>
          </div>
        </div>

        <div
          class="mb-6 rounded-lg border border-brand-200 bg-brand-50 p-4 dark:border-brand-700 dark:bg-brand-900/20">
          <div class="flex items-center">
            <div class="flex-shrink-0">
              <div class="h-2 w-2 rounded-full bg-green-400"></div>
            </div>
            <p class="ml-3 text-gray-800 dark:text-gray-200">
              Sessions: <span class="text-lg font-bold">{{ details?.counts.session_count }}</span
              >{{ $t('web.colonel.active-in-the-past-5-minutes-0') }}
            </p>
          </div>
        </div>

        <h3 class="mb-2 text-xl font-bold text-gray-800 dark:text-gray-200">
          {{
            $t('web.colonel.secrets-details-counts-secret_count-0', [details?.counts.secret_count])
          }}
        </h3>

        <p class="text-gray-800 dark:text-gray-200">
          {{
            $t('web.colonel.metadata-secrets-details-counts-metadata_count-d-0', [
              details?.counts.metadata_count,
              details?.counts.secret_count,
              details?.counts.secrets_created,
              details?.counts.secrets_shared,
              details?.counts.emails_sent,
            ])
          }}
        </p>
      </div>

      <div
        id="feedback"
        class="mb-8">
        <h3 class="mb-2 flex items-center text-xl font-bold text-gray-800 dark:text-gray-200">
          {{
            $t('web.colonel.user-feedback-total-details-counts-feedback_coun-0', [
              details?.counts.feedback_count,
            ])
          }}
          <a
            href="#"
            class="ml-2"
            ><OIcon
              collection="heroicons"
              name="arrow-up"
              size="5"
          /></a>
        </h3>

        <div class="overflow-hidden bg-white text-sm shadow dark:bg-gray-800 sm:rounded-lg">
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

      <div
        id="customers"
        class="mb-8">
        <h3 class="mb-2 flex items-center text-xl font-bold text-gray-800 dark:text-gray-200">
          {{
            $t('web.colonel.customers-details-counts-recent_customer_count-o-0', [
              details?.counts.recent_customer_count,
              details?.counts.customer_count,
            ])
          }}
          <a
            href="#"
            class="ml-2"
            ><OIcon
              collection="heroicons"
              name="arrow-up"
              size="5"
          /></a>
        </h3>
        <ul
          class="divide-y divide-gray-200 overflow-hidden bg-white shadow dark:divide-gray-700 dark:bg-gray-800 sm:rounded-lg">
          <li
            v-for="customer in details?.recent_customers"
            :key="customer.custid"
            class="px-4 py-3 sm:px-6"
            :title="$t('web.colonel.customer-verified-verified-not-verified-0')">
            <div class="flex items-center justify-between">
              <p class="text-sm font-medium text-gray-900 dark:text-gray-100">
                <strong>{{ customer.custid }}</strong>
              </p>
              <p class="text-sm text-gray-500 dark:text-gray-400">
                {{
                  $t('web.colonel.customer-secrets_created-customer-secrets_shared-0', [
                    customer.secrets_created,
                    customer.secrets_shared,
                    customer.emails_sent,
                    customer.planid,
                  ])
                }}
              </p>
            </div>
            <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
              <em>{{ customer.stamp }}</em
              >{{ !customer.verified ? '?' : '' }}
            </p>
          </li>
        </ul>
      </div>

      <div
        id="redis"
        class="mb-8">
        <h3 class="mb-2 mt-6 flex items-center text-xl font-bold text-gray-800 dark:text-gray-200">
          {{ $t('redis-info') }}
          <a
            href="#"
            class="ml-2"
            ><OIcon
              collection="heroicons"
              name="arrow-up"
              size="5"
          /></a>
        </h3>
        <pre
          class="overflow-x-auto rounded-lg bg-gray-100 p-4 text-sm text-gray-800 dark:bg-gray-700 dark:text-gray-200"
          >{{ details?.redis_info }}</pre
        >
      </div>
    </div>
  </div>
</template>
