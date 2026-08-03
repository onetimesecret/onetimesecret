<!-- src/apps/admin/components/domains/DomainConfigRow.vue -->

<script setup lang="ts">
  import DomainConfigFieldGrid from '@/apps/admin/components/domains/DomainConfigFieldGrid.vue';
  import DomainConfigStatusBadge from '@/apps/admin/components/domains/DomainConfigStatusBadge.vue';
  import type { DomainConfigStatus } from '@/apps/admin/components/domains/domainConfigTypes';
  import type { DomainConfigKind } from '@/schemas/api/internal/responses/colonel-domain-configs';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { computed } from 'vue';
  import { useI18n } from 'vue-i18n';

  /**
   * One of the seven per-kind rows in {@link DomainConfigsSection}: kind label,
   * honest status badge, and the row actions.
   *
   * Presentational + presence-driven:
   * - Details toggle and Delete render only when the record is PRESENT
   *   (`exists` — nothing to expand or delete on a missing record).
   * - Edit renders only for the five editable kinds; on a missing record the
   *   PUT upserts, so the button reads "Create".
   * - A missing record shows its absent-record note (what fails closed / falls
   *   back); sso/mailer show the workspace-managed view-only note.
   *
   * All mutations stay in the parent — this emits `edit` / `delete` / `toggle`
   * and never touches the store. The parent also owns the expanded map so
   * open rows survive the section's refetch-after-mutate cycle.
   */
  const props = defineProps<{
    /** The row's config kind (slug drives testids + i18n keys). */
    kind: DomainConfigKind;
    /** Whether the record counts as present (the parent's ONE predicate). */
    exists: boolean;
    /** Derived lifecycle state for the badge. */
    status: DomainConfigStatus;
    /** Whether this kind is colonel-editable (five kinds; sso/mailer are not). */
    editable: boolean;
    /** The serialized (redacted) config when present, else null. */
    config: Record<string, unknown> | null;
    /** Whether the field grid is expanded (parent-owned). */
    expanded: boolean;
  }>();

  const emit = defineEmits<{
    /** Expand/collapse the field grid. */
    toggle: [];
    /** Open the edit/create modal for this kind. */
    edit: [];
    /** Request the typed-confirm delete for this kind. */
    delete: [];
  }>();

  const { t } = useI18n();

  const label = computed(() => t(`web.admin.domains.configs.kinds.${props.kind}`));
</script>

<template>
  <li
    class="px-6 py-4"
    :data-testid="`config-row-${kind}`">
    <div class="flex flex-wrap items-center gap-3">
      <span class="min-w-[6rem] text-sm font-medium text-gray-900 dark:text-white">
        {{ label }}
      </span>
      <DomainConfigStatusBadge
        :status="status"
        :testid="`config-status-${kind}`" />
      <span class="flex-1"></span>
      <button
        v-if="exists"
        type="button"
        :data-testid="`config-toggle-${kind}`"
        :aria-expanded="expanded ? 'true' : 'false'"
        class="inline-flex items-center gap-1 rounded-md px-2 py-1 text-xs font-medium text-gray-500 hover:text-gray-700 focus:ring-2 focus:ring-brand-500 focus:outline-none dark:text-gray-400 dark:hover:text-gray-200"
        @click="emit('toggle')">
        <OIcon
          collection="heroicons"
          :name="expanded ? 'chevron-up' : 'chevron-down'"
          size="3" />
        {{ t('web.admin.domains.configs.detailsToggle') }}
      </button>
      <button
        v-if="editable"
        type="button"
        :data-testid="`config-edit-${kind}`"
        class="inline-flex items-center gap-1 rounded-md border border-gray-300 px-3 py-1.5 text-xs font-medium text-gray-700 hover:bg-gray-50 focus:ring-2 focus:ring-brand-500 focus:outline-none dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-800"
        @click="emit('edit')">
        {{
          exists
            ? t('web.admin.domains.configs.edit.button')
            : t('web.admin.domains.configs.edit.createButton')
        }}
      </button>
      <button
        v-if="exists"
        type="button"
        :data-testid="`config-delete-${kind}`"
        class="inline-flex items-center gap-1 rounded-md border border-red-300 px-3 py-1.5 text-xs font-medium text-red-700 hover:bg-red-50 focus:ring-2 focus:ring-red-500 focus:outline-none dark:border-red-800 dark:text-red-300 dark:hover:bg-red-900/30"
        @click="emit('delete')">
        {{ t('web.admin.domains.configs.delete.button') }}
      </button>
    </div>

    <!-- Absent-record behavior (what fails closed / falls back) -->
    <p
      v-if="!exists"
      class="mt-2 text-sm text-gray-500 dark:text-gray-400"
      :data-testid="`config-missing-note-${kind}`">
      {{ t(`web.admin.domains.configs.missingNotes.${kind}`) }}
    </p>

    <!-- sso/mailer: view/delete only -->
    <p
      v-if="!editable"
      class="mt-2 text-xs text-gray-400 dark:text-gray-500"
      :data-testid="`config-not-editable-${kind}`">
      {{ t('web.admin.domains.configs.notEditable') }}
    </p>

    <!-- Expandable field grid -->
    <DomainConfigFieldGrid
      v-if="exists && expanded && config"
      :kind="kind"
      :config="config" />
  </li>
</template>
