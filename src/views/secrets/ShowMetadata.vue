<script setup lang="ts">
  import DashboardTabNav from '@/components/dashboard/DashboardTabNav.vue';
  import BurnButtonForm from '@/components/secrets/metadata/BurnButtonForm.vue';
  import MetadataSkeleton from '@/components/closet/MetadataSkeleton.vue';
  import StatusBadge from '@/components/secrets/metadata/StatusBadge.vue';
  import TimelineDisplay from '@/components/secrets/metadata/TimelineDisplay.vue';
  import NeedHelpModal from '@/components/modals/NeedHelpModal.vue';
  import SecretLink from '@/components/secrets/metadata/SecretLink.vue';
  import CopyButton from '@/components/CopyButton.vue';
  import OIcon from '@/components/icons/OIcon.vue';
  import MetadataFAQ from '@/components/secrets/metadata/MetadataFAQ.vue';
  import UnknownMetadata from './UnknownMetadata.vue';
  import { useMetadata } from '@/composables/useMetadata';
  import { onMounted, onUnmounted, watch, computed } from 'vue';
  import { useSecretExpiration, EXPIRATION_EVENTS } from '@/composables/useSecretExpiration';

  // Define props
  interface Props {
    metadataKey: string;
  }
  const props = defineProps<Props>();

  const { record, details, isLoading, fetch, reset } = useMetadata(props.metadataKey);

  const { onExpirationEvent } = useSecretExpiration(
    record.value?.created ?? new Date(),
    record.value?.expiration_in_seconds ?? 0
  );

  const isAvailable = computed(() => {
    return !(
      record.value?.is_destroyed ||
      record.value?.is_burned ||
      record.value?.is_received
    );
  });

  // Watch for route parameter changes to refetch data
  watch(
    () => props.metadataKey,
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
  });

  // Ensure cleanup when component unmounts
  onUnmounted(() => {
    reset();
  });
</script>

<template>
  <div class="min-h-screen">
    <DashboardTabNav />

    <MetadataSkeleton v-if="isLoading" />

    <div v-else-if="!record || !details">
      <UnknownMetadata />
    </div>

    <div
      v-else-if="record && details"
      class="max-w-3xl mx-auto py-8 space-y-8 animate-fade-in-up">

      <!-- Main Card with Enhanced Styling -->
      <div class="overflow-hidden bg-gradient-to-b from-slate-50 to-slate-100 dark:from-slate-900 dark:to-slate-950
                  rounded-xl shadow-md dark:shadow-slate-900/30 border border-slate-200/50 dark:border-slate-800/50">

        <!-- Secret Link Header -->
        <section
          v-if="!details.show_recipients"
          class="relative transform transition-transform duration-300 hover:scale-[1.01]"
          aria-labelledby="secret-header">

          <SecretLink
            v-if="isAvailable"
            :record="record"
            :details="details"
            :isInitialView="!record.is_viewed"
            class="focus-within:ring-2 focus-within:ring-brand-500 rounded-lg" />
        </section>

        <!-- Recipients Section -->
        <div
          v-if="details.show_recipients"
          class="border-t border-slate-200 py-5 px-6 dark:border-slate-800">
          <h3 class="text-lg font-semibold text-slate-800 dark:text-slate-200 flex items-center">
            <OIcon
              collection="material-symbols"
              name="mail-outline"
              class="w-5 h-5 mr-2 text-brand-500 dark:text-brand-400" />
            {{ $t('web.COMMON.sent_to') }} {{ record.recipients }}
          </h3>
        </div>

        <!-- Secret Value with Enhanced Styling -->
        <section
          v-if="details.show_secret"
          class="px-6 py-5 bg-slate-50 dark:bg-slate-800/60 border-y border-slate-200 dark:border-slate-700/50">
          <textarea
            readonly
            :value="details.secret_value"
            :rows="details.display_lines || 3"
            class="font-mono text-base leading-tight tracking-wide whitespace-pre shadow-sm transition-colors px-4 py-3 w-full resize-none rounded-lg border-2 border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 text-slate-900 dark:text-slate-100 focus:ring-2 focus:ring-brand-500 focus:border-brand-500 dark:focus:border-brand-400"></textarea>
          <div class="flex items-center justify-between w-full mt-3">
            <p
              class="text-sm text-amber-600 dark:text-amber-400 opacity-80 flex items-center gap-2 animate-pulse-slow"
              role="alert"
              aria-live="polite">
              <OIcon
                collection="material-symbols"
                name="warning"
                class="w-4 h-4 flex-shrink-0"
                aria-hidden="true" />
              {{ $t('web.private.only_see_once') }}
            </p>
            <CopyButton
              v-if="details.secret_value"
              class="ml-auto hover:scale-105 transition-transform"
              :text="details.secret_value" />
          </div>
        </section>

        <!-- Encrypted Content Placeholder -->
        <section
          v-if="!details.show_secret && !record.is_destroyed"
          class="px-6 py-5 bg-gradient-to-r from-slate-200 to-slate-100 dark:from-slate-800/80 dark:to-slate-800/30 border-y border-slate-200 dark:border-slate-700/50">
          <div
            class="flex items-center justify-between font-mono text-slate-400 dark:text-slate-500 py-2">
            <div class="flex-1 flex items-center">
              <span class="inline-block w-full overflow-hidden">
                <span class="blur-sm select-none">•••••••••••••••••••••••••••••••••••••••</span>
              </span>
              <OIcon
                collection="material-symbols"
                name="lock-outline"
                class="flex-shrink-0 h-4 w-4 ml-2 text-slate-400" />
            </div>
            <span class="text-xs font-medium px-2 py-1 rounded-full bg-slate-300/50 dark:bg-slate-700/50">
              {{ $t('web.LABELS.encrypted') }}
            </span>
          </div>
        </section>

        <!-- Status & Timeline with Improved Layout -->
        <section
          class="px-6 py-5"
          aria-labelledby="section-status">
          <div class="flex items-center justify-between mb-3">
            <h2
              id="section-status"
              class="text-sm font-medium text-slate-700 dark:text-slate-300 flex items-center">
              <OIcon
                collection="material-symbols"
                name="history"
                class="w-4 h-4 mr-2 text-brand-500 dark:text-brand-400" />
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
        <section
          v-if="true"
          class="px-6 py-5 bg-slate-50 dark:bg-slate-800/30 border-t border-slate-200 dark:border-slate-700/50"
          aria-labelledby="section-actions">
          <h2
            id="section-actions"
            class="sr-only">
            {{ $t('web.LABELS.actions') }}
          </h2>

          <BurnButtonForm
            :record="record"
            :details="details" />

          <router-link
            type="button"
            to="/"
            class="mt-16 mb-4 w-full inline-flex items-center justify-center px-4 py-2.5 text-sm font-brand text-slate-700 bg-white border border-slate-300 rounded-md dark:bg-slate-800 hover:bg-slate-50 dark:hover:bg-slate-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brand-500 dark:text-slate-200 dark:border-slate-600 dark:focus:ring-offset-slate-900 transition-colors duration-200">
            <OIcon
              collection="material-symbols"
              name="add"
              class="w-4 h-4 mr-2" />
            {{ $t('create-another-secret') }}
          </router-link>
        </section>
      </div>

      <!-- Help Section with Card Styling -->
      <section
        aria-labelledby="section-help"
        class="mt-6 bg-white dark:bg-slate-800/30 rounded-xl shadow-sm border border-slate-200/80 dark:border-slate-700/50 p-5 relative">
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
</template>

<style scoped>
.animate-fade-in-up {
  animation: fadeInUp 0.5s ease-out forwards;
}

@keyframes fadeInUp {
  from {
    opacity: 0;
    transform: translateY(10px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

.animate-pulse-slow {
  animation: pulseSlow 3s infinite;
}

@keyframes pulseSlow {
  0%, 100% {
    opacity: 1;
  }
  50% {
    opacity: 0.6;
  }
}
</style>
