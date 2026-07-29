<!-- src/apps/admin/components/domains/DomainConfigFieldGrid.vue -->

<script setup lang="ts">
  import type { DomainConfigKind } from '@/schemas/api/internal/responses/colonel-domain-configs';
  import { formatDisplayDateTime } from '@/utils/format';
  import { computed } from 'vue';
  import { useI18n } from 'vue-i18n';

  /**
   * Expandable dt/dd field grid for one PRESENT config record.
   *
   * Owns the read-only display vocabulary: which serialized fields each kind
   * shows (identity + secrets already redacted server-side — only `has_*`
   * presence flags ever reach the client), which render monospace, and how raw
   * values format (booleans → yes/no, epoch seconds → local datetime,
   * recipient objects → email list, empty → the shared "none").
   *
   * Presentational only; the parent decides WHEN to render it (record present
   * AND the row expanded).
   */
  const props = defineProps<{
    /** Which config kind's field order/formatting to apply. */
    kind: DomainConfigKind;
    /** The record's serialized (already redacted) config. */
    config: Record<string, unknown>;
  }>();

  const { t } = useI18n();

  /** Serialized field display order per kind (identity + secrets redacted). */
  const DISPLAY_FIELDS: Record<DomainConfigKind, readonly string[]> = {
    signin: [
      'enabled',
      'signin_enabled',
      'email_auth_enabled',
      'sso_enabled',
      'restrict_to',
      'created',
      'updated',
    ],
    signup: [
      'enabled',
      'signup_enabled',
      'autoverify',
      'validation_strategy',
      'allowed_signup_domains',
      'created',
      'updated',
    ],
    homepage: ['enabled', 'secrets_mode', 'disabled_homepage_variant', 'created', 'updated'],
    api: ['enabled', 'created', 'updated'],
    incoming: ['enabled', 'ready', 'recipients', 'created', 'updated'],
    sso: [
      'enabled',
      'provider_type',
      'display_name',
      'issuer',
      'tenant_id',
      'has_client_id',
      'has_client_secret',
      'allowed_domains',
      'enforce_sso_only',
      'grant_org_scope',
      'created',
      'updated',
    ],
    mailer: [
      'enabled',
      'provider',
      'from_name',
      'from_address',
      'reply_to',
      'sending_mode',
      'verification_status',
      'dns_verified',
      'provider_verified',
      'has_api_key',
      'created',
      'updated',
    ],
  };

  /** Key-material fields rendered monospace in the dt/dd grid. */
  const MONO_FIELDS = new Set([
    'restrict_to',
    'validation_strategy',
    'allowed_signup_domains',
    'secrets_mode',
    'disabled_homepage_variant',
    'recipients',
    'provider_type',
    'issuer',
    'tenant_id',
    'allowed_domains',
    'provider',
    'from_address',
    'reply_to',
    'sending_mode',
    'verification_status',
  ]);

  interface FieldRow {
    key: string;
    label: string;
    value: string;
    mono: boolean;
  }

  function formatFieldValue(name: string, value: unknown): string {
    if (value === null || value === undefined || value === '') {
      return t('web.admin.domains.detail.none');
    }
    if (typeof value === 'boolean') {
      return value ? t('web.admin.domains.detail.yes') : t('web.admin.domains.detail.no');
    }
    if ((name === 'created' || name === 'updated') && typeof value === 'number') {
      return formatDisplayDateTime(new Date(value * 1000));
    }
    if (Array.isArray(value)) {
      if (value.length === 0) return t('web.admin.domains.detail.none');
      const parts = value.map((item) =>
        item && typeof item === 'object' && 'email' in (item as Record<string, unknown>)
          ? String((item as { email: unknown }).email)
          : String(item)
      );
      return parts.join(', ');
    }
    return String(value);
  }

  const fields = computed<FieldRow[]>(() =>
    DISPLAY_FIELDS[props.kind].map((name) => ({
      key: name,
      label: t(`web.admin.domains.configs.fields.${name}`),
      value: formatFieldValue(name, props.config[name]),
      mono: MONO_FIELDS.has(name),
    }))
  );
</script>

<template>
  <dl
    class="mt-4 grid grid-cols-1 gap-x-6 gap-y-4 sm:grid-cols-2"
    :data-testid="`config-fields-${kind}`">
    <div
      v-for="field in fields"
      :key="field.key"
      :data-testid="`config-field-${kind}-${field.key}`">
      <dt class="text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
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
</template>
