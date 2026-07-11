<!-- src/apps/admin/components/AddDomainForOrgModal.vue -->

<script setup lang="ts">
  import { AdminModal } from '@/apps/admin/components/kit';
  import type { ColonelOrganization } from '@/schemas/api/internal/responses/colonel';
  import { getBootstrapValue } from '@/services/bootstrap.service';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { computed, ref, watch } from 'vue';
  import { useI18n } from 'vue-i18n';

  /**
   * Attach-a-domain modal for the admin console.
   *
   * A plain domain field plus a READ-ONLY badge of the deployment's custom-domain
   * validation strategy. Validation strategy is install-level config
   * (`features.domains.validation_strategy` on the bootstrap payload), not a
   * per-domain choice — so it is shown for context, never selected here. The
   * parent owns the create mutation (`POST /api/colonel/domains`) and passes
   * `loading` / `error` back in; this component only collects + validates input
   * and emits `submit`.
   */
  const props = defineProps<{
    /** Whether the modal is shown (use with `v-model:open`). */
    open: boolean;
    /** The organization the domain will be attached to (for the header identity). */
    org: ColonelOrganization | null;
    /** True while the parent's create request is in flight. */
    loading?: boolean;
    /** Server/action error to surface, or null. */
    error?: string | null;
  }>();

  const emit = defineEmits<{
    'update:open': [value: boolean];
    submit: [domain: string];
  }>();

  const { t } = useI18n();

  const domain = ref('');

  /** Deployment-wide validation strategy (read-only context). */
  const strategy = computed<string>(() => {
    const domains = getBootstrapValue('domains') as
      | { validation_strategy?: string | null }
      | null
      | undefined;
    return domains?.validation_strategy || 'passthrough';
  });

  /** Friendly one-liner for the active strategy. Unknown values fall back. */
  const strategyDescription = computed(() => {
    const key = `web.admin.domains.addDomain.strategy.${strategy.value}`;
    const translated = t(key);
    // vue-i18n returns the key verbatim when it is missing — degrade honestly.
    return translated === key ? t('web.admin.domains.addDomain.strategy.unknown') : translated;
  });

  // Minimal client-side gate mirroring the shared add-domain regex; the server
  // is authoritative and re-validates.
  const trimmed = computed(() => domain.value.trim().toLowerCase());
  const isValid = computed(
    () => /^[a-zA-Z0-9][a-zA-Z0-9-_.]+[a-zA-Z0-9]$/.test(trimmed.value)
  );
  const canSubmit = computed(() => isValid.value && !props.loading);

  function onSubmit(): void {
    if (!canSubmit.value) return;
    emit('submit', trimmed.value);
  }

  // Clear the field whenever the modal (re)opens.
  watch(
    () => props.open,
    (isOpen) => {
      if (isOpen) domain.value = '';
    }
  );
</script>

<template>
  <AdminModal
    :open="open"
    :title="t('web.admin.domains.addDomain.title')"
    :subtitle="org ? org.extid : undefined"
    :dismissable="!loading"
    testid="add-domain-modal"
    @update:open="emit('update:open', $event)">
    <form @submit.prevent="onSubmit">
      <!-- Target org context -->
      <p
        v-if="org"
        class="mb-4 text-sm text-gray-600 dark:text-gray-400">
        {{ t('web.admin.domains.addDomain.forOrg', {
          org: org.display_name || org.extid,
        }) }}
      </p>

      <!-- Domain field -->
      <label
        for="new-domain"
        class="mb-1 block text-xs font-medium text-gray-500 dark:text-gray-400">
        {{ t('web.admin.domains.addDomain.domainLabel') }}
      </label>
      <input
        id="new-domain"
        v-model="domain"
        type="text"
        autocomplete="off"
        autocapitalize="off"
        autocorrect="off"
        spellcheck="false"
        :disabled="loading"
        data-testid="add-domain-input"
        :placeholder="t('web.admin.domains.addDomain.domainPlaceholder')"
        class="w-full rounded-md border border-gray-300 px-3 py-2 font-mono text-sm text-gray-900 placeholder:text-gray-400 focus:border-brand-500 focus:ring-brand-500 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:bg-gray-800 dark:text-white" />

      <!-- Read-only validation-strategy badge -->
      <div class="mt-4">
        <span class="mb-1 block text-xs font-medium text-gray-500 dark:text-gray-400">
          {{ t('web.admin.domains.addDomain.strategyLabel') }}
        </span>
        <div
          class="flex items-start gap-2 rounded-md border border-gray-200 bg-gray-50 px-3 py-2 dark:border-gray-700 dark:bg-gray-800/50"
          data-testid="strategy-badge">
          <OIcon
            collection="heroicons"
            name="lock-closed"
            size="4"
            class="mt-0.5 shrink-0 text-gray-400" />
          <div class="min-w-0">
            <p class="font-mono text-sm font-medium text-gray-900 tabular-nums dark:text-white">
              {{ strategy }}
            </p>
            <p class="text-xs text-gray-500 dark:text-gray-400">
              {{ strategyDescription }}
            </p>
          </div>
        </div>
      </div>

      <!-- Error -->
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
          data-testid="add-domain-cancel"
          :disabled="loading"
          class="inline-flex justify-center rounded-md bg-white px-4 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-gray-300 ring-inset hover:bg-gray-50 focus:ring-2 focus:ring-gray-400 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:bg-gray-700 dark:text-gray-300 dark:ring-gray-600 dark:hover:bg-gray-600"
          @click="emit('update:open', false)">
          {{ t('web.COMMON.word_cancel') }}
        </button>
        <button
          type="button"
          data-testid="add-domain-submit"
          :disabled="!canSubmit"
          class="inline-flex items-center justify-center gap-2 rounded-md bg-brand-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-brand-700 focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:bg-brand-500 dark:hover:bg-brand-600"
          @click="onSubmit">
          <OIcon
            v-if="loading"
            collection="heroicons"
            name="arrow-path"
            size="4"
            class="animate-spin motion-reduce:animate-none" />
          {{ loading ? t('web.COMMON.processing') : t('web.admin.domains.addDomain.createButton') }}
        </button>
      </div>
    </template>
  </AdminModal>
</template>
