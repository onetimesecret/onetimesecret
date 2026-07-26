<!-- src/apps/admin/components/organizations/AddMemberModal.vue -->

<script setup lang="ts">
  import RevealEmail from '@/apps/admin/components/RevealEmail.vue';
  import { AdminModal } from '@/apps/admin/components/kit';
  import {
    MEMBERSHIP_ROLES,
    type AddMembershipRequest,
    type MembershipRole,
  } from '@/apps/admin/components/organizations/membershipSchemas';
  import { usePaginatedFetch } from '@/apps/admin/composables/usePaginatedFetch';
  import { useResourceFetch } from '@/apps/admin/composables/useResourceFetch';
  import type {
    ColonelUser,
    ColonelUserDetailResponse,
    ColonelUsersResponse,
  } from '@/schemas/api/internal/responses/colonel';
  import {
    colonelUserDetailResponseSchema,
    colonelUsersResponseSchema,
  } from '@/schemas/api/internal/responses/colonel';
  import type { ColonelOrganizationDetailMember } from '@/schemas/api/internal/responses/colonel-organizations';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { formatDisplayDateTime } from '@/utils/format';
  import { computed, onBeforeUnmount, ref, watch } from 'vue';
  import { useI18n } from 'vue-i18n';

  /**
   * "Add an existing account to this organization" — the support-desk flow for
   * the case an invitation cannot cover: a person signed up on their own, so
   * they already have an account and the invite path refuses them, but they
   * belong in an existing organization.
   *
   * Deliberately NOT a membership CRUD surface. It does exactly one verb (add)
   * against `POST /api/colonel/organizations/:org_id/members`; removing a member
   * and changing an existing member's role are different endpoints and are out
   * of scope here.
   *
   * Two steps in one modal:
   *  1. FIND — `GET /api/colonel/users?search=` (the same bounded email-index
   *     scan the customers list uses). An operator working from a support ticket
   *     has an email address, so that is the primary key; the endpoint also
   *     matches an exact extid or objid, which is what a paste from another
   *     console tab gives you.
   *  2. CONFIRM — the picked account is pinned with enough identity to be sure
   *     it is the right person (obscured-by-default address, public id, created
   *     date, verification/suspension state) plus the organizations it is
   *     ALREADY in, fetched from `GET /api/colonel/users/:extid`. That second
   *     fetch is best-effort: if it fails the flow degrades to the roster-based
   *     guard below and never blocks the add.
   *
   * The parent owns the mutation (loading/error are passed back in) — this only
   * collects the account + role and emits `submit`, mirroring
   * {@link AddDomainForOrgModal}.
   */
  const props = withDefaults(
    defineProps<{
      /** Whether the modal is shown (use with `v-model:open`). */
      open: boolean;
      /** The target organization's PUBLIC id (extid). */
      orgExtid: string;
      /** Display label for the target organization (header + copy). */
      orgName: string;
      /**
       * The organization's CURRENT roster. Used purely as a client-side guard so
       * an operator is told "already a member" before spending a request; the
       * server's idempotent `no_change` is still the authority.
       */
      members: ColonelOrganizationDetailMember[];
      /** True while the parent's add request is in flight. */
      loading?: boolean;
      /** Server/action error from the parent's mutation, or null. */
      error?: string | null;
    }>(),
    {
      loading: false,
      error: null,
    }
  );

  const emit = defineEmits<{
    'update:open': [value: boolean];
    submit: [payload: AddMembershipRequest];
  }>();

  const { t } = useI18n();

  // ---- Step 1: find the account -------------------------------------------

  const term = ref('');
  /** The term the current `results` were fetched for — guards no-op refetches. */
  const activeTerm = ref('');
  const results = ref<ColonelUser[]>([]);
  /** True once a search has run — separates "no matches" from "idle". */
  const searched = ref(false);

  const pager = usePaginatedFetch<ColonelUsersResponse, ColonelUser>({
    url: '/api/colonel/users',
    schema: colonelUsersResponseSchema,
    context: 'ColonelUsersResponse',
    perPage: 25,
    select: (data) => ({
      items: data.details?.users ?? [],
      pagination: data.details?.pagination ?? null,
    }),
  });
  const {
    loading: searchLoading,
    error: searchError,
    validationError: searchValidationError,
  } = pager;

  async function runSearch(): Promise<void> {
    const q = term.value.trim();
    activeTerm.value = q;
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
      // Network/HTTP failure is captured in `error`; the banner renders it.
      results.value = [];
    }
  }

  // One request per pause, not per keystroke. The no-op guard keeps the
  // programmatic reset below from firing a second, pointless search.
  let debounceId: ReturnType<typeof setTimeout> | null = null;
  watch(term, (value) => {
    if (debounceId) clearTimeout(debounceId);
    if (value.trim() === activeTerm.value) return;
    debounceId = setTimeout(runSearch, 300);
  });
  onBeforeUnmount(() => {
    if (debounceId) clearTimeout(debounceId);
  });

  function onSearchSubmit(): void {
    if (debounceId) clearTimeout(debounceId);
    runSearch();
  }

  // ---- Step 2: confirm the account + pick a role ---------------------------

  const selected = ref<ColonelUser | null>(null);
  const role = ref<MembershipRole>('member');

  const {
    data: accountData,
    loading: accountLoading,
    error: accountError,
    validationError: accountValidationError,
    load: loadAccount,
    reset: resetAccount,
  } = useResourceFetch<ColonelUserDetailResponse>({
    // Getter form: the id is read lazily, at load() time.
    url: () => `/api/colonel/users/${encodeURIComponent(selected.value?.extid ?? '')}`,
    schema: colonelUserDetailResponseSchema,
    context: 'ColonelUserDetailResponse',
  });

  /** The organizations the picked account already belongs to (best-effort). */
  const accountOrganizations = computed(() => accountData.value?.details?.organizations ?? []);

  /** True when the memberships read-out could not be loaded — shown, not fatal. */
  const accountLookupFailed = computed(
    () => accountError.value !== null || accountValidationError.value !== null
  );

  /** Roster lookup by customer extid (org detail `members[].extid` is the customer's). */
  const rosterByExtid = computed(
    () => new Map(props.members.map((member) => [member.extid, member]))
  );

  function rosterEntry(extid: string): ColonelOrganizationDetailMember | undefined {
    return rosterByExtid.value.get(extid);
  }

  /** The picked account's existing membership in THIS org, from the roster. */
  const existingMembership = computed(() =>
    selected.value ? (rosterEntry(selected.value.extid) ?? null) : null
  );

  /**
   * Already a member per either source: the roster we were handed, or the
   * account's own organization list (which covers a roster that has gone stale
   * since the page loaded).
   */
  const alreadyMember = computed(() => {
    if (existingMembership.value) return true;
    return accountOrganizations.value.some((org) => org.extid === props.orgExtid);
  });

  /** The role we can name in the "already a member" warning, when we know it. */
  const existingRole = computed(() => existingMembership.value?.role ?? null);

  const canSubmit = computed(
    () => selected.value !== null && !alreadyMember.value && !props.loading
  );

  function roleLabel(value: string): string {
    return t(`web.admin.organizations.addMember.roles.${value}`, value);
  }

  function choose(user: ColonelUser): void {
    selected.value = user;
    role.value = 'member';
    resetAccount();
    // Best-effort: this is the only call that exposes the account's current org
    // memberships. A failure degrades to the roster guard, it never blocks.
    loadAccount().catch(() => {});
  }

  function clearSelection(): void {
    selected.value = null;
    resetAccount();
  }

  function onSubmit(): void {
    if (!canSubmit.value || !selected.value) return;
    emit('submit', { customer: selected.value.extid, role: role.value });
  }

  // Reset every time the modal opens so it never shows a stale account/result set.
  watch(
    () => props.open,
    (isOpen) => {
      if (!isOpen) return;
      if (debounceId) clearTimeout(debounceId);
      term.value = '';
      activeTerm.value = '';
      results.value = [];
      searched.value = false;
      selected.value = null;
      role.value = 'member';
      resetAccount();
    }
  );
</script>

<template>
  <AdminModal
    :open="open"
    :title="t('web.admin.organizations.addMember.title')"
    :subtitle="orgExtid"
    :dismissable="!loading"
    width-class="max-w-2xl"
    testid="add-member-modal"
    @update:open="emit('update:open', $event)">
    <p class="text-sm text-gray-600 dark:text-gray-400">
      {{ t('web.admin.organizations.addMember.description', { org: orgName }) }}
    </p>

    <!-- Step 1: find the account ------------------------------------------- -->
    <form
      v-if="!selected"
      class="mt-4"
      @submit.prevent="onSearchSubmit">
      <label
        for="add-member-search"
        class="mb-1 block text-xs font-medium text-gray-500 dark:text-gray-400">
        {{ t('web.admin.organizations.addMember.searchLabel') }}
      </label>
      <div class="relative">
        <span
          class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3 text-gray-400">
          <OIcon
            collection="heroicons"
            name="magnifying-glass"
            size="5" />
        </span>
        <input
          id="add-member-search"
          v-model="term"
          type="search"
          autocomplete="off"
          autocapitalize="off"
          autocorrect="off"
          spellcheck="false"
          data-testid="add-member-search"
          :placeholder="t('web.admin.organizations.addMember.searchPlaceholder')"
          class="w-full rounded-md border border-gray-300 py-2 pr-3 pl-10 text-sm text-gray-900 placeholder:text-gray-400 focus:border-brand-500 focus:ring-brand-500 focus:outline-none dark:border-gray-600 dark:bg-gray-800 dark:text-white" />
      </div>
      <p class="mt-1 text-xs text-gray-400 dark:text-gray-500">
        {{ t('web.admin.organizations.addMember.searchHint') }}
      </p>
    </form>

    <!-- Results region -->
    <div
      v-if="!selected"
      class="mt-4 min-h-[8rem]"
      aria-live="polite">
      <!-- Network / HTTP failure -->
      <div
        v-if="searchError"
        class="rounded-md border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-800 dark:border-red-900/50 dark:bg-red-900/20 dark:text-red-200"
        role="alert"
        data-testid="add-member-search-error">
        {{ t('web.admin.organizations.addMember.searchError') }}
      </div>
      <!-- Contract mismatch (degraded, not fatal) -->
      <div
        v-else-if="searchValidationError"
        class="rounded-md border border-yellow-200 bg-yellow-50 px-3 py-2 text-sm text-yellow-800 dark:border-yellow-900/50 dark:bg-yellow-900/20 dark:text-yellow-200"
        role="alert"
        data-testid="add-member-search-parse-error">
        {{ t('web.admin.organizations.addMember.searchParseError') }}
      </div>

      <!-- Loading -->
      <div
        v-else-if="searchLoading"
        class="flex items-center justify-center gap-2 py-8 text-sm text-gray-500 dark:text-gray-400">
        <OIcon
          collection="heroicons"
          name="arrow-path"
          size="5"
          class="animate-spin motion-reduce:animate-none" />
        {{ t('web.COMMON.processing') }}
      </div>

      <!-- Idle -->
      <p
        v-else-if="!searched"
        class="py-8 text-center text-sm text-gray-400 dark:text-gray-500"
        data-testid="add-member-idle">
        {{ t('web.admin.organizations.addMember.idle') }}
      </p>

      <!-- No matches: the account genuinely does not exist -->
      <div
        v-else-if="results.length === 0"
        class="py-8 text-center"
        data-testid="add-member-no-results">
        <OIcon
          collection="heroicons"
          name="user-circle"
          size="8"
          class="mx-auto text-gray-300 dark:text-gray-600" />
        <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.admin.organizations.addMember.noResults', { term: activeTerm }) }}
        </p>
        <p class="mt-1 text-xs text-gray-400 dark:text-gray-500">
          {{ t('web.admin.organizations.addMember.noResultsHint') }}
        </p>
      </div>

      <!-- Matches -->
      <ul
        v-else
        class="divide-y divide-gray-100 dark:divide-gray-800"
        data-testid="add-member-results">
        <li
          v-for="user in results"
          :key="user.extid"
          class="flex items-start justify-between gap-3 py-3">
          <div class="min-w-0">
            <div class="text-sm font-semibold text-gray-900 dark:text-white">
              <RevealEmail :email="user.email" />
            </div>
            <p
              class="mt-0.5 truncate font-mono text-xs text-gray-500 tabular-nums dark:text-gray-400">
              {{ user.extid }}
            </p>
            <div class="mt-1 flex flex-wrap items-center gap-1.5">
              <span
                v-if="user.verified"
                class="inline-flex items-center gap-1 rounded bg-green-100 px-1.5 py-0.5 text-xs font-medium text-green-800 dark:bg-green-900/40 dark:text-green-200">
                <OIcon
                  collection="heroicons"
                  name="check-badge"
                  size="3" />
                {{ t('web.admin.organizations.addMember.badges.verified') }}
              </span>
              <span
                v-else
                class="inline-flex items-center gap-1 rounded bg-amber-100 px-1.5 py-0.5 text-xs font-medium text-amber-800 dark:bg-amber-900/40 dark:text-amber-200">
                <OIcon
                  collection="heroicons"
                  name="exclamation-triangle"
                  size="3" />
                {{ t('web.admin.organizations.addMember.badges.unverified') }}
              </span>
              <span
                v-if="user.suspended"
                class="inline-flex items-center gap-1 rounded bg-red-100 px-1.5 py-0.5 text-xs font-medium text-red-800 dark:bg-red-900/40 dark:text-red-200">
                <OIcon
                  collection="heroicons"
                  name="no-symbol"
                  size="3" />
                {{ t('web.admin.organizations.addMember.badges.suspended') }}
              </span>
              <span
                v-if="user.role && user.role !== 'customer'"
                class="inline-flex items-center rounded bg-amber-100 px-1.5 py-0.5 text-xs font-medium text-amber-800 dark:bg-amber-900/40 dark:text-amber-200">
                {{ user.role }}
              </span>
              <span
                v-if="rosterEntry(user.extid)"
                class="inline-flex items-center rounded bg-gray-200 px-1.5 py-0.5 text-xs font-medium text-gray-700 dark:bg-gray-700 dark:text-gray-200"
                :data-testid="`add-member-existing-${user.extid}`">
                {{ t('web.admin.organizations.addMember.badges.alreadyMember') }}
              </span>
              <span class="text-xs text-gray-400 tabular-nums dark:text-gray-500">
                {{
                  t('web.admin.organizations.addMember.createdOn', {
                    date: formatDisplayDateTime(user.created),
                  })
                }}
              </span>
            </div>
          </div>
          <button
            type="button"
            :data-testid="`add-member-select-${user.extid}`"
            class="mt-0.5 inline-flex shrink-0 items-center rounded-md bg-brand-600 px-3 py-1.5 text-sm font-semibold text-white shadow-sm hover:bg-brand-700 focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 focus:outline-none dark:bg-brand-500 dark:hover:bg-brand-600"
            @click="choose(user)">
            {{ t('web.admin.organizations.addMember.select') }}
          </button>
        </li>
      </ul>
    </div>

    <!-- Step 2: confirm the account + pick a role ---------------------------- -->
    <div
      v-else
      class="mt-4"
      data-testid="add-member-selected">
      <div
        class="overflow-hidden rounded-lg border border-l-4 border-gray-200 border-l-brand-600 bg-white dark:border-gray-700 dark:border-l-brand-500 dark:bg-gray-900">
        <!-- Identity -->
        <div
          class="flex items-start justify-between gap-4 border-b border-gray-200 bg-gray-50 px-4 py-3 dark:border-gray-700 dark:bg-gray-800/50">
          <div class="min-w-0">
            <p
              class="mb-1 text-xs font-semibold tracking-wide text-brand-600 uppercase dark:text-brand-400">
              {{ t('web.admin.organizations.addMember.selectedEyebrow') }}
            </p>
            <div class="text-sm font-semibold text-gray-900 dark:text-white">
              <RevealEmail :email="selected.email" />
            </div>
            <p
              class="mt-0.5 truncate font-mono text-xs text-gray-500 tabular-nums dark:text-gray-400">
              {{ selected.extid }}
            </p>
          </div>
          <button
            type="button"
            data-testid="add-member-change"
            :disabled="loading"
            class="shrink-0 rounded-md px-2 py-1 text-xs font-medium text-gray-500 hover:bg-gray-100 hover:text-gray-700 focus:ring-2 focus:ring-brand-500 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:text-gray-400 dark:hover:bg-gray-700 dark:hover:text-gray-200"
            @click="clearSelection">
            {{ t('web.admin.organizations.addMember.change') }}
          </button>
        </div>

        <div class="space-y-4 px-4 py-4">
          <!-- Identifying detail -->
          <dl class="grid grid-cols-1 gap-x-6 gap-y-3 sm:grid-cols-3">
            <div data-testid="add-member-field-created">
              <dt
                class="text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
                {{ t('web.admin.organizations.addMember.fields.created') }}
              </dt>
              <dd class="mt-0.5 text-sm text-gray-900 tabular-nums dark:text-gray-100">
                {{ formatDisplayDateTime(selected.created) }}
              </dd>
            </div>
            <div data-testid="add-member-field-verified">
              <dt
                class="text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
                {{ t('web.admin.organizations.addMember.fields.verified') }}
              </dt>
              <dd class="mt-0.5 text-sm text-gray-900 dark:text-gray-100">
                {{
                  selected.verified
                    ? t('web.admin.organizations.addMember.badges.verified')
                    : t('web.admin.organizations.addMember.badges.unverified')
                }}
              </dd>
            </div>
            <div data-testid="add-member-field-lastLogin">
              <dt
                class="text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
                {{ t('web.admin.organizations.addMember.fields.lastLogin') }}
              </dt>
              <dd class="mt-0.5 text-sm text-gray-900 tabular-nums dark:text-gray-100">
                {{
                  selected.last_login
                    ? formatDisplayDateTime(selected.last_login)
                    : t('web.admin.organizations.detail.none')
                }}
              </dd>
            </div>
          </dl>

          <!-- Current organizations (best-effort read) -->
          <div data-testid="add-member-organizations">
            <p
              class="text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
              {{ t('web.admin.organizations.addMember.fields.organizations') }}
            </p>
            <div
              v-if="accountLoading"
              class="mt-1 flex items-center gap-2 text-xs text-gray-400 dark:text-gray-500">
              <OIcon
                collection="heroicons"
                name="arrow-path"
                size="4"
                class="animate-spin motion-reduce:animate-none" />
              {{ t('web.COMMON.loading') }}
            </div>
            <p
              v-else-if="accountLookupFailed"
              class="mt-1 text-xs text-gray-500 dark:text-gray-400"
              data-testid="add-member-organizations-error">
              {{ t('web.admin.organizations.addMember.organizationsUnavailable') }}
            </p>
            <div
              v-else-if="accountOrganizations.length > 0"
              class="mt-1 flex flex-wrap gap-1.5">
              <span
                v-for="org in accountOrganizations"
                :key="org.extid"
                class="inline-flex items-center gap-1 rounded px-2 py-0.5 text-xs font-medium"
                :class="
                  org.extid === orgExtid
                    ? 'bg-amber-100 text-amber-800 dark:bg-amber-900/40 dark:text-amber-200'
                    : 'bg-gray-100 text-gray-700 dark:bg-gray-800 dark:text-gray-300'
                ">
                {{ org.display_name || org.extid }}
                <span
                  v-if="org.is_default"
                  class="text-[10px] tracking-wide uppercase opacity-70">
                  {{ t('web.admin.organizations.addMember.defaultOrg') }}
                </span>
              </span>
            </div>
            <p
              v-else
              class="mt-1 text-xs text-gray-400 dark:text-gray-500">
              {{ t('web.admin.organizations.detail.none') }}
            </p>
          </div>

          <!-- Role selector: exactly the roles the backend accepts. -->
          <div>
            <label
              for="add-member-role"
              class="mb-1 block text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
              {{ t('web.admin.organizations.addMember.roleLabel') }}
            </label>
            <select
              id="add-member-role"
              v-model="role"
              data-testid="add-member-role"
              :disabled="loading || alreadyMember"
              class="w-full rounded-md border border-gray-300 px-3 py-2 text-sm text-gray-900 focus:border-brand-500 focus:ring-brand-500 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 sm:w-64 dark:border-gray-600 dark:bg-gray-800 dark:text-white">
              <option
                v-for="value in MEMBERSHIP_ROLES"
                :key="value"
                :value="value">
                {{ roleLabel(value) }}
              </option>
            </select>
            <p class="mt-1 text-xs text-gray-400 dark:text-gray-500">
              {{ t(`web.admin.organizations.addMember.roleHints.${role}`) }}
            </p>
          </div>
        </div>
      </div>

      <!-- Already a member: the add would be a no-op; point at set-role. -->
      <div
        v-if="alreadyMember"
        class="mt-4 flex items-start gap-2 rounded-md border border-amber-200 bg-amber-50 px-3 py-2 dark:border-amber-900/50 dark:bg-amber-900/20"
        role="alert"
        data-testid="add-member-already-member">
        <OIcon
          collection="heroicons"
          name="information-circle"
          size="5"
          class="mt-0.5 shrink-0 text-amber-600 dark:text-amber-400" />
        <p class="text-sm text-amber-800 dark:text-amber-200">
          {{
            existingRole
              ? t('web.admin.organizations.addMember.errors.alreadyMember', {
                  role: roleLabel(existingRole),
                })
              : t('web.admin.organizations.addMember.errors.alreadyMemberUnknownRole')
          }}
        </p>
      </div>

      <!-- Parent mutation failure (stays put so the operator can retry/cancel). -->
      <div
        v-if="error"
        class="mt-4 rounded-md bg-red-50 p-3 dark:bg-red-900/20"
        role="alert"
        aria-live="assertive"
        data-testid="add-member-error">
        <p class="text-sm text-red-800 dark:text-red-200">
          {{ error }}
        </p>
      </div>
    </div>

    <template #footer>
      <div class="flex justify-end gap-3">
        <button
          type="button"
          data-testid="add-member-cancel"
          :disabled="loading"
          class="inline-flex justify-center rounded-md bg-white px-4 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-gray-300 ring-inset hover:bg-gray-50 focus:ring-2 focus:ring-gray-400 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:bg-gray-700 dark:text-gray-300 dark:ring-gray-600 dark:hover:bg-gray-600"
          @click="emit('update:open', false)">
          {{ t('web.COMMON.word_cancel') }}
        </button>
        <button
          type="button"
          data-testid="add-member-submit"
          :disabled="!canSubmit"
          class="inline-flex items-center justify-center gap-2 rounded-md bg-brand-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-brand-700 focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:bg-brand-500 dark:hover:bg-brand-600"
          @click="onSubmit">
          <OIcon
            v-if="loading"
            collection="heroicons"
            name="arrow-path"
            size="4"
            class="animate-spin motion-reduce:animate-none" />
          {{ loading ? t('web.COMMON.processing') : t('web.admin.organizations.addMember.submit') }}
        </button>
      </div>
    </template>
  </AdminModal>
</template>
