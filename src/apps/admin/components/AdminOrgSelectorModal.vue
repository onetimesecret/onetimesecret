<!-- src/apps/admin/components/AdminOrgSelectorModal.vue -->

<script setup lang="ts">
  import { AdminModal } from '@/apps/admin/components/kit';
  import { usePaginatedFetch } from '@/apps/admin/composables/usePaginatedFetch';
  import type {
    ColonelOrganization,
    ColonelOrganizationsResponse,
  } from '@/schemas/api/internal/responses/colonel';
  import { colonelOrganizationsResponseSchema } from '@/schemas/api/internal/responses/colonel';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { onBeforeUnmount, ref, watch } from 'vue';
  import { useI18n } from 'vue-i18n';

  /**
   * Reusable organization picker for the admin console.
   *
   * Resolves an org by exact objid / extid or by an email substring
   * (contact / owner / billing) via `GET /api/colonel/organizations?search=` and
   * lets the operator select one. Emits the chosen {@link ColonelOrganization}
   * and closes. Deliberately self-contained — it owns its own paginated fetch
   * (NOT the shared `useAdminOrganizations` store) so dropping it onto any admin
   * screen never bleeds picker state into that screen's org list.
   */
  const props = defineProps<{
    /** Whether the picker is shown (use with `v-model:open`). */
    open: boolean;
  }>();

  const emit = defineEmits<{
    'update:open': [value: boolean];
    select: [org: ColonelOrganization];
  }>();

  const { t } = useI18n();

  const term = ref('');
  const results = ref<ColonelOrganization[]>([]);
  /** True once a search has been run — separates "empty result" from "idle". */
  const searched = ref(false);

  const pager = usePaginatedFetch<ColonelOrganizationsResponse, ColonelOrganization>({
    url: '/api/colonel/organizations',
    schema: colonelOrganizationsResponseSchema,
    context: 'ColonelOrganizationsResponse',
    perPage: 25,
    select: (data) => ({
      items: data.details?.organizations ?? [],
      pagination: data.details?.pagination ?? null,
    }),
  });
  const { loading, error, validationError } = pager;

  async function runSearch(): Promise<void> {
    const q = term.value.trim();
    if (q === '') {
      results.value = [];
      searched.value = false;
      return;
    }
    searched.value = true;
    try {
      const page = await pager.fetchPage(1, { search: q });
      results.value = page?.items ?? [];
    } catch {
      // Network/HTTP failure is captured in `error`; the banner handles it.
      results.value = [];
    }
  }

  // Debounce keystrokes so we don't fire a scan per character.
  let debounceId: ReturnType<typeof setTimeout> | null = null;
  watch(term, () => {
    if (debounceId) clearTimeout(debounceId);
    debounceId = setTimeout(runSearch, 300);
  });
  onBeforeUnmount(() => {
    if (debounceId) clearTimeout(debounceId);
  });

  function onSubmit(): void {
    if (debounceId) clearTimeout(debounceId);
    runSearch();
  }

  function choose(org: ColonelOrganization): void {
    emit('select', org);
    emit('update:open', false);
  }

  // Reset picker state each time it opens so it never shows a stale result set.
  watch(
    () => props.open,
    (isOpen) => {
      if (isOpen) {
        term.value = '';
        results.value = [];
        searched.value = false;
      }
    }
  );
</script>

<template>
  <AdminModal
    :open="open"
    :title="t('web.admin.domains.orgPicker.title')"
    width-class="max-w-xl"
    testid="org-selector-modal"
    @update:open="emit('update:open', $event)">
    <!-- Search field -->
    <form @submit.prevent="onSubmit">
      <label
        for="org-search"
        class="mb-1 block text-xs font-medium text-gray-500 dark:text-gray-400">
        {{ t('web.admin.domains.orgPicker.searchLabel') }}
      </label>
      <div class="relative">
        <span class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3 text-gray-400">
          <OIcon
            collection="heroicons"
            name="magnifying-glass"
            size="5" />
        </span>
        <input
          id="org-search"
          v-model="term"
          type="text"
          autocomplete="off"
          autocapitalize="off"
          autocorrect="off"
          spellcheck="false"
          data-testid="org-search-input"
          :placeholder="t('web.admin.domains.orgPicker.searchPlaceholder')"
          class="w-full rounded-md border border-gray-300 py-2 pr-3 pl-10 font-mono text-sm text-gray-900 placeholder:font-sans placeholder:text-gray-400 focus:border-brand-500 focus:ring-brand-500 focus:outline-none dark:border-gray-600 dark:bg-gray-800 dark:text-white" />
      </div>
      <p class="mt-1 text-xs text-gray-400 dark:text-gray-500">
        {{ t('web.admin.domains.orgPicker.searchHint') }}
      </p>
    </form>

    <!-- Results region -->
    <div
      class="mt-4 min-h-[8rem]"
      aria-live="polite">
      <!-- Error -->
      <div
        v-if="error"
        class="rounded-md border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-800 dark:border-red-900/50 dark:bg-red-900/20 dark:text-red-200"
        role="alert">
        {{ t('web.admin.domains.orgPicker.loadError') }}
      </div>
      <!-- Validation mismatch (degraded, not fatal) -->
      <div
        v-else-if="validationError"
        class="rounded-md border border-yellow-200 bg-yellow-50 px-3 py-2 text-sm text-yellow-800 dark:border-yellow-900/50 dark:bg-yellow-900/20 dark:text-yellow-200"
        role="alert">
        {{ t('web.admin.domains.orgPicker.parseError') }}
      </div>

      <!-- Loading -->
      <div
        v-else-if="loading"
        class="flex items-center justify-center gap-2 py-8 text-sm text-gray-500 dark:text-gray-400">
        <OIcon
          collection="heroicons"
          name="arrow-path"
          size="5"
          class="animate-spin motion-reduce:animate-none" />
        {{ t('web.COMMON.processing') }}
      </div>

      <!-- Idle (no search yet) -->
      <p
        v-else-if="!searched"
        class="py-8 text-center text-sm text-gray-400 dark:text-gray-500">
        {{ t('web.admin.domains.orgPicker.idle') }}
      </p>

      <!-- Empty result -->
      <p
        v-else-if="results.length === 0"
        class="py-8 text-center text-sm text-gray-500 dark:text-gray-400"
        data-testid="org-search-empty">
        {{ t('web.admin.domains.orgPicker.noResults', { term: term.trim() }) }}
      </p>

      <!-- Results list -->
      <ul
        v-else
        class="divide-y divide-gray-100 dark:divide-gray-800"
        data-testid="org-search-results">
        <li
          v-for="org in results"
          :key="org.org_id"
          class="flex items-center justify-between gap-3 py-3">
          <div class="min-w-0">
            <p class="truncate text-sm font-semibold text-gray-900 dark:text-white">
              {{ org.display_name || t('web.admin.domains.orgPicker.unnamedOrg') }}
            </p>
            <p class="truncate font-mono text-xs text-gray-500 tabular-nums dark:text-gray-400">
              {{ org.extid }}
            </p>
            <p
              v-if="org.owner_email || org.contact_email"
              class="truncate text-xs text-gray-500 dark:text-gray-400">
              {{ org.owner_email || org.contact_email }}
            </p>
          </div>
          <div class="flex shrink-0 items-center gap-3">
            <span class="hidden text-xs text-gray-400 sm:inline dark:text-gray-500">
              {{ t('web.admin.domains.orgPicker.domainCount', { count: org.domain_count }) }}
            </span>
            <button
              type="button"
              :data-testid="`org-select-${org.extid}`"
              class="inline-flex items-center rounded-md bg-brand-600 px-3 py-1.5 text-sm font-semibold text-white shadow-sm hover:bg-brand-700 focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 focus:outline-none dark:bg-brand-500 dark:hover:bg-brand-600"
              @click="choose(org)">
              {{ t('web.admin.domains.orgPicker.select') }}
            </button>
          </div>
        </li>
      </ul>
    </div>
  </AdminModal>
</template>
