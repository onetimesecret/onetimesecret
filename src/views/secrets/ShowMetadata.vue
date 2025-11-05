<!-- src/views/secrets/ShowMetadata.vue -->

<script setup lang="ts">
  import MetadataSkeleton from '@/components/closet/MetadataSkeleton.vue';
  import CopyButton from '@/components/CopyButton.vue';
  import DashboardTabNav from '@/components/dashboard/DashboardTabNav.vue';
  import OIcon from '@/components/icons/OIcon.vue';
  import NeedHelpModal from '@/components/modals/NeedHelpModal.vue';
  import BurnButtonForm from '@/components/secrets/metadata/BurnButtonForm.vue';
  import MetadataFAQ from '@/components/secrets/metadata/MetadataFAQ.vue';
  import SecretLink from '@/components/secrets/metadata/SecretLink.vue';
  import StatusBadge from '@/components/secrets/metadata/StatusBadge.vue';
  import TimelineDisplay from '@/components/secrets/metadata/TimelineDisplay.vue';
  import { useMetadata } from '@/composables/useMetadata';
  import { useSecretExpiration, EXPIRATION_EVENTS } from '@/composables/useSecretExpiration';
  import { onMounted, onUnmounted, watch, computed, ref } from 'vue';

  import UnknownMetadata from './UnknownMetadata.vue';

  // Define props
  interface Props {
    metadataIdentifier: string;
  }
  const props = defineProps<Props>();

  // State for delayed warning message
  const showWarning = ref(false);
  const warningMessage = ref<HTMLElement | null>(null);

  const { record, details, isLoading, fetch, reset } = useMetadata(props.metadataIdentifier);

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
    () => props.metadataIdentifier,
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
    <DashboardTabNav />

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
        {{ $t('back') }}
      </button>

      <MetadataSkeleton v-if="isLoading" />

      <div v-else-if="!record || !details">
        <UnknownMetadata />
      </div>

      <div
        v-else-if="record && details"
        class="mx-auto max-w-3xl space-y-8">
        <!-- Main Card with Enhanced Styling -->
        <!-- prettier-ignore-attribute class -->
        <div
          class="overflow-hidden rounded-xl border border-slate-200/50
          bg-gradient-to-b from-slate-50 to-slate-100 shadow-md
          dark:border-slate-800/50 dark:from-slate-900 dark:to-slate-950 dark:shadow-slate-900/30">
          <!-- Secret Link Header -->
          <section
            class="relative transition-transform duration-300 hover:scale-[1.01]"
            aria-labelledby="secret-header">
            <SecretLink
              v-if="isAvailable"
              :record="record"
              :details="details"
              :is-initial-view="!record.is_viewed"
            />
          </section>

          <!-- Recipients Section -->
          <div
            v-if="details.show_recipients"
            class="border-t border-slate-200 px-6 py-5 dark:border-slate-800">
            <h3 class="flex items-center text-lg font-semibold text-slate-800 dark:text-slate-200">
              <OIcon
                collection="material-symbols"
                name="mail-outline"
                class="mr-2 size-5 text-brand-500 dark:text-brand-400" />
              {{ $t('web.COMMON.sent_to') }} {{ record.recipients }}
            </h3>
          </div>

          <!-- Secret Value with Enhanced Styling -->
          <!-- prettier-ignore-attribute class -->
          <section
            v-if="details.show_secret"
            class="border-y border-slate-200 bg-slate-50 px-6 py-5
            dark:border-slate-700/50 dark:bg-slate-800/60">
            <!-- prettier-ignore-attribute class -->
            <textarea
              readonly
              :value="details.secret_value"
              :rows="details.display_lines || 3"
              class="w-full resize-none whitespace-pre
              rounded-lg border-2 border-slate-200 bg-white px-4 py-3
              font-mono text-base leading-tight tracking-wide text-slate-900 shadow-sm transition-colors
              focus:border-brand-500 focus:ring-2 focus:ring-brand-500
              dark:border-slate-700 dark:bg-slate-900 dark:text-slate-100 dark:focus:border-brand-400"></textarea>
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
                {{ $t('web.private.only_see_once') }}
              </p>
              <CopyButton
                v-if="details.secret_value"
                class="ml-auto transition-transform hover:scale-105"
                :text="details.secret_value" />
            </div>
          </section>

          <!-- Encrypted Content Placeholder -->
          <!-- prettier-ignore-attribute class -->
          <section
            v-if="!details.show_secret && !record.is_destroyed"
            class="border-y border-slate-200 bg-gradient-to-r from-slate-200 to-slate-100 px-6 py-5
            dark:border-slate-700/50 dark:from-slate-800/80 dark:to-slate-800/30">
            <!-- prettier-ignore-attribute class -->
            <div
              class="flex items-center justify-between py-2 font-mono
              text-slate-400 dark:text-slate-500">
              <div class="flex flex-1 items-center">
                <span class="inline-block w-full overflow-hidden">
                  <span class="select-none blur-sm">•••••••••••••••••••••••••••••••••••••••</span>
                </span>
                <OIcon
                  collection="material-symbols"
                  name="lock-outline"
                  class="ml-2 size-4 shrink-0 text-slate-400" />
              </div>
              <!-- prettier-ignore-attribute class -->
              <span
                class="rounded-full bg-slate-300/50 px-2 py-1
                text-xs font-medium dark:bg-slate-700/50">
                {{ $t('web.LABELS.encrypted') }}
              </span>
            </div>
          </section>

          <!-- Status & Timeline with Improved Layout -->
          <section
            class="px-6 py-5"
            aria-labelledby="section-status">
            <div class="mb-3 flex items-center justify-between">
              <h2
                id="section-status"
                class="flex items-center text-sm font-medium text-slate-700 dark:text-slate-300">
                <OIcon
                  collection="material-symbols"
                  name="history"
                  class="mr-2"
                  size="5" />
                {{ $t('web.LABELS.timeline') }}
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
            class="border-t border-slate-200 bg-slate-50 px-6 py-5
            dark:border-slate-700/50 dark:bg-slate-800/30"
            aria-labelledby="section-actions">
            <h2
              id="section-actions"
              class="sr-only">
              {{ $t('web.LABELS.actions') }}
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
          class="relative mt-6 rounded-xl border border-slate-200/80
          bg-white p-5 shadow-sm
          dark:border-slate-700/50 dark:bg-slate-800/30">
          <NeedHelpModal>
            <template #content>
              <MetadataFAQ
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
