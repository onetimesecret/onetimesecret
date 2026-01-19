<!-- src/apps/workspace/components/domains/DnsWidget.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import { useDnsWidget, type DnsRecord } from '@/shared/composables/useDnsWidget';
  import { computed, onMounted, watch } from 'vue';

  interface Props {
    /** The domain to configure DNS for */
    domain: string;
    /** The IP address or hostname to point the domain at */
    targetAddress: string;
    /** Whether this is an apex domain (requires A record instead of CNAME) */
    isApex?: boolean;
    /** Optional TXT record for domain ownership validation */
    txtValidationHost?: string;
    txtValidationValue?: string;
  }

  const props = defineProps<Props>();
  const emit = defineEmits<{
    (e: 'records-verified', records: unknown[]): void;
    (e: 'verification-failed', records: unknown[]): void;
    (e: 'partial-verification', records: unknown[]): void;
  }>();

  const { t } = useI18n();

  // Build DNS records based on whether it's an apex domain
  const dnsRecords = computed<DnsRecord[]>(() => {
    const records: DnsRecord[] = [];

    // For apex domains, use A record; otherwise use CNAME
    if (props.isApex) {
      records.push({
        type: 'A',
        host: '@',
        value: props.targetAddress,
        ttl: 3600,
      });
    } else {
      records.push({
        type: 'CNAME',
        host: '@',
        value: props.targetAddress,
        ttl: 3600,
      });
    }

    // Add TXT record for validation if provided
    if (props.txtValidationHost && props.txtValidationValue) {
      records.push({
        type: 'TXT',
        host: props.txtValidationHost,
        value: props.txtValidationValue,
        ttl: 3600,
      });
    }

    return records;
  });

  const { isLoading, error, initWidget, stopWidget } = useDnsWidget({
    dnsRecords: dnsRecords.value,
    domain: props.domain,
    onRecordsVerified: (records) => emit('records-verified', records),
    onVerificationFailed: (records) => emit('verification-failed', records),
    onPartialVerification: (records) => emit('partial-verification', records),
  });

  // Initialize widget when component mounts
  onMounted(async () => {
    await initWidget();
  });

  // Re-initialize if domain changes
  watch(
    () => props.domain,
    async (newDomain, oldDomain) => {
      if (newDomain !== oldDomain && newDomain) {
        stopWidget();
        await initWidget();
      }
    }
  );
</script>

<template>
  <div class="dns-widget-container">
    <!-- Loading state -->
    <div
      v-if="isLoading"
      class="flex items-center justify-center py-8">
      <div class="h-8 w-8 animate-spin rounded-full border-4 border-brand-500 border-t-transparent" ></div>
      <span class="ml-3 text-gray-600 dark:text-gray-400">
        {{ t('web.COMMON.loading') }}
      </span>
    </div>

    <!-- Error state -->
    <div
      v-else-if="error"
      class="rounded-lg border border-red-200 bg-red-50 p-4 dark:border-red-800 dark:bg-red-900/20">
      <p class="text-red-700 dark:text-red-400">
        {{ error }}
      </p>
    </div>

    <!-- Widget container -->
    <div
      v-show="!isLoading && !error"
      id="apxdnswidget"
      class="apxdnswidget" ></div>
  </div>
</template>

<style>
  /* Dark mode overrides for Approximated DNS widget */
  .dark .apxdnswidget {
    --text-color: #e5e7eb;
    --light-text-color: #9ca3af;
    --link-text-color: #60a5fa;
    --main-bg-color: transparent;
    --shaded-bg-color: #1f2937;
    --shaded-border: 1px solid #374151;
    --button-bg-color: #3b82f6;
    --button-text-color: #ffffff;
    --border-color: #374151;
  }

  /* Ensure widget inputs match dark mode */
  .dark .apxdnswidget input {
    background-color: #1f2937;
    border-color: #374151;
    color: #e5e7eb;
  }

  .dark .apxdnswidget input:focus {
    border-color: #3b82f6;
  }

  .dark .apxdnswidget .apxdns-button {
    background-color: #3b82f6;
    border-color: #3b82f6;
  }

  .dark .apxdnswidget .apxdns-button:hover {
    background-color: #2563eb;
    border-color: #2563eb;
  }

  /* Widget container styling */
  .dns-widget-container {
    margin-top: 1.5rem;
  }

  .dns-widget-container .apxdnswidget {
    max-width: 100%;
  }
</style>
