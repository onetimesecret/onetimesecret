<!-- src/apps/admin/components/organizations/OrganizationMembersSection.vue -->

<script setup lang="ts">
  import { AdminConfirmDialog, DataTable } from '@/apps/admin/components/kit';
  import type { DataTableColumn } from '@/apps/admin/components/kit';
  import {
    CHANGEABLE_MEMBERSHIP_ROLES,
    colonelRemoveMembershipResponseSchema,
    colonelSetMembershipRoleResponseSchema,
    type ChangeableMembershipRole,
  } from '@/apps/admin/components/organizations/membershipSchemas';
  import RevealEmail from '@/apps/admin/components/RevealEmail.vue';
  import { useAdminDestructiveMutation } from '@/apps/admin/composables/useAdminDestructiveMutation';
  import { accountConfirmToken, confirmHeaders } from '@/apps/admin/utils/confirmHeader';
  import { reasonBody, reasonQueryArgs } from '@/apps/admin/utils/operatorReason';
  import type { ColonelOrganizationDetailMember } from '@/schemas/api/internal/responses/colonel-organizations';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useApi } from '@/shared/composables/useApi';
  import { useNotificationsStore } from '@/shared/stores/notificationsStore';
  import { formatDisplayDateTime } from '@/utils/format';
  import { gracefulParse } from '@/utils/schemaValidation';
  import { computed, ref } from 'vue';
  import { useI18n } from 'vue-i18n';

  /**
   * The organization's member roster, plus the two per-member TIER 1 verbs:
   *
   *   POST   :org/members/:member_id/role   — change an existing member's role
   *   DELETE :org/members/:member_id        — remove the membership
   *
   * Both are thin adapters over the same ops `bin/ots memberships set-role` /
   * `remove` use, and both are gated server-side on step-up elevation AND an
   * X-OTS-Confirm token that is the MEMBER's account identifier (their email,
   * their public id when they have none — `account_confirm_token`). The typed
   * confirmation asks for that same value, so the dialog cannot ask for one
   * thing while the server checks another.
   *
   * ## Elevation comes before the dialog
   *
   * Each opener awaits `ensureElevated()` and only then opens its dialog, so the
   * operator proves the credential once and fills in the role, reason and typed
   * token once. The request still runs through useAdminDestructiveMutation,
   * whose 403 -> prompt -> retry-once loop covers a window that lapses while the
   * dialog is open.
   *
   * ## The owner row is locked
   *
   * Removing or demoting the owner here would orphan the org or split the
   * `owner_id` mirror from the owner membership, so both controls are disabled
   * on that row. Ownership moves only through a transfer of ownership
   * (`Onetime::Operations::Org::TransferOwnership`), which promotes, pivots and
   * demotes together. The server's sole-owner guard refuses the same requests;
   * this lock only spares the operator a typed confirmation that cannot succeed.
   *
   * Success shows a notice and emits `changed`; the parent refetches the detail
   * GET, so the roster is always drawn from live state, never from an ack.
   */
  const props = defineProps<{
    /** The org resource URL, `/api/colonel/organizations/:org_id`. */
    orgUrl: string;
    /** The organization's display heading, for the confirm copy. */
    orgName: string;
    /** `details.members` from the detail GET. */
    members: ColonelOrganizationDetailMember[];
  }>();

  const emit = defineEmits<{
    /** A membership changed server-side; the parent refetches the detail. */
    changed: [];
  }>();

  defineSlots<{
    /** Header controls beside the section title (the add-member button). */
    actions?: () => unknown;
  }>();

  const { t } = useI18n();
  const $api = useApi();
  const notifications = useNotificationsStore();

  const columns = computed<DataTableColumn<ColonelOrganizationDetailMember>[]>(() => [
    { key: 'email', label: t('web.admin.organizations.detail.members.email') },
    { key: 'role', label: t('web.admin.organizations.detail.members.role') },
    { key: 'status', label: t('web.admin.organizations.detail.members.status') },
    { key: 'joined', label: t('web.admin.organizations.detail.members.joined') },
    {
      key: 'actions',
      label: t('web.admin.organizations.members.columns.actions'),
      align: 'right',
    },
  ]);

  /** The owner is `owner_id`, but any `owner` membership is locked the same way. */
  function isOwnerRow(member: ColonelOrganizationDetailMember): boolean {
    return member.is_owner || member.role === 'owner';
  }

  function roleLabel(role: string | null | undefined): string {
    if (!role) return '—';
    return t(`web.admin.organizations.addMember.roles.${role}`, role);
  }

  /** How the dialogs name a member: the address the operator will retype. */
  function memberLabel(member: ColonelOrganizationDetailMember | null): string {
    return member?.email || member?.extid || '';
  }

  function memberUrl(member: ColonelOrganizationDetailMember): string {
    return `${props.orgUrl}/members/${encodeURIComponent(member.extid)}`;
  }

  /**
   * True while an opener waits on the elevation prompt. A second request would
   * share the same prompt and resolve with the same answer, so without this a
   * second click (say, Remove on another row) would open its dialog alongside
   * the first one's. Also keeps the row controls busy meanwhile.
   */
  const opening = ref(false);

  /**
   * Prove the credential, THEN open the action's dialog. A cancelled prompt
   * opens nothing. Fails closed when the member has no confirmation token: the
   * dialog would otherwise degrade to a one-click confirm.
   */
  async function openAfterElevation(
    member: ColonelOrganizationDetailMember,
    open: () => void
  ): Promise<void> {
    if (isOwnerRow(member) || opening.value || !accountConfirmToken(member)) return;
    opening.value = true;
    let elevated = false;
    try {
      // Both mutations hand back the same shared seam; either one will do.
      elevated = await ensureElevated();
    } finally {
      opening.value = false;
    }
    if (elevated) open();
  }

  // ---- Change role ------------------------------------------------------------

  const roleDialogOpen = ref(false);
  const roleTarget = ref<ColonelOrganizationDetailMember | null>(null);
  const pendingRole = ref<ChangeableMembershipRole>(CHANGEABLE_MEMBERSHIP_ROLES[0]);

  /** Every changeable role except the one the member already holds. */
  const roleOptions = computed(() =>
    CHANGEABLE_MEMBERSHIP_ROLES.filter((role) => role !== roleTarget.value?.role)
  );

  const roleTargetToken = computed(() => accountConfirmToken(roleTarget.value));
  let roleNoChangeMessage: string | null = null;

  const {
    loading: roleLoading,
    error: roleError,
    run: runRoleChange,
    reset: resetRoleChange,
    ensureElevated,
  } = useAdminDestructiveMutation(async (reason?: string) => {
    roleNoChangeMessage = null;
    const target = roleTarget.value;
    const token = accountConfirmToken(target);
    if (!target || !token) throw new Error('No member selected');

    const response = await $api.post(
      `${memberUrl(target)}/role`,
      { role: pendingRole.value, ...reasonBody(reason) },
      { headers: confirmHeaders(token) }
    );
    const parsed = gracefulParse(
      colonelSetMembershipRoleResponseSchema,
      response.data,
      'ColonelSetMembershipRoleResponse'
    );
    // `no_change` means the roster was stale: close and refresh as for a
    // change, but report it as information. Ack drift stays non-fatal:
    // an unparseable 2xx is still a success.
    if (parsed.ok && parsed.data.record.status === 'no_change') {
      roleNoChangeMessage = t('web.admin.organizations.members.changeRole.noChange', {
        role: roleLabel(parsed.data.record.to ?? pendingRole.value),
      });
    }
  });

  function requestRoleChange(member: ColonelOrganizationDetailMember): Promise<void> {
    return openAfterElevation(member, () => {
      roleTarget.value = member;
      pendingRole.value = roleOptions.value[0] ?? CHANGEABLE_MEMBERSHIP_ROLES[0];
      resetRoleChange();
      roleDialogOpen.value = true;
    });
  }

  async function onRoleConfirm(reason?: string): Promise<void> {
    const target = roleTarget.value;
    if (!target) return;
    const role = pendingRole.value;

    if (!(await runRoleChange(reason))) return; // Failure stays in the dialog.

    roleDialogOpen.value = false;
    roleTarget.value = null;
    notifications.show(
      roleNoChangeMessage ??
        t('web.admin.organizations.members.changeRole.success', {
          member: target.extid,
          role: roleLabel(role),
        }),
      roleNoChangeMessage ? 'info' : 'success'
    );
    emit('changed');
  }

  function onRoleCancel(): void {
    roleDialogOpen.value = false;
    roleTarget.value = null;
    resetRoleChange();
  }

  // ---- Remove membership --------------------------------------------------

  const removeDialogOpen = ref(false);
  const removeTarget = ref<ColonelOrganizationDetailMember | null>(null);
  const removeTargetToken = computed(() => accountConfirmToken(removeTarget.value));

  const {
    loading: removeLoading,
    error: removeError,
    run: runRemove,
    reset: resetRemove,
  } = useAdminDestructiveMutation(async (reason?: string) => {
    const target = removeTarget.value;
    const token = accountConfirmToken(target);
    if (!target || !token) throw new Error('No member selected');

    // DELETE: the optional reason rides the query string (operatorReason.ts),
    // the confirmation token rides the header.
    const [reasonConfig] = reasonQueryArgs(reason);
    const response = await $api.delete(memberUrl(target), {
      headers: confirmHeaders(token),
      ...reasonConfig,
    });
    // Tripwire only: refusals (not_found, last_owner) arrive as 4xx.
    gracefulParse(
      colonelRemoveMembershipResponseSchema,
      response.data,
      'ColonelRemoveMembershipResponse'
    );
  });

  function requestRemove(member: ColonelOrganizationDetailMember): Promise<void> {
    return openAfterElevation(member, () => {
      removeTarget.value = member;
      resetRemove();
      removeDialogOpen.value = true;
    });
  }

  async function onRemoveConfirm(reason?: string): Promise<void> {
    const target = removeTarget.value;
    if (!target) return;

    if (!(await runRemove(reason))) return; // Failure stays in the dialog.

    removeDialogOpen.value = false;
    removeTarget.value = null;
    notifications.show(
      t('web.admin.organizations.members.remove.success', {
        member: target.extid,
        org: props.orgName,
      }),
      'success'
    );
    emit('changed');
  }

  function onRemoveCancel(): void {
    removeDialogOpen.value = false;
    removeTarget.value = null;
    resetRemove();
  }

  /** Row controls stay inert while any member action is opening or in flight. */
  const busy = computed(() => opening.value || roleLoading.value || removeLoading.value);
</script>

<template>
  <section
    class="rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-800 dark:bg-gray-900"
    data-testid="members-section">
    <div
      class="flex flex-wrap items-center justify-between gap-3 border-b border-gray-200 px-6 py-4 dark:border-gray-800">
      <h3 class="text-lg font-medium text-gray-900 dark:text-white">
        {{ t('web.admin.organizations.detail.sections.members') }}
        <span class="ml-1 text-sm font-normal text-gray-500 dark:text-gray-400"
          >({{ members.length }})</span
        >
      </h3>
      <slot name="actions"></slot>
    </div>
    <DataTable
      :columns="columns"
      :rows="members"
      row-key="extid"
      :empty-text="t('web.admin.organizations.detail.members.empty')"
      testid="members-table">
      <template #cell-email="{ row }">
        <span class="inline-flex items-center gap-2">
          <RevealEmail :email="row.email" />
          <span
            v-if="row.is_owner"
            class="inline-flex shrink-0 rounded bg-brand-50 px-1.5 py-0.5 text-xs font-medium text-brand-700 dark:bg-brand-900/30 dark:text-brand-300">
            {{ t('web.admin.organizations.detail.members.owner') }}
          </span>
        </span>
        <!-- The customer's PUBLIC id, and the way through to their record.
             A real router-link, not a row-click handler, so middle-click and
             open-in-new-tab work — the operator comparing several members
             wants them side by side. GetUserDetails resolves by extid first
             (see its #process comment), so the extid IS the route param. -->
        <router-link
          :to="{ name: 'AdminCustomerDetail', params: { id: row.extid } }"
          :data-testid="`member-detail-${row.extid}`"
          :title="t('web.admin.organizations.detail.members.openCustomer')"
          class="mt-0.5 inline-flex items-center gap-1 font-mono text-xs text-gray-500 hover:text-brand-600 hover:underline focus:ring-2 focus:ring-brand-500 focus:outline-none dark:text-gray-400 dark:hover:text-brand-400">
          {{ row.extid }}
          <OIcon
            collection="heroicons"
            name="arrow-top-right-on-square"
            size="3"
            aria-hidden="true" />
          <span class="sr-only">{{
            t('web.admin.organizations.detail.members.openCustomer')
          }}</span>
        </router-link>
      </template>
      <template #cell-role="{ row }">
        {{ row.role || '—' }}
      </template>
      <template #cell-status="{ row }">
        {{ row.status || '—' }}
      </template>
      <template #cell-joined="{ row }">
        {{ row.joined_at ? formatDisplayDateTime(row.joined_at) : '—' }}
      </template>
      <template #cell-actions="{ row }">
        <!-- The title sits on the wrapper: a disabled button does not raise
             mouse events in every browser, so its own title may never show. -->
        <div
          class="flex flex-wrap justify-end gap-2"
          :title="isOwnerRow(row) ? t('web.admin.organizations.members.ownerLocked') : undefined"
          :data-testid="`member-actions-${row.extid}`">
          <button
            type="button"
            :data-testid="`member-change-role-${row.extid}`"
            :disabled="isOwnerRow(row) || busy"
            :aria-label="
              t('web.admin.organizations.members.changeRole.ariaLabel', { member: row.extid })
            "
            class="inline-flex items-center gap-1 rounded-md border border-gray-300 px-2.5 py-1.5 text-xs font-medium text-gray-700 hover:bg-gray-50 focus:ring-2 focus:ring-brand-500 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-800"
            @click="requestRoleChange(row)">
            <OIcon
              collection="heroicons"
              name="arrows-right-left"
              size="3"
              aria-hidden="true" />
            {{ t('web.admin.organizations.members.changeRole.button') }}
          </button>
          <button
            type="button"
            :data-testid="`member-remove-${row.extid}`"
            :disabled="isOwnerRow(row) || busy"
            :aria-label="
              t('web.admin.organizations.members.remove.ariaLabel', { member: row.extid })
            "
            class="inline-flex items-center gap-1 rounded-md border border-red-300 px-2.5 py-1.5 text-xs font-medium text-red-700 hover:bg-red-50 focus:ring-2 focus:ring-red-500 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:border-red-800 dark:text-red-300 dark:hover:bg-red-900/30"
            @click="requestRemove(row)">
            <OIcon
              collection="heroicons"
              name="user-minus"
              size="3"
              aria-hidden="true" />
            {{ t('web.admin.organizations.members.remove.button') }}
          </button>
          <span
            v-if="isOwnerRow(row)"
            class="sr-only"
            >{{ t('web.admin.organizations.members.ownerLocked') }}</span
          >
        </div>
      </template>
    </DataTable>

    <!-- Change role (TIER 1 — typed confirmation: retype the member's email). -->
    <AdminConfirmDialog
      v-model:open="roleDialogOpen"
      :title="t('web.admin.organizations.members.changeRole.title')"
      :confirm-token="roleTargetToken"
      variant="danger"
      :confirm-text="t('web.admin.organizations.members.changeRole.confirm')"
      request-reason
      :loading="roleLoading"
      :error="roleError"
      @confirm="onRoleConfirm"
      @cancel="onRoleCancel">
      <template #description>
        <div
          class="space-y-3 text-sm text-gray-600 dark:text-gray-300"
          data-testid="member-role-dialog">
          <p>
            {{
              t('web.admin.organizations.members.changeRole.description', {
                member: memberLabel(roleTarget),
                org: orgName,
              })
            }}
          </p>
          <p class="text-xs text-gray-500 dark:text-gray-400">
            {{
              t('web.admin.organizations.members.changeRole.currentRole', {
                role: roleLabel(roleTarget?.role),
              })
            }}
          </p>
          <div>
            <label
              for="member-role-select"
              class="block text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
              {{ t('web.admin.organizations.members.changeRole.roleLabel') }}
            </label>
            <select
              id="member-role-select"
              v-model="pendingRole"
              data-testid="member-role-select"
              :disabled="roleLoading"
              class="mt-1 block w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-sm text-gray-700 focus:border-brand-500 focus:ring-1 focus:ring-brand-500 focus:outline-none disabled:opacity-50 dark:border-gray-600 dark:bg-gray-800 dark:text-gray-300">
              <option
                v-for="role in roleOptions"
                :key="role"
                :value="role">
                {{ roleLabel(role) }}
              </option>
            </select>
          </div>
        </div>
      </template>
    </AdminConfirmDialog>

    <!-- Remove membership (TIER 1 — typed confirmation: retype the member's email). -->
    <AdminConfirmDialog
      v-model:open="removeDialogOpen"
      :title="t('web.admin.organizations.members.remove.title')"
      :description="
        t('web.admin.organizations.members.remove.description', {
          member: memberLabel(removeTarget),
          org: orgName,
        })
      "
      :confirm-token="removeTargetToken"
      variant="danger"
      :confirm-text="t('web.admin.organizations.members.remove.confirm')"
      request-reason
      :loading="removeLoading"
      :error="removeError"
      @confirm="onRemoveConfirm"
      @cancel="onRemoveCancel" />
  </section>
</template>
