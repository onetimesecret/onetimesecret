<!-- src/apps/secret/reveal/ShowReceipt.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import ReceiptSkeleton from '@/shared/components/closet/ReceiptSkeleton.vue';
  import CopyButton from '@/shared/components/ui/CopyButton.vue';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import NeedHelpModal from '@/shared/components/modals/NeedHelpModal.vue';
  import BurnButtonForm from '@/apps/secret/components/receipt/BurnButtonForm.vue';
  import ReceiptFAQ from '@/apps/secret/components/receipt/ReceiptFAQ.vue';
  import SecretLink from '@/apps/secret/components/receipt/SecretLink.vue';
  import StatusBadge from '@/apps/secret/components/receipt/StatusBadge.vue';
  import TimelineDisplay from '@/apps/secret/components/receipt/TimelineDisplay.vue';
  import { useReceipt } from '@/shared/composables/useReceipt';
  import { useSecretExpiration, EXPIRATION_EVENTS } from '@/shared/composables/useSecretExpiration';
  import { onMounted, onUnmounted, watch, computed, ref } from 'vue';

  import UnknownReceipt from './UnknownReceipt.vue';

  // Define props
  interface Props {
    receiptIdentifier: string;
  }
  const props = defineProps<Props>();

  const { t } = useI18n();

  // State for delayed warning message
  const showWarning = ref(false);
  const warningMessage = ref<HTMLElement | null>(null);

  const { record, details, isLoading, fetch, reset } = useReceipt(props.receiptIdentifier);

  const { onExpirationEvent } = useSecretExpiration(
    record.value?.created ?? new Date(),
    record.value?.expiration_in_seconds ?? 0
  );

  const isAvailable = computed(() => !(record.value?.is_destroyed || record.value?.is_burned || record.value?.is_received));

  const goBack = () => {
    window.history.back();
  };

  // Watch for route parameter changes to refetch data
  watch(
    () => props.receiptIdentifier,
    (newKey) => {
      reset();
      if (newKey) {
        fetch();
      }
    }
  );

  onMounted(() => {
    fetch();

    // Handle expiration events at page level
    onExpirationEvent(EXPIRATION_EVENTS.EXPIRED, () => {
      // Update UI state, show notifications etc
    });

    onExpirationEvent(EXPIRATION_EVENTS.WARNING, () => {
      // Show warning notification
    });

    // Delay showing the warning message for better screen reader experience
    // This ensures the page has loaded and user has context before the warning is announced
    setTimeout(() => {
      showWarning.value = true;
    }, 1500); // 1.5 second delay for optimal timing
  });

  // Ensure cleanup when component unmounts
  onUnmounted(() => {
    reset();
  });
</script>

<template>
  <div class="flex flex-col">
    <div class="container mx-auto px-4">
      <!--  Add Back navigation link -->
      <!-- prettier-ignore-attribute class -->
      <button
        type="button"
        @click="goBack"
        class="mb-4 mt-2 inline-flex items-center gap-2 text-lg font-medium
        text-gray-600 hover:text-gray-800
        dark:text-gray-300 dark:hover:text-gray-200">
        <OIcon
          collection="heroicons"
          name="arrow-left"
          size="6" />
        {{ t('web.COMMON.back') }}
      </button>

      <ReceiptSkeleton v-if="isLoading" />

      <div v-else-if="!record || !details">
        <UnknownReceipt />
      </div>

      <div
        v-else-if="record && details"
        class="mx-auto max-w-3xl space-y-10">
        <!-- Main Card with Enhanced Styling -->
        <!-- prettier-ignore-attribute class -->
        <div
          class="overflow-hidden rounded-xl border border-gray-200/60
          bg-gradient-to-br from-white to-gray-50/30
          shadow-[0_4px_16px_rgb(0,0,0,0.08),0_1px_4px_rgb(0,0,0,0.06)]
          backdrop-blur-sm
          dark:border-gray-700/60 dark:from-slate-900 dark:to-slate-800/30
          dark:shadow-none">
          <!-- Secret Link Header -->
          <section
            class="relative"
            aria-labelledby="secret-header">
            <SecretLink
              v-if="isAvailable"
              :record="record"
              :details="details"
              :is-initial-view="!record.is_viewed" />
          </section>

          <!-- Recipients Section -->
          <div
            v-if="details.show_recipients"
            class="border-t border-gray-200/60 p-4 sm:p-6 dark:border-gray-700/40">
            <h3 class="flex items-center text-base font-medium text-gray-900 dark:text-white">
              <OIcon
                collection="material-symbols"
                name="mail-outline"
                class="mr-2 size-5 text-brand-500 dark:text-brand-400" />
              {{ t('web.COMMON.sent_to') }} {{ record.recipients }}
            </h3>
          </div>

          <!-- Secret Value with Enhanced Styling -->
          <!-- prettier-ignore-attribute class -->
          <section
            v-if="details.show_secret"
            class="border-y border-gray-200/60 bg-gray-50 p-4 sm:p-6
            dark:border-gray-700/60 dark:bg-gray-800/60">
            <!-- prettier-ignore-attribute class -->
            <textarea
              readonly
              :value="details.secret_value"
              :rows="details.display_lines || 3"
              class="w-full resize-none whitespace-pre
              rounded-lg border-2 border-gray-200 bg-white px-4 py-3
              font-mono text-base leading-tight tracking-wide text-gray-900 shadow-sm transition-colors
              focus:border-brand-500 focus:ring-2 focus:ring-brand-500
              dark:border-gray-700 dark:bg-gray-900 dark:text-gray-100 dark:focus:border-brand-400"></textarea>
            <div class="mt-3 flex w-full items-center justify-between">
              <p
                ref="warningMessage"
                class="flex items-center gap-2 text-sm"
                role="alert"
                aria-live="polite"
                :class="{ invisible: !showWarning }">
                <OIcon
                  collection="material-symbols"
                  name="warning"
                  class="size-4 shrink-0 text-amber-600 dark:text-amber-400"
                  aria-hidden="true" />
                {{ t('web.private.only_see_once') }}
              </p>
              <CopyButton
                v-if="details.secret_value"
                class="ml-auto"
                :text="details.secret_value" />
            </div>
          </section>

          <!-- Encrypted Content Placeholder -->
          <!-- prettier-ignore-attribute class -->
          <section
            v-if="!details.show_secret && !record.is_destroyed"
            class="border-y border-gray-200/60 bg-gradient-to-r from-gray-200 to-gray-100 p-4 sm:p-6
            dark:border-gray-700/60 dark:from-gray-800/80 dark:to-gray-800/30">
            <!-- prettier-ignore-attribute class -->
            <div
              class="flex items-center justify-between py-2 font-mono
              text-gray-400 dark:text-gray-500">
              <div class="flex flex-1 items-center">
                <span class="inline-block w-full overflow-hidden">
                  <span class="select-none blur-sm">•••••••••••••••••••••••••••••••••••••••</span>
                </span>
                <OIcon
                  collection="material-symbols"
                  name="lock-outline"
                  class="ml-2 size-4 shrink-0 text-gray-400" />
              </div>
              <!-- prettier-ignore-attribute class -->
              <span
                class="rounded-full bg-gray-50 px-2 py-1
                text-xs font-medium text-gray-600 ring-1 ring-inset ring-gray-500/20
                dark:bg-gray-700 dark:text-gray-300 dark:ring-gray-500/30">
                {{ t('web.LABELS.encrypted') }}
              </span>
            </div>
          </section>

          <!-- Status & Timeline with Improved Layout -->
          <section
            class="p-4 sm:p-6"
            aria-labelledby="section-status">
            <div class="mb-3 flex items-center justify-between">
              <h2
                id="section-status"
                class="flex items-center text-base font-medium text-gray-600 dark:text-gray-300">
                <OIcon
                  collection="material-symbols"
                  name="history"
                  class="mr-2"
                  size="5" />
                {{ t('web.LABELS.timeline') }}
              </h2>
              <StatusBadge
                :record="record"
                :expires-in="details?.secret_realttl ?? undefined" />
            </div>

            <TimelineDisplay
              :record="record"
              :details="details" />
          </section>

          <!-- Actions Section with Improved Layout -->
          <!-- prettier-ignore-attribute class -->
          <section
            v-if="isAvailable"
            class="border-t border-gray-200/60 bg-gray-50 p-4 sm:p-6
            dark:border-gray-700/60 dark:bg-gray-800/30"
            aria-labelledby="section-actions">
            <h2
              id="section-actions"
              class="sr-only">
              {{ t('web.LABELS.actions') }}
            </h2>

            <BurnButtonForm
              :record="record"
              :details="details" />
          </section>
        </div>

        <!-- Help Section with Card Styling -->
        <!-- prettier-ignore-attribute class -->
        <section
          v-if="isAvailable"
          aria-labelledby="section-help"
          class="relative rounded-xl border border-gray-200/60
          bg-white/60 p-4 shadow-sm backdrop-blur-sm sm:p-6
          dark:border-gray-700/60 dark:bg-gray-800/60">
          <NeedHelpModal>
            <template #content>
              <ReceiptFAQ
                :record="record"
                :details="details" />
            </template>
          </NeedHelpModal>
        </section>
      </div>
    </div>
  </div>
</template>

<style scoped></style>
