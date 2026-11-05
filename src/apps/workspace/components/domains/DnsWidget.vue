<!-- src/apps/workspace/components/domains/DnsWidget.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import Skeleton from '@/shared/components/closet/Skeleton.vue';
  import { useDnsWidget, type DnsRecord } from '@/shared/composables/useDnsWidget';
  import { txtChallengeLabel } from '@/shared/utils/txtRecordName';
  import { computed, onMounted, watch } from 'vue';

  interface Props {
    /** The domain to configure DNS for (e.g., "uk.metalbaum.com") */
    domain: string;
    /** The IP address or hostname to point the domain at */
    targetAddress: string;
    /** Whether this is an apex domain (requires A record instead of CNAME) */
    isApex?: boolean;
    /**
     * TXT record host for domain ownership validation (`txt_validation_host`),
     * relative to the base domain: the challenge label plus the subdomain,
     * e.g. "_onetime-challenge-019bdd2.uk".
     * @see lib/onetime/models/custom_domain.rb#txt_challenge_host
     */
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

  /**
   * The TXT host for the Approximated DNS widget: the challenge label alone.
   *
   * The widget reads each record's `host` as relative to `domain`, the same
   * way '@' below means `domain` itself. txt_validation_host is relative to
   * the base domain instead, so for a subdomain it already carries the
   * subdomain, and passing it as is would name the subdomain twice. Its first
   * label is the challenge label, whatever spelling the subdomain after it
   * has (A-label for new records, as typed for some earlier ones).
   *
   * Example for "uk.metalbaum.com":
   *   - txt_validation_host: "_onetime-challenge-019bdd2.uk"
   *   - Widget host:         "_onetime-challenge-019bdd2"
   *   - Record name:         "_onetime-challenge-019bdd2.uk.metalbaum.com"
   */
  const widgetTxtHost = computed(() => txtChallengeLabel(props.txtValidationHost) || undefined);

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
    if (widgetTxtHost.value && props.txtValidationValue) {
      records.push({
        type: 'TXT',
        host: widgetTxtHost.value,
        value: props.txtValidationValue,
        ttl: 3600,
      });
    }

    return records;
  });

  const { isLoading, error, initWidget, stopWidget } = useDnsWidget({
    dnsRecords: dnsRecords,
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
      role="status"
      aria-busy="true"
      class="animate-pulse space-y-3 py-8 motion-reduce:animate-none">
      <span class="sr-only">{{ t('web.COMMON.loading') }}</span>
      <Skeleton
        :count="4"
        height="h-12"
        rounded="rounded-md"
        :pulse="false" />
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

  /* Ensure all widget inputs match dark mode */
  .dark .apxdnswidget input,
  .dark .apxdnswidget textarea {
    background-color: #374151;
    border-color: #4b5563;
    color: #f3f4f6;
  }

  .dark .apxdnswidget input:focus,
  .dark .apxdnswidget textarea:focus {
    border-color: #3b82f6;
  }

  /* Read-only copy fields (the instruction values) */
  .dark .apxdnswidget .apxdns-input-copy-container input {
    background-color: #1f2937;
    border-color: #374151;
    color: #f3f4f6;
  }

  /* Copy button styling */
  .dark .apxdnswidget .apxdns-copy-button {
    background-color: #3b82f6;
    color: #ffffff;
  }

  .dark .apxdnswidget .apxdns-button {
    background-color: #3b82f6;
    border-color: #3b82f6;
  }

  .dark .apxdnswidget .apxdns-button:hover {
    background-color: #2563eb;
    border-color: #2563eb;
  }

  /* Record display values */
  .dark .apxdnswidget .apxdns-domainconnect-record-display-host-value,
  .dark .apxdnswidget .apxdns-domainconnect-record-display-value-value,
  .dark .apxdnswidget .apxdns-domainconnect-record-display-ttl-value {
    background-color: #1f2937;
    color: #f3f4f6;
  }

  /* Widget container styling */
  .dns-widget-container {
    margin-top: 1.5rem;
  }

  .dns-widget-container .apxdnswidget {
    max-width: 100%;
  }
</style>
