<!-- src/apps/admin/components/domains/DomainConfigActionDialog.vue -->

<script setup lang="ts">
  import type { DomainConfigAction } from '@/apps/admin/components/domains/domainConfigTypes';
  import { AdminConfirmDialog } from '@/apps/admin/components/kit';
  import type { DomainConfigKind } from '@/schemas/api/internal/responses/colonel-domain-configs';
  import { computed } from 'vue';
  import { useI18n } from 'vue-i18n';

  /**
   * The section's ONE guarded-action dialog, shared by its two mutations:
   * - delete: typed-confirmation gate, token = the kind slug (console
   *   convention), danger styling;
   * - ensure apply: plain confirm listing the kinds the dry-run preview said
   *   it would create.
   *
   * Only the copy/variant wiring lives here — the parent owns the mutation,
   * so failures stay visible in the dialog (via `:error`) for retry/cancel and
   * only a confirmed success closes it.
   */
  const props = defineProps<{
    /** Whether the dialog is shown (use with `v-model:open`). */
    open: boolean;
    /** Which guarded action the dialog is fronting, or null when idle. */
    action: DomainConfigAction | null;
    /** The kind being deleted (delete mode identity + typed token). */
    deleteKind: DomainConfigKind | null;
    /** The kinds the ensure preview would create (ensure-mode copy). */
    ensureKinds: readonly string[];
    /** The domain's display name (dialog identity). */
    displayDomain: string;
    /** True while the confirmed mutation is in flight. */
    loading: boolean;
    /** Mutation failure to surface inside the dialog, or null. */
    error: string | null;
  }>();

  const emit = defineEmits<{
    'update:open': [value: boolean];
    confirm: [];
    cancel: [];
  }>();

  const { t } = useI18n();

  const dialogConfig = computed(() => {
    if (props.action === 'delete' && props.deleteKind) {
      return {
        title: t('web.admin.domains.configs.delete.confirmTitle', {
          kind: t(`web.admin.domains.configs.kinds.${props.deleteKind}`),
        }),
        description: t('web.admin.domains.configs.delete.confirmDescription', {
          kind: props.deleteKind,
          domain: props.displayDomain,
        }),
        // Typed-confirmation gate: retype the kind slug (console convention).
        confirmToken: props.deleteKind as string | undefined,
        variant: 'danger' as const,
        confirmText: t('web.admin.domains.configs.delete.button'),
      };
    }
    if (props.action === 'ensure') {
      return {
        title: t('web.admin.domains.configs.ensure.confirmTitle'),
        description: t('web.admin.domains.configs.ensure.confirmDescription', {
          kinds: props.ensureKinds.join(', '),
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
</script>

<template>
  <AdminConfirmDialog
    :open="open"
    :title="dialogConfig.title"
    :description="dialogConfig.description"
    :confirm-token="dialogConfig.confirmToken"
    :variant="dialogConfig.variant"
    :confirm-text="dialogConfig.confirmText"
    :loading="loading"
    :error="error"
    @update:open="emit('update:open', $event)"
    @confirm="emit('confirm')"
    @cancel="emit('cancel')" />
</template>
