<script setup lang="ts">
  import DashboardTabNav from '@/components/dashboard/DashboardTabNav.vue';
  import BurnButtonForm from '@/components/secrets/metadata/BurnButtonForm.vue';
  // import MetadataDisplayCase from '@/components/secrets/metadata/MetadataDisplayCase.vue';
  import MetadataSkeleton from '@/components/closet/MetadataSkeleton.vue';
  import StatusBadge from '@/components/secrets/metadata/StatusBadge.vue';
  import TimelineDisplay from '@/components/secrets/metadata/TimelineDisplay.vue';
  import NeedHelpModal from '@/components/modals/NeedHelpModal.vue';
  import SecretLink from '@/components/secrets/metadata/SecretLink.vue';
  import CopyButton from '@/components/CopyButton.vue';
  import OIcon from '@/components/icons/OIcon.vue';
  import UnknownMetadata from './UnknownMetadata.vue';
  import { useMetadata } from '@/composables/useMetadata';
  import { onMounted, onUnmounted, watch, computed } from 'vue';

  // Define props
  interface Props {
    metadataKey: string;
  }
  const props = defineProps<Props>();

  const { record, details, isLoading, fetch, reset } = useMetadata(props.metadataKey);

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
        <h1
          id="secret-header"
          class="sr-only">
          {{ $t('web.LABELS.secret_link') }}
        </h1>

        <!-- Passphrase Indicator -->
        <div
          v-if="details?.has_passphrase"
          class="absolute -top-4 right-2 flex items-center gap-2 text-sm text-amber-600 dark:text-amber-400">
          <OIcon
            collection=""
            name="mdi-lock"
            class="w-4 h-4" />
          {{ $t('web.COMMON.passphrase_protected') }}
        </div>

        <SecretLink
          v-if="details.show_secret_link && isAvailable"
          :record="record"
          :details="details"
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
          class="
            font-mono text-base leading-tight tracking-wide whitespace-pre shadow-sm transition-colors px-4 py-3
            w-full resize-none rounded-lg border-2 border-slate-200
            dark:border-slate-700 bg-white dark:bg-slate-900 text-slate-900 dark:text-slate-100
            focus:ring-2 focus:ring-brand-500 focus:border-brand-500 dark:focus:border-brand-400"></textarea>
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
          <CopyButton class="ml-auto" />
        </div>
      </section>

      <section
        v-if="!details.show_secret && !record.is_destroyed"
        class="bg-slate-200 bg-opacity-50 dark:bg-slate-800 dark:bg-opacity-50 rounded-lg p-4">
        <div
          class="flex items-center justify-between font-mono text-slate-400 dark:text-slate-500">
          <span>•••••••••••••••••••</span>
          <span class="text-xs font-medium">Encrypted</span>
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

      <!-- Sharing Instructions -->
      <section
        class="bg-slate-50 dark:bg-slate-800 rounded-lg p-4 space-y-3"
        aria-labelledby="section-sharing">
        <h2
          id="section-sharing"
          class="text-sm font-medium text-slate-700 dark:text-slate-300">
          {{ $t('web.INSTRUCTION.sharing_instructions') }}
        </h2>

        <ul class="space-y-2 text-sm text-slate-600 dark:text-slate-400">
          <li class="flex items-start gap-2">
            <OIcon
              collection="mdi"
              name="link"
              class="w-5 h-5 mt-0.5 text-brand-500"
              aria-hidden="true" />
            {{ $t('web.INSTRUCTION.share_link_instruction') }}
          </li>
          <li
            v-if="details.has_passphrase"
            class="flex items-start gap-2">
            <OIcon
              collection="mdi"
              name="key"
              class="w-5 h-5 mt-0.5 text-amber-500"
              aria-hidden="true" />
            {{ $t('web.INSTRUCTION.share_passphrase_instruction') }}
          </li>
          <li class="flex items-start gap-2">
            <OIcon
              collection="mdi"
              name="shield-alert"
              class="w-5 h-5 mt-0.5 text-red-500"
              aria-hidden="true" />
            {{ $t('web.INSTRUCTION.secure_channel_instruction') }}
          </li>
        </ul>
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
          class="inline-flex items-center justify-center px-4 py-2 text-sm font-brand text-slate-700 bg-white border border-slate-300 rounded-md hover:bg-slate-50 dark:bg-slate-800 dark:text-slate-200 dark:border-slate-600 dark:hover:bg-slate-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brand-500 dark:focus:ring-offset-slate-900">
          Create another secret
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
        <NeedHelpModal
          :record="record"
          :details="details" />
      </section>
    </div>
  </div>
</template>
