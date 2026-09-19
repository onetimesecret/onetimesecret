<!-- src/apps/admin/components/AdminDomainDnsDetails.vue -->

<script setup lang="ts">
  import type {
    ColonelDomainCluster,
    ColonelDomainDetailRecord,
  } from '@/schemas/api/internal/responses/colonel-domains';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import DetailField from '@/shared/components/ui/DetailField.vue';
  import { useDomainDnsRecord } from '@/shared/composables/useDomainDnsRecord';
  import { computed } from 'vue';
  import { useI18n } from 'vue-i18n';

  /**
   * DNS-validation instructions for a single custom domain, admin console.
   *
   * Presentational only — renders the TXT ownership record plus the address
   * record the operator must publish, sourced from the domain's `safe_dump`
   * (`txt_validation_*`, `is_apex`, `trd`, `base_domain`) and the deployment
   * `cluster`. Mirrors the workspace `VerifyDomainDetails` step layout, but
   * reads the colonel detail record and owns no verify action — the panel
   * above orchestrates re-verify so it can reuse the existing colonel verify
   * endpoint and refresh this record.
   *
   * Where the address record points comes from `useDomainDnsRecord`, the same
   * source the customer pages use, so an operator relays what the customer
   * sees: the Approximated proxy (`cluster.proxy_ip` / `proxy_host`) only when
   * the strategy routes through it, otherwise this install by name. The proxy
   * fields stay configured after a move off `approximated` and must not be
   * read here directly.
   *
   * Fields the dump omits render as "—" (DetailField shows an empty value)
   * rather than crashing; unverified / self-hosted domains legitimately lack
   * some of them.
   */
  const props = defineProps<{
    record: ColonelDomainDetailRecord;
    cluster: ColonelDomainCluster;
  }>();

  const { t } = useI18n();

  const baseDomain = computed(() => props.record.base_domain ?? '');

  const { kind, recordType, recordHost, recordHostAppendix, recordTarget, usesApproximatedProxy } =
    useDomainDnsRecord(
      () => props.record,
      () => props.cluster
    );

  // Heading by record kind and by where the record points. "the proxy" is
  // only said when the target is the Approximated proxy.
  const addressStepHeading = computed(() => {
    if (kind.value === 'a') return t('web.admin.domains.dns.aStep');
    if (kind.value === 'alias') return t('web.admin.domains.dns.aliasStepInstall');
    return usesApproximatedProxy.value
      ? t('web.admin.domains.dns.cnameStep')
      : t('web.admin.domains.dns.cnameStepInstall');
  });
</script>

<template>
  <div
    class="rounded-md border border-gray-200 bg-gray-50 p-4 dark:border-gray-700 dark:bg-gray-800/40"
    data-testid="dns-details">
    <h5 class="mb-3 text-xs font-semibold tracking-wide text-gray-500 uppercase dark:text-gray-400">
      {{ t('web.admin.domains.dns.heading') }}
    </h5>

    <div class="space-y-4">
      <!-- Step 1: TXT ownership record -->
      <div>
        <p class="mb-1.5 text-sm font-medium text-gray-700 dark:text-gray-300">
          {{ t('web.admin.domains.dns.txtStep') }}
        </p>
        <div class="divide-y divide-gray-200 overflow-hidden rounded-lg border border-gray-200 bg-white dark:divide-gray-700 dark:border-gray-700 dark:bg-gray-900">
          <DetailField
            :label="t('web.COMMON.type')"
            value="TXT" />
          <DetailField
            :label="t('web.COMMON.host')"
            :value="record.txt_validation_host ?? ''"
            :appendix="baseDomain ? `.${baseDomain}` : undefined" />
          <DetailField
            :label="t('web.COMMON.value')"
            :value="record.txt_validation_value ?? ''" />
        </div>
      </div>

      <!-- Step 2: the address record. A / CNAME at the Approximated proxy, or
           ALIAS / CNAME at this install (useDomainDnsRecord). -->
      <div data-testid="dns-address-step">
        <p
          class="mb-1.5 text-sm font-medium text-gray-700 dark:text-gray-300"
          data-testid="dns-address-heading">
          {{ addressStepHeading }}
        </p>
        <div class="divide-y divide-gray-200 overflow-hidden rounded-lg border border-gray-200 bg-white dark:divide-gray-700 dark:border-gray-700 dark:bg-gray-900">
          <DetailField
            :label="t('web.COMMON.type')"
            :value="recordType" />
          <DetailField
            :label="t('web.COMMON.host')"
            :value="recordHost"
            :appendix="recordHostAppendix || undefined" />
          <DetailField
            :label="t('web.COMMON.value')"
            :value="recordTarget" />
        </div>
        <p
          v-if="kind === 'alias'"
          class="mt-1.5 text-xs text-gray-500 dark:text-gray-400"
          data-testid="dns-apex-note">
          {{ t('web.admin.domains.dns.apexNote') }}
        </p>
      </div>
    </div>

    <p class="mt-3 flex items-start gap-2 text-xs text-gray-500 dark:text-gray-400">
      <OIcon
        collection="heroicons"
        name="information-circle"
        size="4"
        class="mt-0.5 shrink-0 text-gray-400" />
      {{ t('web.admin.domains.dns.propagationNote') }}
    </p>
  </div>
</template>
