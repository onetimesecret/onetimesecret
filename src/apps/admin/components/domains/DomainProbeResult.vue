<!-- src/apps/admin/components/domains/DomainProbeResult.vue -->

<script setup lang="ts">
  import { JsonViewer } from '@/apps/admin/components/kit';
  import type { ColonelDomainProbeDetails } from '@/schemas/api/internal/responses/colonel-domaintoolbox';
  import { computed } from 'vue';
  import { useI18n } from 'vue-i18n';

  /**
   * Read-out for one `GET /api/colonel/domains/:extid/probe` result.
   *
   * Presentational only — the caller owns the request (see
   * `useAdminDomains.probe`). Surfaces the op's honest health classification,
   * the HTTP arm and the TLS-certificate arm, then the raw payload via
   * {@link JsonViewer} for anything the summary doesn't name.
   *
   * A probe reaches the network but mutates nothing, so nothing here is guarded
   * and no audit is written.
   */
  const props = defineProps<{
    /** The probe payload (`details` of the wrapped response). */
    details: ColonelDomainProbeDetails;
    /** The probed hostname, echoed next to the health pill. */
    domain?: string;
  }>();

  const { t } = useI18n();

  /** Health pill colour keyed by the op's classification. */
  const healthClass = computed(() => {
    switch (props.details.health) {
      case 'healthy':
        return 'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200';
      case 'ssl_expiring_soon':
      case 'http_error':
        return 'bg-amber-100 text-amber-800 dark:bg-amber-900/40 dark:text-amber-200';
      default:
        return 'bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200';
    }
  });

  const http = computed(() => props.details.http);
  const ssl = computed(() => props.details.ssl ?? null);

  type ProbeField = { key: string; label: string; value: string; mono?: boolean };

  /** HTTP arm: either a status line, or the transport error that replaced it. */
  const httpFields = computed<ProbeField[]>(() => {
    const h = http.value;
    const rows: ProbeField[] = [];
    if (h.status_code !== undefined) {
      rows.push({
        key: 'status',
        label: t('web.admin.domains.probe.fields.httpStatus'),
        value: [h.status_code, h.status_message].filter(Boolean).join(' '),
        mono: true,
      });
    }
    if (h.error) {
      rows.push({
        key: 'httpError',
        label: t('web.admin.domains.probe.fields.httpError'),
        value: h.message ? `${h.error}: ${h.message}` : h.error,
      });
    }
    return rows;
  });

  /**
   * TLS arm. Absent entirely on failure branches that never reached a
   * certificate (connection refused, timeout) — the caller sees the notice
   * below instead of empty rows.
   */
  const sslFields = computed<ProbeField[]>(() => {
    const s = ssl.value;
    if (!s) return [];

    const rows: ProbeField[] = [];
    if (s.error) {
      rows.push({
        key: 'sslError',
        label: t('web.admin.domains.probe.fields.sslError'),
        value: s.error,
      });
      return rows;
    }
    if (s.issuer) {
      rows.push({
        key: 'issuer',
        label: t('web.admin.domains.probe.fields.issuer'),
        value: s.issuer,
      });
    }
    if (s.subject) {
      rows.push({
        key: 'subject',
        label: t('web.admin.domains.probe.fields.subject'),
        value: s.subject,
        mono: true,
      });
    }
    if (s.not_after) {
      rows.push({
        key: 'notAfter',
        label: t('web.admin.domains.probe.fields.notAfter'),
        value:
          s.days_until_expiry === undefined
            ? s.not_after
            : t('web.admin.domains.probe.fields.expiresIn', {
                date: s.not_after,
                days: s.days_until_expiry,
              }),
      });
    }
    return rows;
  });

  /** True once we know a certificate arm was returned but is unusable. */
  const certUnusable = computed(
    () => ssl.value !== null && (ssl.value?.expired === true || ssl.value?.not_yet_valid === true)
  );
</script>

<template>
  <div
    class="space-y-4"
    data-testid="probe-result">
    <!-- Health headline -->
    <div class="flex flex-wrap items-center gap-3">
      <span class="text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.admin.domains.probe.healthLabel') }}
      </span>
      <span
        :class="['inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium', healthClass]"
        data-testid="probe-health">
        {{ details.health }}
      </span>
      <span
        v-if="domain"
        class="font-mono text-xs text-gray-500 dark:text-gray-400">
        {{ domain }}
      </span>
      <span
        v-if="certUnusable"
        class="inline-flex items-center rounded-full bg-red-100 px-2.5 py-0.5 text-xs font-medium text-red-800 dark:bg-red-900 dark:text-red-200"
        data-testid="probe-cert-invalid">
        {{ t('web.admin.domains.probe.certInvalid') }}
      </span>
    </div>

    <!-- Summary rows -->
    <dl
      v-if="httpFields.length || sslFields.length"
      class="grid grid-cols-1 gap-x-6 gap-y-3 sm:grid-cols-2">
      <div
        v-for="field in [...httpFields, ...sslFields]"
        :key="field.key"
        :data-testid="`probe-${field.key}`">
        <dt
          class="font-brand text-[11px] font-semibold tracking-[0.1em] text-gray-500 uppercase dark:text-gray-400">
          {{ field.label }}
        </dt>
        <dd
          :class="[
            'mt-1 text-sm break-words text-gray-900 dark:text-gray-100',
            field.mono ? 'font-mono tabular-nums' : '',
          ]">
          {{ field.value }}
        </dd>
      </div>
    </dl>

    <p
      v-if="!ssl"
      class="text-xs text-gray-500 dark:text-gray-400"
      data-testid="probe-no-cert">
      {{ t('web.admin.domains.probe.noCertificate') }}
    </p>

    <!-- Full payload. Probe results carry no secrets (hostname, status, cert
         metadata), so passing them through is safe. -->
    <JsonViewer
      :data="details"
      :expand-depth="2"
      testid="probe-json" />
  </div>
</template>
