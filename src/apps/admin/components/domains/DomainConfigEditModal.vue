<!-- src/apps/admin/components/domains/DomainConfigEditModal.vue -->

<script setup lang="ts">
  import {
    DOMAIN_CONFIG_EDIT_FIELDS,
    type DomainConfigFieldDescriptor,
  } from '@/apps/admin/components/domains/domainConfigDescriptors';
  import { AdminModal } from '@/apps/admin/components/kit';
  import type { EditableDomainConfigKind } from '@/schemas/api/internal/responses/colonel-domain-configs';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { computed, ref, watch } from 'vue';
  import { useI18n } from 'vue-i18n';

  /**
   * Per-kind config edit modal for the colonel domain-configs section.
   *
   * DUMB by contract (the AddDomainForOrgModal shape): the parent owns the
   * upsert mutation and passes `loading` / `error` back in; this component
   * only collects input (driven by {@link DOMAIN_CONFIG_EDIT_FIELDS}) and
   * emits `submit` with the field payload. Field state re-seeds from the
   * current serialized config — or the model defaults when creating a missing
   * record — every time `open` flips true.
   */
  const props = defineProps<{
    /** Whether the modal is shown (use with `v-model:open`). */
    open: boolean;
    /** The editable kind being configured, or null when idle. */
    kind: EditableDomainConfigKind | null;
    /** Current serialized config (prefill), or null when creating. */
    config: Record<string, unknown> | null;
    /** The domain's display name (header identity). */
    displayDomain: string;
    /** True while the parent's upsert request is in flight. */
    loading?: boolean;
    /** Server/action error to surface, or null. */
    error?: string | null;
  }>();

  const emit = defineEmits<{
    'update:open': [value: boolean];
    submit: [payload: Record<string, unknown>];
  }>();

  const { t } = useI18n();

  const fields = computed<readonly DomainConfigFieldDescriptor[]>(() =>
    props.kind ? DOMAIN_CONFIG_EDIT_FIELDS[props.kind] : []
  );

  /** Missing record → the PUT creates it, so the modal reads as "Create". */
  const isCreate = computed(() => props.config === null);

  const kindLabel = computed(() =>
    props.kind ? t(`web.admin.domains.configs.kinds.${props.kind}`) : ''
  );

  // Form state, keyed by field name. Selects hold '' for "unset" (→ null in
  // the payload); the domains textarea holds one domain per line.
  const booleanValues = ref<Record<string, boolean>>({});
  const selectValues = ref<Record<string, string>>({});
  const domainsText = ref('');

  /**
   * Seed all field state from the current config, or the model defaults.
   * A null/undefined enum on the record (legacy/corrupt data — e.g. signup's
   * `validation_strategy`) falls back to the field's defaultValue, so the
   * repair path renders a valid choice instead of blanking the select.
   */
  function resetFields(): void {
    const nextBooleans: Record<string, boolean> = {};
    const nextSelects: Record<string, string> = {};
    let nextDomains = '';
    for (const field of fields.value) {
      const current = props.config?.[field.name];
      if (field.type === 'boolean') {
        nextBooleans[field.name] =
          typeof current === 'boolean' ? current : field.defaultValue === true;
      } else if (field.type === 'select') {
        nextSelects[field.name] =
          typeof current === 'string' && current !== ''
            ? current
            : ((field.defaultValue as string | null) ?? '');
      } else {
        nextDomains = Array.isArray(current) ? (current as string[]).join('\n') : '';
      }
    }
    booleanValues.value = nextBooleans;
    selectValues.value = nextSelects;
    domainsText.value = nextDomains;
  }

  watch(
    () => props.open,
    (isOpen) => {
      if (isOpen) resetFields();
    }
  );

  /** The current form value for one field, in payload space (''→null). */
  function formValue(field: DomainConfigFieldDescriptor): unknown {
    if (field.type === 'boolean') return booleanValues.value[field.name] ?? false;
    if (field.type === 'select') {
      const value = selectValues.value[field.name] ?? '';
      return value === '' ? null : value;
    }
    return domainsText.value
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter((line) => line.length > 0);
  }

  /**
   * The prefilled record value for one field, normalized into payload space
   * for diffing (nullable enums read '' / null / undefined as null). A
   * non-comparable stored value (corrupt boolean, nil enum) never equals the
   * form value, so repairing it counts as a change.
   */
  function prefilledValue(field: DomainConfigFieldDescriptor): unknown {
    const current = props.config?.[field.name];
    if (field.type === 'boolean') return typeof current === 'boolean' ? current : undefined;
    if (field.type === 'select')
      return typeof current === 'string' && current !== '' ? current : null;
    return Array.isArray(current) ? current : [];
  }

  function sameValue(a: unknown, b: unknown): boolean {
    if (Array.isArray(a) && Array.isArray(b)) {
      return a.length === b.length && a.every((item, i) => item === b[i]);
    }
    return a === b;
  }

  /**
   * The writable-field payload for the PUT (booleans real, ''→null).
   *
   * Audit fidelity: when EDITING an existing record only fields whose value
   * differs from the prefill are emitted, so the backend's audit
   * `changed:[...]` lists real changes. When CREATING (no record) the full
   * writable set is emitted so the new record matches what the form showed.
   */
  function buildPayload(): Record<string, unknown> {
    const payload: Record<string, unknown> = {};
    for (const field of fields.value) {
      const value = formValue(field);
      if (!isCreate.value && sameValue(value, prefilledValue(field))) continue;
      payload[field.name] = value;
    }
    return payload;
  }

  /** On edit, submitting zero changed fields is a no-op — keep it disabled. */
  const hasChanges = computed(() => Object.keys(buildPayload()).length > 0);

  function onSubmit(): void {
    if (props.loading || !props.kind || !hasChanges.value) return;
    emit('submit', buildPayload());
  }
</script>

<template>
  <AdminModal
    :open="open"
    :title="t('web.admin.domains.configs.edit.title', { kind: kindLabel })"
    :subtitle="displayDomain"
    :dismissable="!loading"
    testid="config-edit-modal"
    @update:open="emit('update:open', $event)">
    <form @submit.prevent="onSubmit">
      <div class="space-y-4">
        <template
          v-for="field in fields"
          :key="field.name">
          <!-- Boolean toggle (accessible native checkbox) -->
          <label
            v-if="field.type === 'boolean'"
            class="flex items-center gap-2">
            <input
              type="checkbox"
              v-model="booleanValues[field.name]"
              :disabled="loading"
              :data-testid="`config-field-${field.name}`"
              class="size-4 rounded border-gray-300 text-brand-600 focus:ring-brand-500 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:bg-gray-800" />
            <span class="text-sm text-gray-900 dark:text-gray-100">
              {{ t(`web.admin.domains.configs.fields.${field.name}`) }}
            </span>
          </label>

          <!-- Enum select -->
          <div v-else-if="field.type === 'select'">
            <label
              :for="`config-select-${field.name}`"
              class="mb-1 block text-xs font-medium text-gray-500 dark:text-gray-400">
              {{ t(`web.admin.domains.configs.fields.${field.name}`) }}
            </label>
            <select
              :id="`config-select-${field.name}`"
              v-model="selectValues[field.name]"
              :disabled="loading"
              :data-testid="`config-field-${field.name}`"
              class="w-full rounded-md border border-gray-300 px-3 py-2 font-mono text-sm text-gray-900 focus:border-brand-500 focus:ring-brand-500 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:bg-gray-800 dark:text-white">
              <option
                v-if="field.allowUnset"
                value="">
                {{ t('web.admin.domains.configs.edit.unsetOption') }}
              </option>
              <option
                v-for="option in field.options"
                :key="option"
                :value="option">
                {{ option }}
              </option>
            </select>
          </div>

          <!-- Domain list (one per line) -->
          <div v-else>
            <label
              :for="`config-domains-${field.name}`"
              class="mb-1 block text-xs font-medium text-gray-500 dark:text-gray-400">
              {{ t(`web.admin.domains.configs.fields.${field.name}`) }}
            </label>
            <textarea
              :id="`config-domains-${field.name}`"
              v-model="domainsText"
              rows="4"
              autocomplete="off"
              autocapitalize="off"
              autocorrect="off"
              spellcheck="false"
              :disabled="loading"
              :data-testid="`config-field-${field.name}`"
              class="w-full rounded-md border border-gray-300 px-3 py-2 font-mono text-sm text-gray-900 placeholder:text-gray-400 focus:border-brand-500 focus:ring-brand-500 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:bg-gray-800 dark:text-white"></textarea>
            <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
              {{ t('web.admin.domains.configs.edit.domainsHint') }}
            </p>
          </div>
        </template>
      </div>

      <!-- Error stays IN the modal (useAdminMutation convention) -->
      <div
        v-if="error"
        class="mt-4 rounded-md bg-red-50 p-3 dark:bg-red-900/20"
        role="alert"
        aria-live="assertive">
        <p class="text-sm text-red-800 dark:text-red-200">
          {{ error }}
        </p>
      </div>
    </form>

    <template #footer>
      <div class="flex justify-end gap-3">
        <button
          type="button"
          data-testid="config-edit-cancel"
          :disabled="loading"
          class="inline-flex justify-center rounded-md bg-white px-4 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-gray-300 ring-inset hover:bg-gray-50 focus:ring-2 focus:ring-gray-400 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:bg-gray-700 dark:text-gray-300 dark:ring-gray-600 dark:hover:bg-gray-600"
          @click="emit('update:open', false)">
          {{ t('web.COMMON.word_cancel') }}
        </button>
        <button
          type="button"
          data-testid="config-edit-submit"
          :disabled="loading || !hasChanges"
          class="inline-flex items-center justify-center gap-2 rounded-md bg-brand-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-brand-700 focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:bg-brand-500 dark:hover:bg-brand-600"
          @click="onSubmit">
          <OIcon
            v-if="loading"
            collection="heroicons"
            name="arrow-path"
            size="4"
            class="animate-spin motion-reduce:animate-none" />
          {{
            loading
              ? t('web.COMMON.processing')
              : isCreate
                ? t('web.admin.domains.configs.edit.createButton')
                : t('web.admin.domains.configs.edit.submit')
          }}
        </button>
      </div>
    </template>
  </AdminModal>
</template>
