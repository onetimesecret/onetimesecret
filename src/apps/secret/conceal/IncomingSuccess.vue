<!-- src/apps/secret/conceal/IncomingSuccess.vue -->

<script setup lang="ts">
  import { computed, ref } from 'vue';
  import { useRoute, useRouter } from 'vue-router';
  import { useNotificationsStore } from '@/shared/stores/notificationsStore';
  import { useI18n } from 'vue-i18n';

  const { t } = useI18n();
  const route = useRoute();
  const router = useRouter();
  const notifications = useNotificationsStore();

  const receiptKey = computed(() => route.params.receiptKey as string);
  const receiptUrl = computed(() => `/receipt/${receiptKey.value}`);
  const copied = ref(false);

  const handleCreateAnother = () => {
    router.push({ name: 'IncomingSecretForm' });
  };

  const openReceipt = () => {
    if (receiptKey.value) {
      window.open(receiptUrl.value, '_blank');
    }
  };

  const copyToClipboard = async () => {
    if (!receiptKey.value) return;

    try {
      await navigator.clipboard.writeText(receiptKey.value);
      copied.value = true;
      notifications.show('Reference ID copied to clipboard', 'success', 'top');

      setTimeout(() => {
        copied.value = false;
      }, 2000);
    } catch {
      notifications.show('Failed to copy reference ID', 'error', 'top');
    }
  };
</script>

<template>
  <div class="container mx-auto mt-16 max-w-3xl px-4 pb-16 sm:mt-20">
    <!-- Success Card -->
    <div class="overflow-hidden rounded-2xl bg-white shadow-lg dark:bg-slate-800">
      <!-- Success Icon & Header -->
      <div class="bg-gradient-to-br from-green-50 to-emerald-50 px-8 py-12 dark:from-green-950/30 dark:to-emerald-950/30 sm:px-12">
        <div class="flex flex-col items-center">
          <!-- Success Icon -->
          <div class="relative mb-6">
            <div class="absolute inset-0 rounded-full bg-green-400 opacity-25"></div>
            <div class="relative flex size-20 items-center justify-center rounded-full bg-green-500 shadow-lg dark:bg-green-600">
              <svg
                class="size-10 text-white"
                fill="none"
                stroke="currentColor"
                stroke-width="3"
                viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M5 13l4 4L19 7" />
              </svg>
            </div>
          </div>

          <!-- Success Message -->
          <h1 class="mb-3 text-center text-3xl font-bold text-gray-900 dark:text-white sm:text-4xl">
            {{ t('incoming.success_title') }}
          </h1>
          <p class="max-w-md text-center text-base text-gray-600 dark:text-gray-400 sm:text-lg">
            {{ t('incoming.success_description') }}
          </p>
        </div>
      </div>

      <!-- Content Area -->
      <div class="px-8 py-8 sm:px-12">
        <!-- Reference ID Card -->
        <div
          v-if="receiptKey"
          class="mb-8">
          <label class="mb-3 block text-sm font-semibold uppercase tracking-wide text-gray-500 dark:text-gray-400">
            {{ t('incoming.reference_id') }}
          </label>
          <div class="group relative overflow-hidden rounded-xl border-2 border-gray-200 bg-gray-50 transition-all duration-200 hover:border-gray-300 dark:border-gray-700 dark:bg-slate-900/50 dark:hover:border-gray-600">
            <div class="flex items-center justify-between gap-2 p-4">
              <code class="flex-1 select-all break-all font-mono text-sm font-medium text-gray-900 dark:text-white sm:text-base">
                {{ receiptKey }}
              </code>
              <div class="flex flex-shrink-0 gap-2">
                <button
                  type="button"
                  class="rounded-lg bg-gray-200 p-2.5 text-gray-600 transition-all duration-200 hover:bg-gray-300 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 dark:bg-gray-700 dark:text-gray-300 dark:hover:bg-gray-600"
                  :class="{ 'bg-green-500 hover:bg-green-500 text-white dark:bg-green-600 dark:hover:bg-green-600': copied }"
                  @click="copyToClipboard"
                  :title="copied ? 'Copied!' : 'Copy to clipboard'">
                  <svg
                    v-if="!copied"
                    class="size-5"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2"
                    viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" />
                  </svg>
                  <svg
                    v-else
                    class="size-5"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2.5"
                    viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      d="M5 13l4 4L19 7" />
                  </svg>
                </button>
                <button
                  type="button"
                  class="rounded-lg bg-gray-200 p-2.5 text-gray-600 transition-all duration-200 hover:bg-gray-300 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 dark:bg-gray-700 dark:text-gray-300 dark:hover:bg-gray-600"
                  @click="openReceipt"
                  title="Open receipt in new window">
                  <svg
                    class="size-5"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2"
                    viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" />
                  </svg>
                </button>
              </div>
            </div>
          </div>
        </div>

        <!-- Information Box -->
        <div class="mb-8 overflow-hidden rounded-xl border border-purple-200 bg-gradient-to-br from-purple-50 to-blue-50 dark:border-purple-900/50 dark:from-purple-950/30 dark:to-blue-950/30">
          <div class="flex gap-4 p-4">
            <div class="flex-shrink-0">
              <div class="flex size-10 items-center justify-center rounded-lg bg-purple-100 dark:bg-purple-900/50">
                <svg
                  class="size-6 text-purple-600 dark:text-purple-400"
                  fill="currentColor"
                  viewBox="0 0 20 20">
                  <path
                    fill-rule="evenodd"
                    d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z"
                    clip-rule="evenodd" />
                </svg>
              </div>
            </div>
            <div class="flex-1">
              <h3 class="mb-2 font-semibold text-purple-900 dark:text-purple-200">
                {{ t('incoming.success_info_title') }}
              </h3>
              <p class="text-sm leading-relaxed text-purple-800 dark:text-purple-300">
                {{ t('incoming.success_info_description') }}
              </p>
            </div>
          </div>
        </div>

        <!-- Action Button -->
        <div class="flex justify-center">
          <button
            type="button"
            class="rounded-xl bg-brand-500 px-8 py-4 text-base font-semibold text-white shadow-md transition-all duration-200 hover:bg-brand-600 hover:shadow-lg focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2"
            @click="handleCreateAnother">
            <span class="flex items-center justify-center gap-2">
              <svg
                class="size-5"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M12 4v16m8-8H4" />
              </svg>
              {{ t('incoming.create_another') }}
            </span>
          </button>
        </div>
      </div>
    </div>

    <!-- Helpful Tips -->
    <div class="mt-8 text-center">
      <i18n-t
        keypath="incoming.end_of_experience_suggestion"
        tag="p"
        class="text-sm text-gray-500 dark:text-gray-400"
        scope="global">
        <template #receipt>
          <a
            :href="receiptUrl"
            class="text-brand-600 underline transition-colors duration-200 hover:text-brand-700 dark:text-brand-400 dark:hover:text-brand-300">
            {{ t('incoming.receipt_link_text', 'receipt') }}
          </a>
        </template>
      </i18n-t>
    </div>
  </div>
</template>
