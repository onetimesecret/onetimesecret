<script setup lang="ts">
  import DashboardTabNav from '@/components/dashboard/DashboardTabNav.vue';
  import BurnButtonForm from '@/components/secrets/metadata/BurnButtonForm.vue';
  // import MetadataDisplayCase from '@/components/secrets/metadata/MetadataDisplayCase.vue';
  import MetadataSkeleton from '@/components/closet/MetadataSkeleton.vue';
  import StatusBadge from '@/components/secrets/metadata/StatusBadge.vue';
  import TimelineDisplay from '@/components/secrets/metadata/TimelineDisplay.vue';
  import NeedHelpModal from '@/components/modals/NeedHelpModal.vue';
  import SecretLink from '@/components/secrets/metadata/SecretLink.vue';
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
      details.value?.is_destroyed ||
      details.value?.is_burned ||
      details.value?.is_received
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
      class="space-y-8">
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

      <!-- Status & Timeline -->
      <section
        class="bg-gray-50 dark:bg-gray-800 rounded-lg p-4"
        aria-labelledby="section-status">
        <div class="flex items-center justify-between mb-2">
          <h2
            id="section-status"
            class="text-sm font-medium text-gray-700 dark:text-gray-300">
            {{ $t('web.LABELS.timeline') }}
          </h2>
          <StatusBadge
            :record="record"
            :expires-in="details?.secret_realttl ?? undefined"
            />
        </div>

        <TimelineDisplay
          :record="record"
          :details="details" />
      </section>

      <!-- Sharing Instructions -->
      <section
        class="bg-gray-50 dark:bg-gray-800 rounded-lg p-4 space-y-3"
        aria-labelledby="section-sharing">
        <h2
          id="section-sharing"
          class="text-sm font-medium text-gray-700 dark:text-gray-300">
          {{ $t('web.INSTRUCTION.sharing_instructions') }}
        </h2>

        <ul class="space-y-2 text-sm text-gray-600 dark:text-gray-400">
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
          class="inline-flex items-center justify-center px-4 py-2 text-sm font-brand text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50 dark:bg-gray-800 dark:text-gray-200 dark:border-gray-600 dark:hover:bg-gray-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brand-500 dark:focus:ring-offset-gray-900">
          Create another secret
        </router-link>
      </section>

      <!-- Recipients Section -->
      <div
        v-if="details.show_recipients"
        class="border-t border-gray-100 py-4 dark:border-gray-800">
        <h3 class="text-lg font-semibold text-gray-800 dark:text-gray-200">
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
