<!-- src/apps/workspace/components/domains/DomainEmailDnsRecords.vue -->

<script setup lang="ts">
/**
 * DNS Records display for domain email configuration.
 *
 * Shows DNS records required for email authentication (SPF, DKIM, DMARC) as
 * vertical cards with per-record status indicators and copy-to-clipboard
 * functionality. Values render fully visible (no truncation) so DKIM keys
 * and long hostnames are copyable. Includes a "Re-validate" button.
 */
import { useI18n } from 'vue-i18n';
import { ref, computed } from 'vue';
import OIcon from '@/shared/components/icons/OIcon.vue';
import { useClipboard } from '@/shared/composables/useClipboard';
import type { EmailDnsRecord, EmailValidationStatus } from '@/schemas/contracts/email-config';

interface Props {
  dnsRecords: EmailDnsRecord[];
  validationStatus: EmailValidationStatus;
  lastValidatedAt: Date | null;
  dnsCheckCompletedAt: Date | null;
  providerCheckCompletedAt: Date | null;
  lastError: string | null;
  isValidating: boolean;
}

const props = defineProps<Props>();

const emit = defineEmits<{
  (e: 'validate'): void;
}>();

const { t } = useI18n();

// Per-record clipboard state (keyed by record index)
const copiedIndex = ref<number | null>(null);
const { copyToClipboard } = useClipboard();

const handleCopy = async (value: string, index: number) => {
  const success = await copyToClipboard(value);
  if (success) {
    copiedIndex.value = index;
    setTimeout(() => {
      if (copiedIndex.value === index) {
        copiedIndex.value = null;
      }
    }, 2000);
  }
};

/** Whether both DNS and provider checks have completed. */
const bothChecksComplete = computed(() =>
  props.dnsCheckCompletedAt !== null && props.providerCheckCompletedAt !== null
);

/** Effective validation status accounting for check completion. */
const effectiveStatus = computed(() => {
  if (props.isValidating || !bothChecksComplete.value) return 'pending';
  return props.validationStatus;
});

/** Format the last validated date for display. */
const formatDate = (date: Date): string => new Intl.DateTimeFormat(undefined, {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  }).format(date);
</script>

<template>
  <section
    aria-labelledby="dns-records-heading"
    class="space-y-4">
    <!-- Header -->
    <div class="flex items-start justify-between">
      <div>
        <h3
          id="dns-records-heading"
          class="text-base font-semibold text-gray-900 dark:text-white">
          {{ t('web.domains.email.dns_records_title') }}
        </h3>
        <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.domains.email.dns_records_description') }}
        </p>
      </div>

      <!-- Re-validate button -->
      <button
        type="button"
        @click="emit('validate')"
        :disabled="isValidating"
        class="inline-flex items-center gap-2 rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-gray-600 dark:text-gray-100 dark:ring-gray-500 dark:hover:bg-gray-500">
        <OIcon
          v-if="isValidating"
          collection="heroicons"
          name="arrow-path"
          class="size-4 animate-spin"
          aria-hidden="true" />
        <OIcon
          v-else
          collection="heroicons"
          name="arrow-path"
          class="size-4"
          aria-hidden="true" />
        {{ isValidating ? t('web.domains.email.validating') : t('web.domains.email.revalidate') }}
      </button>
    </div>

    <!-- Validation status banner -->
    <div
      v-if="effectiveStatus === 'verified'"
      class="flex items-center gap-2 rounded-md bg-emerald-50 px-4 py-3 dark:bg-emerald-900/20"
      role="status">
      <OIcon
        collection="heroicons"
        name="check-circle-solid"
        class="size-5 text-emerald-500"
        aria-hidden="true" />
      <span class="text-sm font-medium text-emerald-800 dark:text-emerald-200">
        {{ t('web.domains.email.domain_verified') }}
      </span>
      <span
        v-if="lastValidatedAt"
        class="ml-auto text-xs text-emerald-600 dark:text-emerald-400">
        {{ t('web.domains.email.last_validated') }}: {{ formatDate(lastValidatedAt) }}
      </span>
    </div>

    <div
      v-else-if="effectiveStatus === 'failed'"
      class="rounded-md bg-rose-50 px-4 py-3 dark:bg-rose-900/20"
      role="alert">
      <div class="flex items-center gap-2">
        <OIcon
          collection="heroicons"
          name="x-circle-solid"
          class="size-5 text-rose-500"
          aria-hidden="true" />
        <span class="text-sm font-medium text-rose-800 dark:text-rose-200">
          {{ t('web.domains.email.validation_failed') }}
        </span>
        <span
          v-if="lastValidatedAt"
          class="ml-auto text-xs text-rose-600 dark:text-rose-400">
          {{ t('web.domains.email.last_validated') }}: {{ formatDate(lastValidatedAt) }}
        </span>
      </div>
      <p
        v-if="lastError"
        class="mt-1 ml-7 text-sm text-rose-700 dark:text-rose-300">
        {{ lastError }}
      </p>
    </div>

    <div
      v-else
      class="flex items-center gap-2 rounded-md bg-amber-50 px-4 py-3 dark:bg-amber-900/20"
      role="status">
      <OIcon
        collection="heroicons"
        name="clock"
        class="size-5 text-amber-500"
        aria-hidden="true" />
      <span class="text-sm font-medium text-amber-800 dark:text-amber-200">
        {{ t('web.domains.email.status_pending') }}
      </span>
    </div>

    <!-- DNS Records Cards -->
    <div
      v-if="dnsRecords.length > 0"
      class="space-y-3">
      <div
        v-for="(record, index) in dnsRecords"
        :key="index"
        data-testid="dns-record-card"
        class="rounded-lg border border-gray-200 bg-white p-4 dark:border-gray-700 dark:bg-gray-900">
        <!-- Card header: type badge + status -->
        <div class="flex items-center justify-between">
          <span class="inline-flex rounded bg-gray-100 px-2 py-0.5 text-xs font-medium text-gray-700 dark:bg-gray-700 dark:text-gray-300">
            {{ record.type }}
          </span>
          <!-- DNS + Resolving dual indicators -->
          <div class="inline-flex items-center gap-3">
            <span
              class="inline-flex items-center gap-1"
              :class="record.dns_exists === true ? 'text-emerald-600 dark:text-emerald-400' : 'text-gray-300 dark:text-gray-600'">
              <OIcon
                collection="heroicons"
                name="check-circle-solid"
                class="size-4"
                aria-hidden="true" />
              <span class="text-xs font-medium">DNS</span>
            </span>
            <span
              class="inline-flex items-center gap-1"
              :class="validationStatus === 'verified' ? 'text-emerald-600 dark:text-emerald-400' : 'text-gray-300 dark:text-gray-600'">
              <OIcon
                collection="heroicons"
                name="check-circle-solid"
                class="size-4"
                aria-hidden="true" />
              <span class="text-xs font-medium">Resolving</span>
            </span>
          </div>
        </div>

        <!-- Name field -->
        <div class="mt-3">
          <div class="flex items-start justify-between gap-2">
            <span class="text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
              {{ t('web.domains.email.dns_column_name') }}
            </span>
            <button
              type="button"
              @click="handleCopy(record.name, index * 2)"
              class="flex-shrink-0 rounded p-1 text-gray-400 hover:bg-gray-100 hover:text-gray-600 dark:hover:bg-gray-700 dark:hover:text-gray-300"
              :aria-label="`${t('web.domains.email.copy')} ${record.name}`">
              <OIcon
                v-if="copiedIndex === index * 2"
                collection="heroicons"
                name="check"
                class="size-4 text-emerald-500"
                aria-hidden="true" />
              <OIcon
                v-else
                collection="heroicons"
                name="clipboard-document"
                class="size-4"
                aria-hidden="true" />
            </button>
          </div>
          <code class="mt-1 block break-all text-sm text-gray-900 dark:text-gray-100">
            {{ record.name }}
          </code>
        </div>

        <!-- Value field -->
        <div class="mt-3">
          <div class="flex items-start justify-between gap-2">
            <span class="text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
              {{ t('web.domains.email.dns_column_value') }}
            </span>
            <button
              type="button"
              @click="handleCopy(record.value, index * 2 + 1)"
              class="flex-shrink-0 rounded p-1 text-gray-400 hover:bg-gray-100 hover:text-gray-600 dark:hover:bg-gray-700 dark:hover:text-gray-300"
              :aria-label="`${t('web.domains.email.copy')} ${record.value}`">
              <OIcon
                v-if="copiedIndex === index * 2 + 1"
                collection="heroicons"
                name="check"
                class="size-4 text-emerald-500"
                aria-hidden="true" />
              <OIcon
                v-else
                collection="heroicons"
                name="clipboard-document"
                class="size-4"
                aria-hidden="true" />
            </button>
          </div>
          <code class="mt-1 block break-all text-sm text-gray-900 dark:text-gray-100">
            {{ record.value }}
          </code>
        </div>
      </div>
    </div>

    <!-- Empty state (no DNS records) -->
    <div
      v-else
      class="rounded-lg border border-dashed border-gray-300 p-6 text-center dark:border-gray-600">
      <OIcon
        collection="heroicons"
        name="server-stack"
        class="mx-auto size-8 text-gray-400"
        aria-hidden="true" />
      <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.domains.email.dns_records_description') }}
      </p>
    </div>
  </section>
</template>
