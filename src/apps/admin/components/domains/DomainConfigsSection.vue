<!-- src/apps/admin/components/domains/DomainConfigsSection.vue -->

<script setup lang="ts">
  import DomainConfigEditModal from '@/apps/admin/components/domains/DomainConfigEditModal.vue';
  import { AdminConfirmDialog } from '@/apps/admin/components/kit';
  import { useAdminMutation } from '@/apps/admin/composables/useAdminMutation';
  import { useAdminDomains } from '@/apps/admin/stores/useAdminDomains';
  import {
    DOMAIN_CONFIG_KINDS,
    EDITABLE_DOMAIN_CONFIG_KINDS,
    type ColonelDomainConfigsEnsureDetails,
    type ColonelDomainConfigsMap,
    type DomainConfigKind,
    type EditableDomainConfigKind,
  } from '@/schemas/api/internal/responses/colonel-domain-configs';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useNotificationsStore } from '@/shared/stores/notificationsStore';
  import { formatDisplayDateTime } from '@/utils/format';
  import { computed, onMounted, ref } from 'vue';
  import { useI18n } from 'vue-i18n';

  /**
   * "Domain configuration" section for {@link AdminDomainDetail}.
   *
   * Surfaces the seven per-custom-domain config records (signin, signup,
   * homepage, api, incoming, sso, mailer) with an honest MISSING state — the
   * v0.26.2 outage class was exactly these records absent and failing closed
   * with no admin-visible signal. Per row: status badge, missing-state note,
   * expandable field grid, and Edit (five editable kinds; the PUT upserts, so
   * a missing record's button reads "Create") / Delete (typed-confirm, token =
   * the kind slug). Section-level "Create missing configs" previews with
   * `dry_run: true` and applies behind a plain confirm.
   *
   * Owns its own fetch (via the store's `fetchConfigs` verb, so every screen
   * drives the same endpoint + ack parsing). Mutations run through
   * {@link useAdminMutation}: failures stay in the dialog/modal; only success
   * closes, toasts, and refetches. Audit is written SERVER-SIDE.
   */
  const props = defineProps<{
    /** The domain's public id (extid). */
    extid: string;
    /** The domain's display name (dialog/modal identity). */
    displayDomain: string;
  }>();

  const { t } = useI18n();
  const notifications = useNotificationsStore();
  const store = useAdminDomains();

  // ---- Fetch (three failure modes kept distinct) -----------------------------

  const configs = ref<ColonelDomainConfigsMap | null>(null);
  const loading = ref(false);
  /** Non-404 network/HTTP failure → error banner + retry. */
  const loadFailed = ref(false);
  /** The domain itself 404'd under us. */
  const notFound = ref(false);
  /** 2xx payload failed the Zod contract → degrade note, no retry loop. */
  const degraded = ref(false);

  function httpStatusOf(err: unknown): number | undefined {
    return (err as { response?: { status?: number } } | null)?.response?.status;
  }

  async function loadConfigs(): Promise<void> {
    loading.value = true;
    loadFailed.value = false;
    notFound.value = false;
    degraded.value = false;
    try {
      const details = await store.fetchConfigs(props.extid);
      if (details) {
        configs.value = details.configs;
      } else {
        configs.value = null;
        degraded.value = true;
      }
    } catch (err) {
      configs.value = null;
      if (httpStatusOf(err) === 404) {
        notFound.value = true;
      } else {
        loadFailed.value = true;
      }
    } finally {
      loading.value = false;
    }
  }

  onMounted(() => {
    loadConfigs();
  });

  // ---- Rows ------------------------------------------------------------------

  const EDITABLE = new Set<string>(EDITABLE_DOMAIN_CONFIG_KINDS);

  type ConfigStatus = 'missing' | 'disabled' | 'enabled' | 'enabledNotReady';

  const STATUS_BADGE_CLASSES: Record<ConfigStatus, string> = {
    missing: 'bg-amber-100 text-amber-800 dark:bg-amber-900/40 dark:text-amber-200',
    disabled: 'bg-gray-100 text-gray-600 dark:bg-gray-800 dark:text-gray-300',
    enabled: 'bg-green-100 text-green-800 dark:bg-green-900/40 dark:text-green-200',
    enabledNotReady: 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900/40 dark:text-yellow-200',
  };

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

  function fieldRows(kind: DomainConfigKind, config: Record<string, unknown>): FieldRow[] {
    return DISPLAY_FIELDS[kind].map((name) => ({
      key: name,
      label: t(`web.admin.domains.configs.fields.${name}`),
      value: formatFieldValue(name, config[name]),
      mono: MONO_FIELDS.has(name),
    }));
  }

  interface ConfigRow {
    kind: DomainConfigKind;
    label: string;
    exists: boolean;
    status: ConfigStatus;
    editable: boolean;
    fields: FieldRow[];
  }

  /**
   * The ONE presence predicate for a config entry: the record counts as
   * present only when the server says it exists AND its serialized form
   * parsed (`config` non-null). Drives both row status and the
   * ensure-button/materializable computation, so the two can never disagree.
   */
  function recordPresent(entry: { exists: boolean; config: unknown } | undefined): boolean {
    return entry != null && entry.exists && entry.config !== null;
  }

  const rows = computed<ConfigRow[]>(() => {
    const map = configs.value;
    if (!map) return [];
    return DOMAIN_CONFIG_KINDS.map((kind) => {
      const entry = map[kind];
      const config = (entry.config ?? null) as Record<string, unknown> | null;
      const exists = recordPresent(entry);
      let status: ConfigStatus = 'missing';
      if (exists && config) {
        const enabled = config.enabled === true;
        if (!enabled) status = 'disabled';
        else if (kind === 'incoming' && config.ready !== true) status = 'enabledNotReady';
        else status = 'enabled';
      }
      return {
        kind,
        label: t(`web.admin.domains.configs.kinds.${kind}`),
        exists,
        status,
        editable: EDITABLE.has(kind),
        fields: exists && config ? fieldRows(kind, config) : [],
      };
    });
  });

  const expanded = ref<Record<string, boolean>>({});
  function toggleExpand(kind: DomainConfigKind): void {
    expanded.value[kind] = !expanded.value[kind];
  }

  // ---- Ensure (dry-run preview → plain confirm apply) ------------------------

  const missingMaterializable = computed(() =>
    EDITABLE_DOMAIN_CONFIG_KINDS.filter((kind) => {
      const entry = configs.value?.[kind];
      return entry ? !recordPresent(entry) : false;
    })
  );

  /** The section-level button only shows when a materializable kind is missing. */
  const ensureVisible = computed(() => missingMaterializable.value.length > 0);

  const ensurePlan = ref<ColonelDomainConfigsEnsureDetails | null>(null);

  const {
    loading: ensurePreviewLoading,
    error: ensurePreviewError,
    run: runEnsurePreview,
    reset: resetEnsurePreview,
  } = useAdminMutation(async () => {
    const plan = await store.ensureConfigs(props.extid, { dryRun: true });
    if (!plan) {
      // A null resolve is a 2xx whose payload failed the Zod contract. Throw
      // so the failure lands in `ensurePreviewError` under the button — a
      // silent return would leave the button looking dead.
      throw new Error(t('web.admin.domains.configs.degraded'));
    }
    ensurePlan.value = plan;
  });

  async function onEnsure(): Promise<void> {
    resetEnsurePreview();
    ensurePlan.value = null;
    const ok = await runEnsurePreview();
    // Re-read through an asserted local: the mutation closure assigned the
    // ref, which TS's narrowing (from the `= null` above) cannot see across
    // the await — without the assertion it collapses the type to never.
    const plan = ensurePlan.value as ColonelDomainConfigsEnsureDetails | null;
    if (!ok || !plan) return;
    if (plan.created.length === 0) {
      // Race: another operator materialized the records between our load and
      // this preview. Nothing to create — resync the rows instead of opening
      // a no-op confirm dialog.
      ensurePlan.value = null;
      notifications.show(t('web.admin.domains.configs.ensure.nothingMissing'), 'info');
      await loadConfigs();
      return;
    }
    requestAction('ensure');
  }

  // ---- The shared guarded-action dialog (ensure apply + delete) --------------

  type ActionKey = 'ensure' | 'delete';

  const dialogOpen = ref(false);
  const activeAction = ref<ActionKey | null>(null);
  const deleteKind = ref<DomainConfigKind | null>(null);

  const {
    loading: mutationLoading,
    error: mutationError,
    run: runMutation,
    reset: resetMutation,
  } = useAdminMutation(async () => {
    switch (activeAction.value) {
      case 'ensure': {
        // The endpoint DEFAULTS dry_run to true; a dry_run echo on the ack
        // means the server only PREVIEWED — reporting success would toast
        // "created" while nothing was materialized. A null ack (Zod tripwire)
        // still means the mutation happened, so it passes.
        const ack = await store.ensureConfigs(props.extid, { dryRun: false });
        if (ack && ack.dry_run !== false) {
          throw new Error(t('web.admin.domains.configs.ensure.notApplied'));
        }
        return;
      }
      case 'delete': {
        if (!deleteKind.value) throw new Error('No config kind selected');
        await store.deleteConfig(props.extid, deleteKind.value);
        return;
      }
      default:
        throw new Error('No active action');
    }
  });

  const dialogConfig = computed(() => {
    if (activeAction.value === 'delete' && deleteKind.value) {
      return {
        title: t('web.admin.domains.configs.delete.confirmTitle', {
          kind: t(`web.admin.domains.configs.kinds.${deleteKind.value}`),
        }),
        description: t('web.admin.domains.configs.delete.confirmDescription', {
          kind: deleteKind.value,
          domain: props.displayDomain,
        }),
        // Typed-confirmation gate: retype the kind slug (console convention).
        confirmToken: deleteKind.value as string | undefined,
        variant: 'danger' as const,
        confirmText: t('web.admin.domains.configs.delete.button'),
      };
    }
    if (activeAction.value === 'ensure') {
      return {
        title: t('web.admin.domains.configs.ensure.confirmTitle'),
        description: t('web.admin.domains.configs.ensure.confirmDescription', {
          kinds: (ensurePlan.value?.created ?? []).join(', '),
          domain: props.displayDomain,
        }),
        confirmToken: undefined as string | undefined,
        variant: 'default' as const,
        confirmText: t('web.admin.domains.configs.ensure.applyButton'),
      };
    }
    return {
      title: '',
      description: undefined as string | undefined,
      confirmToken: undefined as string | undefined,
      variant: 'default' as const,
      confirmText: undefined as string | undefined,
    };
  });

  function requestAction(key: ActionKey): void {
    activeAction.value = key;
    resetMutation();
    dialogOpen.value = true;
  }

  function requestDelete(kind: DomainConfigKind): void {
    deleteKind.value = kind;
    requestAction('delete');
  }

  async function onConfirm(): Promise<void> {
    const action = activeAction.value;
    if (!action) return;

    const ok = await runMutation();
    if (!ok) return; // Failure message stays in the dialog for retry/cancel.

    dialogOpen.value = false;
    if (action === 'ensure') {
      notifications.show(t('web.admin.domains.configs.ensure.success'), 'success');
      ensurePlan.value = null;
    } else {
      notifications.show(t('web.admin.domains.configs.delete.success'), 'success');
    }
    activeAction.value = null;
    deleteKind.value = null;
    await loadConfigs();
  }

  function onCancel(): void {
    dialogOpen.value = false;
    activeAction.value = null;
    deleteKind.value = null;
    resetMutation();
  }

  // ---- Edit / create (dumb modal; this parent owns the upsert) ---------------

  const editOpen = ref(false);
  const editKind = ref<EditableDomainConfigKind | null>(null);

  const editConfig = computed<Record<string, unknown> | null>(() => {
    if (!editKind.value) return null;
    const entry = configs.value?.[editKind.value];
    return entry?.exists ? ((entry.config ?? null) as Record<string, unknown> | null) : null;
  });

  const {
    loading: upsertLoading,
    error: upsertError,
    run: runUpsert,
    reset: resetUpsert,
  } = useAdminMutation(async (payload: Record<string, unknown>) => {
    if (!editKind.value) throw new Error('No config kind selected');
    await store.upsertConfig(props.extid, editKind.value, payload);
  });

  function openEdit(kind: DomainConfigKind): void {
    if (!EDITABLE.has(kind)) return;
    editKind.value = kind as EditableDomainConfigKind;
    resetUpsert();
    editOpen.value = true;
  }

  async function onEditSubmit(payload: Record<string, unknown>): Promise<void> {
    const ok = await runUpsert(payload);
    if (!ok) return; // Error stays in the modal.
    editOpen.value = false;
    notifications.show(t('web.admin.domains.configs.edit.success'), 'success');
    await loadConfigs();
  }
</script>

<template>
  <section
    class="rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-800 dark:bg-gray-900"
    data-testid="domain-configs-section">
    <!-- Header + ensure -->
    <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-800">
      <div class="flex flex-wrap items-start justify-between gap-3">
        <div class="min-w-0">
          <h3 class="text-lg font-medium text-gray-900 dark:text-white">
            {{ t('web.admin.domains.configs.title') }}
          </h3>
          <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
            {{ t('web.admin.domains.configs.description') }}
          </p>
        </div>
        <button
          v-if="ensureVisible"
          type="button"
          data-testid="config-ensure"
          :disabled="ensurePreviewLoading"
          class="inline-flex items-center gap-1 rounded-md border border-gray-300 px-3 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 focus:ring-2 focus:ring-brand-500 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-800"
          @click="onEnsure">
          <OIcon
            collection="heroicons"
            :name="ensurePreviewLoading ? 'arrow-path' : 'plus-circle'"
            size="4"
            :class="ensurePreviewLoading ? 'animate-spin motion-reduce:animate-none' : ''" />
          {{ t('web.admin.domains.configs.ensure.button') }}
        </button>
      </div>
      <p
        v-if="ensurePreviewError"
        class="mt-2 text-sm text-red-700 dark:text-red-300"
        role="alert"
        data-testid="config-ensure-error">
        {{ ensurePreviewError }}
      </p>
    </div>

    <!-- Loading -->
    <div
      v-if="loading && !configs"
      class="flex items-center justify-center px-6 py-10 text-gray-500 dark:text-gray-400"
      data-testid="configs-loading">
      <OIcon
        collection="heroicons"
        name="arrow-path"
        size="5"
        class="animate-spin motion-reduce:animate-none" />
      <span class="ml-3 text-sm">{{ t('web.COMMON.loading') }}</span>
    </div>

    <!-- Domain vanished under us -->
    <div
      v-else-if="notFound"
      class="px-6 py-10 text-center text-sm text-gray-500 dark:text-gray-400"
      data-testid="configs-not-found">
      {{ t('web.admin.domains.configs.notFoundNote') }}
    </div>

    <!-- Network/HTTP failure → retry -->
    <div
      v-else-if="loadFailed"
      class="px-6 py-10 text-center"
      role="alert"
      data-testid="configs-error">
      <p class="text-sm text-red-800 dark:text-red-200">
        {{ t('web.admin.domains.configs.loadError') }}
      </p>
      <button
        type="button"
        data-testid="configs-retry"
        class="mt-3 inline-flex items-center gap-1 rounded-md border border-red-300 px-3 py-2 text-sm font-medium text-red-800 hover:bg-red-100 focus:ring-2 focus:ring-red-500 focus:outline-none dark:border-red-800 dark:text-red-200 dark:hover:bg-red-900/40"
        @click="loadConfigs">
        <OIcon
          collection="heroicons"
          name="arrow-path"
          size="4" />
        {{ t('web.admin.domains.configs.retry') }}
      </button>
    </div>

    <!-- Contract mismatch → honest degrade -->
    <div
      v-else-if="degraded"
      class="px-6 py-10 text-center text-sm text-gray-500 dark:text-gray-400"
      data-testid="configs-degraded">
      {{ t('web.admin.domains.configs.degraded') }}
    </div>

    <!-- The seven rows, fixed order -->
    <ul
      v-else-if="configs"
      class="divide-y divide-gray-200 dark:divide-gray-800">
      <li
        v-for="row in rows"
        :key="row.kind"
        class="px-6 py-4"
        :data-testid="`config-row-${row.kind}`">
        <div class="flex flex-wrap items-center gap-3">
          <span class="min-w-[6rem] text-sm font-medium text-gray-900 dark:text-white">
            {{ row.label }}
          </span>
          <span
            class="inline-flex items-center rounded px-2 py-0.5 text-xs font-medium"
            :class="STATUS_BADGE_CLASSES[row.status]"
            :data-testid="`config-status-${row.kind}`">
            {{ t(`web.admin.domains.configs.status.${row.status}`) }}
          </span>
          <span class="flex-1"></span>
          <button
            v-if="row.exists"
            type="button"
            :data-testid="`config-toggle-${row.kind}`"
            :aria-expanded="expanded[row.kind] ? 'true' : 'false'"
            class="inline-flex items-center gap-1 rounded-md px-2 py-1 text-xs font-medium text-gray-500 hover:text-gray-700 focus:ring-2 focus:ring-brand-500 focus:outline-none dark:text-gray-400 dark:hover:text-gray-200"
            @click="toggleExpand(row.kind)">
            <OIcon
              collection="heroicons"
              :name="expanded[row.kind] ? 'chevron-up' : 'chevron-down'"
              size="3" />
            {{ t('web.admin.domains.configs.detailsToggle') }}
          </button>
          <button
            v-if="row.editable"
            type="button"
            :data-testid="`config-edit-${row.kind}`"
            class="inline-flex items-center gap-1 rounded-md border border-gray-300 px-3 py-1.5 text-xs font-medium text-gray-700 hover:bg-gray-50 focus:ring-2 focus:ring-brand-500 focus:outline-none dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-800"
            @click="openEdit(row.kind)">
            {{
              row.exists
                ? t('web.admin.domains.configs.edit.button')
                : t('web.admin.domains.configs.edit.createButton')
            }}
          </button>
          <button
            v-if="row.exists"
            type="button"
            :data-testid="`config-delete-${row.kind}`"
            class="inline-flex items-center gap-1 rounded-md border border-red-300 px-3 py-1.5 text-xs font-medium text-red-700 hover:bg-red-50 focus:ring-2 focus:ring-red-500 focus:outline-none dark:border-red-800 dark:text-red-300 dark:hover:bg-red-900/30"
            @click="requestDelete(row.kind)">
            {{ t('web.admin.domains.configs.delete.button') }}
          </button>
        </div>

        <!-- Absent-record behavior (what fails closed / falls back) -->
        <p
          v-if="!row.exists"
          class="mt-2 text-sm text-gray-500 dark:text-gray-400"
          :data-testid="`config-missing-note-${row.kind}`">
          {{ t(`web.admin.domains.configs.missingNotes.${row.kind}`) }}
        </p>

        <!-- sso/mailer: view/delete only -->
        <p
          v-if="!row.editable"
          class="mt-2 text-xs text-gray-400 dark:text-gray-500"
          :data-testid="`config-not-editable-${row.kind}`">
          {{ t('web.admin.domains.configs.notEditable') }}
        </p>

        <!-- Expandable field grid -->
        <dl
          v-if="row.exists && expanded[row.kind]"
          class="mt-4 grid grid-cols-1 gap-x-6 gap-y-4 sm:grid-cols-2"
          :data-testid="`config-fields-${row.kind}`">
          <div
            v-for="field in row.fields"
            :key="field.key"
            :data-testid="`config-field-${row.kind}-${field.key}`">
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
      </li>
    </ul>

    <!-- Edit/create modal (dumb; this section owns the upsert mutation) -->
    <DomainConfigEditModal
      v-model:open="editOpen"
      :kind="editKind"
      :config="editConfig"
      :display-domain="displayDomain"
      :loading="upsertLoading"
      :error="upsertError"
      @submit="onEditSubmit" />

    <!-- Shared guarded-action dialog (typed-confirm delete, plain-confirm ensure) -->
    <AdminConfirmDialog
      v-model:open="dialogOpen"
      :title="dialogConfig.title"
      :description="dialogConfig.description"
      :confirm-token="dialogConfig.confirmToken"
      :variant="dialogConfig.variant"
      :confirm-text="dialogConfig.confirmText"
      :loading="mutationLoading"
      :error="mutationError"
      @confirm="onConfirm"
      @cancel="onCancel" />
  </section>
</template>
