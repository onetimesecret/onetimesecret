<!-- src/apps/admin/components/domains/DomainConfigsSection.vue -->

<script setup lang="ts">
  import DomainConfigActionDialog from '@/apps/admin/components/domains/DomainConfigActionDialog.vue';
  import DomainConfigEditModal from '@/apps/admin/components/domains/DomainConfigEditModal.vue';
  import DomainConfigRow from '@/apps/admin/components/domains/DomainConfigRow.vue';
  import DomainConfigsHeader from '@/apps/admin/components/domains/DomainConfigsHeader.vue';
  import type {
    DomainConfigAction,
    DomainConfigStatus,
  } from '@/apps/admin/components/domains/domainConfigTypes';
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
   * This is the CONTAINER of the family: it owns the fetch state machine, the
   * derived row states, and all three mutations. The extracted children —
   * {@link DomainConfigsHeader}, {@link DomainConfigRow} (with its badge and
   * field grid), {@link DomainConfigActionDialog} and
   * {@link DomainConfigEditModal} — are presentational and emit intents back.
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

  /**
   * What the server requires in X-OTS-Confirm for the per-config verbs (#4326):
   * "<display_domain>:<kind>". The URL carries the extid and the kind, so the
   * hostname is the half a scraped-URL replay does not have. `ensure` is
   * un-gated (an idempotent backfill of missing rows) and sends nothing.
   */
  function configConfirmToken(kind: DomainConfigKind): string {
    return `${props.displayDomain}:${kind}`;
  }

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

  interface ConfigRow {
    kind: DomainConfigKind;
    exists: boolean;
    status: DomainConfigStatus;
    editable: boolean;
    config: Record<string, unknown> | null;
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
      // The map TYPE carries every key, but a drifted server payload could
      // omit one at runtime — an absent entry must render as MISSING, not
      // throw and blank the whole section.
      const entry: (typeof map)[typeof kind] | undefined = map[kind];
      const config = (entry?.config ?? null) as Record<string, unknown> | null;
      const exists = recordPresent(entry);
      let status: DomainConfigStatus = 'missing';
      if (exists && config) {
        const enabled = config.enabled === true;
        if (!enabled) status = 'disabled';
        else if (kind === 'incoming' && config.ready !== true) status = 'enabledNotReady';
        else status = 'enabled';
      }
      return {
        kind,
        exists,
        status,
        editable: EDITABLE.has(kind),
        config: exists ? config : null,
      };
    });
  });

  const expanded = ref<Record<string, boolean>>({});
  function toggleExpand(kind: DomainConfigKind): void {
    expanded.value[kind] = !expanded.value[kind];
  }

  // ---- Ensure (dry-run preview → plain confirm apply) ------------------------

  const missingMaterializable = computed(() => {
    const map = configs.value;
    // Not loaded (or load failed): nothing is "missing" yet — keep the ensure
    // button hidden rather than flashing it for every kind during load.
    if (!map) return [];
    // Once the map is populated, a kind whose KEY is absent (server drift,
    // schema change) must count as missing too — recordPresent handles the
    // undefined entry. Filtering on `entry ? … : false` would silently skip it.
    return EDITABLE_DOMAIN_CONFIG_KINDS.filter((kind) => !recordPresent(map[kind]));
  });

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

  const dialogOpen = ref(false);
  const activeAction = ref<DomainConfigAction | null>(null);
  const deleteKind = ref<DomainConfigKind | null>(null);

  const {
    loading: mutationLoading,
    error: mutationError,
    run: runMutation,
    reset: resetMutation,
  } = useAdminMutation(async () => {
    switch (activeAction.value) {
      case 'ensure': {
        // The ack is LOAD-BEARING here: it is the only proof the run was
        // APPLIED rather than previewed. A null ack (2xx that failed the Zod
        // contract) hard-fails like the preview path — toasting success on it
        // could report "created" when nothing was materialized. And since the
        // endpoint DEFAULTS dry_run to true, a dry_run echo on a parsed ack
        // means the server only PREVIEWED — also a failure.
        const ack = await store.ensureConfigs(props.extid, { dryRun: false });
        if (!ack) {
          throw new Error(t('web.admin.domains.configs.degraded'));
        }
        if (ack.dry_run !== false) {
          throw new Error(t('web.admin.domains.configs.ensure.notApplied'));
        }
        return;
      }
      case 'delete': {
        if (!deleteKind.value) throw new Error('No config kind selected');
        const ack = await store.deleteConfig(
          props.extid,
          deleteKind.value,
          configConfirmToken(deleteKind.value)
        );
        if (!ack) {
          // Null ack = 2xx whose payload failed the Zod contract. The DELETE
          // itself succeeded (a failure would have rejected), so keep the
          // success flow — but surface the contract regression in devtools.
          console.warn(
            '[DomainConfigsSection] delete ack failed schema validation — response not verified'
          );
        }
        return;
      }
      default:
        throw new Error('No active action');
    }
  });

  function requestAction(key: DomainConfigAction): void {
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
    const ack = await store.upsertConfig(
      props.extid,
      editKind.value,
      payload,
      configConfirmToken(editKind.value)
    );
    if (!ack) {
      // Null ack = 2xx whose payload failed the Zod contract. The PUT itself
      // succeeded (a failure would have rejected), so keep the success flow —
      // but surface the contract regression in devtools.
      console.warn(
        '[DomainConfigsSection] upsert ack failed schema validation — response not verified'
      );
    }
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
    <DomainConfigsHeader
      :ensure-visible="ensureVisible"
      :ensure-loading="ensurePreviewLoading"
      :ensure-error="ensurePreviewError"
      @ensure="onEnsure" />

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
      <DomainConfigRow
        v-for="row in rows"
        :key="row.kind"
        :kind="row.kind"
        :exists="row.exists"
        :status="row.status"
        :editable="row.editable"
        :config="row.config"
        :expanded="!!expanded[row.kind]"
        @toggle="toggleExpand(row.kind)"
        @edit="openEdit(row.kind)"
        @delete="requestDelete(row.kind)" />
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
    <DomainConfigActionDialog
      v-model:open="dialogOpen"
      :action="activeAction"
      :delete-kind="deleteKind"
      :ensure-kinds="ensurePlan?.created ?? []"
      :display-domain="displayDomain"
      :loading="mutationLoading"
      :error="mutationError"
      @confirm="onConfirm"
      @cancel="onCancel" />
  </section>
</template>
