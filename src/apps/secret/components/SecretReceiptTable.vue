<!-- src/apps/secret/components/SecretReceiptTable.vue -->

<!--
  Console-style dashboard receipts feed.
  Lists pending and revealed receipts using SecretReceiptTableItem.
  Self-evident row design — no table headers needed.
-->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import OIcon from '@/shared/components/icons/OIcon.vue';
import SecretReceiptTableItem from '@/apps/secret/components/SecretReceiptTableItem.vue';
import type { ReceiptList } from '@/schemas/shapes/v3/receipt';

const { t } = useI18n();

interface Props {
  pendingReceipts: ReceiptList[];
  revealedReceipts: ReceiptList[];
  isLoading: boolean;
}

defineProps<Props>();
</script>

<template>
  <div
    class="space-y-8"
    v-cloak>
    <template v-if="isLoading">
      <!-- Loading indicator -->
      <div class="text-justify">
        <p class="text-gray-600 dark:text-gray-400">
          {{ t('web.COMMON.loading_ellipses') }}
        </p>
      </div>
    </template>
    <template v-else>
      <!-- Pending Receipts Section (not yet revealed) -->
      <section
        class="mb-8"
        aria-labelledby="pending-receipts-heading">
        <!-- Console-style list with pending receipts -->
        <!-- prettier-ignore-attribute class -->
        <div
          v-if="pendingReceipts && pendingReceipts.length > 0"
          class="relative overflow-hidden rounded-lg border border-gray-200/60 bg-white/60 p-4 shadow-sm
            backdrop-blur-sm dark:border-gray-700/60 dark:bg-gray-800/60">
          <ul
            class="divide-y-0"
            role="list"
            :aria-label="t('web.dashboard.title_not_received')">
            <SecretReceiptTableItem
              v-for="(item, idx) in pendingReceipts"
              :key="item.identifier ?? item.shortid ?? idx"
              :secret-receipt="item"
              :index="idx + 1"
              :is-last="idx === pendingReceipts.length - 1" />
          </ul>
        </div>

        <!-- Empty state for not received -->
        <!-- prettier-ignore-attribute class -->
        <div
          v-else
          class="rounded-xl border border-gray-200 bg-gray-50/50 p-6 text-center
            dark:border-gray-700/50 dark:bg-slate-800/20">
          <div class="flex flex-col items-center justify-center">
            <OIcon
              collection="heroicons"
              name="document-text"
              class="mb-3 size-10 text-gray-400 dark:text-gray-500"
              aria-hidden="true" />
            <p class="text-gray-600 dark:text-gray-400">
              {{ t('web.COMMON.go_on_then') }}
              <router-link
                to="/"
                class="text-brand-500 hover:underline">
                {{ t('web.COMMON.share_a_secret') }}
              </router-link>
            </p>
          </div>
        </div>
      </section>

      <!-- Revealed Receipts Section -->
      <section
        class="mb-8"
        aria-labelledby="revealed-receipts-heading">
        <h3
          id="revealed-receipts-heading"
          class="mb-4 text-lg font-medium text-gray-600 dark:text-gray-300">
          {{ t('web.dashboard.title_received') }}
        </h3>

        <!-- Console-style list with revealed receipts -->
        <!-- prettier-ignore-attribute class -->
        <div
          v-if="revealedReceipts && revealedReceipts.length > 0"
          class="relative overflow-hidden rounded-lg border border-gray-200/60 bg-white/60 p-4 shadow-sm
            backdrop-blur-sm dark:border-gray-700/60 dark:bg-gray-800/60">
          <ul
            class="divide-y-0"
            role="list"
            :aria-label="t('web.dashboard.title_received')">
            <SecretReceiptTableItem
              v-for="(item, idx) in revealedReceipts"
              :key="item.identifier ?? item.shortid ?? idx"
              :secret-receipt="item"
              :index="idx + 1"
              :is-last="idx === revealedReceipts.length - 1" />
          </ul>
        </div>

        <!-- Empty state for received -->
        <!-- prettier-ignore-attribute class -->
        <div
          v-else
          class="rounded-xl border border-gray-200 bg-gray-50/50 p-6 text-center
            dark:border-gray-700/50 dark:bg-slate-800/20">
          <div class="flex flex-col items-center justify-center">
            <OIcon
              collection="heroicons"
              name="inbox"
              class="mb-3 size-10 text-gray-400 dark:text-gray-500"
              aria-hidden="true" />
            <p class="text-gray-600 dark:text-gray-400">
              {{ t('web.COMMON.word_none') }}
            </p>
          </div>
        </div>
      </section>
    </template>
  </div>
</template>
