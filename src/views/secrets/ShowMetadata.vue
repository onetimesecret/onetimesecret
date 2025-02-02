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
  <div class="">
    <DashboardTabNav />

    <MetadataSkeleton v-if="isLoading" />

    <div v-else-if="!record || !details">
      <UnknownMetadata />
    </div>

    <div
      v-else-if="record && details"
      class="space-y-8 bg-gradient-to-b from-slate-50 to-slate-100 dark:from-slate-900 dark:to-slate-950 rounded-lg p-6">
      <!-- Secret Link Header -->
      <section
        class="animate-fade-in relative"
        aria-labelledby="secret-header">

        <SecretLink
          v-if="isAvailable"
          :record="record"
          :details="details"
          :isInitialView="!record.is_viewed"
          class="focus-within:ring-2 focus-within:ring-brand-500 rounded-lg" />
      </section>

      <!-- Secret Value -->
      <section
        v-if="details.show_secret"
        class="bg-slate-50 dark:bg-slate-800 dark:bg-opacity-50 rounded-lg p-4">
        <textarea
          readonly
          :value="details.secret_value"
          :rows="details.display_lines || 3"
          class="font-mono text-base leading-tight tracking-wide whitespace-pre shadow-sm transition-colors px-4 py-3 w-full resize-none rounded-lg border-2 border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 text-slate-900 dark:text-slate-100 focus:ring-2 focus:ring-brand-500 focus:border-brand-500 dark:focus:border-brand-400"></textarea>
        <div class="flex items-center justify-between w-full mt-2">
          <p
            class="text-sm text-amber-600 dark:text-amber-400 opacity-80 flex items-center gap-2"
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
            class="ml-auto"
            :text="details.secret_value" />
        </div>
      </section>

      <section
        v-if="!details.show_secret && !record.is_destroyed"
        class="bg-slate-200 bg-opacity-50 dark:bg-slate-800 dark:bg-opacity-50 rounded-lg p-4">
        <div
          class="flex items-center justify-between font-mono text-slate-400 dark:text-slate-500">
          <span>•••••••••••••••••••</span>
          <span class="text-xs font-medium">{{ $t('web.LABELS.encrypted') }}</span>
        </div>
      </section>

      <!-- Status & Timeline -->
      <section
        class="bg-slate-50 dark:bg-slate-800 rounded-lg p-4"
        aria-labelledby="section-status">
        <div class="flex items-center justify-between mb-2">
          <h2
            id="section-status"
            class="text-sm font-medium text-slate-700 dark:text-slate-300">
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

      <!-- Actions -->
      <section
        v-if="true"
        class="flex flex-col gap-3"
        aria-labelledby="section-actions">
        <h2
          id="section-actions"
          class="sr-only">
          {{ $t('web.LABELS.actions') }}
        </h2>

        <BurnButtonForm
          :record="record"
          :details="details"
          class="pt-2" />

        <router-link
          type="button"
          to="/"
          class="inline-flex items-center justify-center px-4 py-2 text-sm font-brand text-slate-700 bg-white border border-slate-300 rounded-md dark:bg-slate-800 hover:bg-slate-50 dark:hover:bg-slate-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brand-500 dark:text-slate-200 dark:border-slate-600 dark:focus:ring-offset-slate-900">
          {{ $t('create-another-secret') }}
        </router-link>
      </section>

      <!-- Recipients Section -->
      <div
        v-if="details.show_recipients"
        class="border-t border-slate-100 py-4 dark:border-slate-800">
        <h3 class="text-lg font-semibold text-slate-800 dark:text-slate-200">
          {{ $t('web.COMMON.sent_to') }} {{ record.recipients }}
        </h3>
      </div>

      <!-- Help Section -->
      <section
        aria-labelledby="section-help"
        class="relative">
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
