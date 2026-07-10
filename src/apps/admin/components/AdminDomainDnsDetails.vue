<!-- src/apps/admin/components/AdminDomainDnsDetails.vue -->

<script setup lang="ts">
  import type {
    ColonelDomainCluster,
    ColonelDomainDetailRecord,
  } from '@/schemas/api/internal/responses/colonel-domains';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import DetailField from '@/shared/components/ui/DetailField.vue';
  import { computed } from 'vue';
  import { useI18n } from 'vue-i18n';

  /**
   * DNS-validation instructions for a single custom domain, admin console.
   *
   * Presentational only — renders the TXT ownership record plus the apex A /
   * subdomain CNAME record the operator must publish, sourced from the domain's
   * `safe_dump` (`txt_validation_*`, `is_apex`, `trd`, `base_domain`) and the
   * deployment proxy `cluster` (`proxy_ip` / `proxy_host`). Mirrors the
   * workspace `VerifyDomainDetails` step layout, but reads the colonel detail
   * record and owns no verify action — the panel above orchestrates re-verify so
   * it can reuse the existing colonel verify endpoint and refresh this record.
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

  const isApex = computed(() => props.record.is_apex === true);
  const host = computed(() => props.record.trd || '@');
  const baseDomain = computed(() => props.record.base_domain ?? '');
  const proxyIp = computed(() => props.cluster?.proxy_ip ?? '');
  const proxyHost = computed(() => props.cluster?.proxy_host ?? '');
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

      <!-- Step 2: A record (apex) or CNAME (subdomain) pointing at the proxy -->
      <div>
        <p class="mb-1.5 text-sm font-medium text-gray-700 dark:text-gray-300">
          {{ isApex ? t('web.admin.domains.dns.aStep') : t('web.admin.domains.dns.cnameStep') }}
        </p>
        <div class="divide-y divide-gray-200 overflow-hidden rounded-lg border border-gray-200 bg-white dark:divide-gray-700 dark:border-gray-700 dark:bg-gray-900">
          <DetailField
            :label="t('web.COMMON.type')"
            :value="isApex ? 'A' : 'CNAME'" />
          <DetailField
            :label="t('web.COMMON.host')"
            :value="host"
            :appendix="baseDomain ? `.${baseDomain}` : undefined" />
          <DetailField
            :label="t('web.COMMON.value')"
            :value="isApex ? proxyIp : proxyHost" />
        </div>
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
