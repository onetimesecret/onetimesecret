<!-- src/apps/workspace/components/members/MembersTable.vue -->

<script setup lang="ts">
import MemberRoleSelector from '@/apps/workspace/components/members/MemberRoleSelector.vue';
import OIcon from '@/shared/components/icons/OIcon.vue';
import ConfirmDialog from '@/shared/components/modals/ConfirmDialog.vue';
import { useMembersManager } from '@/shared/composables/useMembersManager';
import type { OrganizationMember, OrganizationRole } from '@/types/organization';
import { useConfirmDialog } from '@vueuse/core';
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();

const props = defineProps<{
  members: OrganizationMember[];
  orgExtid: string;
  isLoading: boolean;
}>();

const emit = defineEmits<{
  (e: 'member-updated', member: OrganizationMember): void;
  (e: 'member-removed', memberExtid: string): void;
}>();

const {
  canModifyMember,
  canChangeRole,
  getAssignableRoles,
  updateMemberRole,
  removeMember,
  getRoleLabel,
} = useMembersManager();

const { isRevealed, reveal, confirm, cancel } = useConfirmDialog();

const memberToRemove = ref<OrganizationMember | null>(null);

const handleRoleChange = async (member: OrganizationMember, newRole: OrganizationRole) => {
  if (newRole === member.role) return;

  const result = await updateMemberRole(props.orgExtid, member.extid, newRole);
  if (result) {
    emit('member-updated', result);
  }
};

const handleRemoveClick = async (member: OrganizationMember) => {
  memberToRemove.value = member;
  const confirmed = await reveal();

  if (confirmed) {
    const success = await removeMember(props.orgExtid, member.extid);
    if (success) {
      emit('member-removed', member.extid);
    }
  }

  memberToRemove.value = null;
};

const formatDate = (date: Date): string => new Intl.DateTimeFormat(undefined, {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  }).format(date);

const getRoleBadgeClasses = (role: OrganizationRole): string => {
  const baseClasses =
    'inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium';

  switch (role) {
    case 'owner':
      return `${baseClasses} bg-amber-100 text-amber-800 dark:bg-amber-900/30 dark:text-amber-400`;
    case 'admin':
      return `${baseClasses} bg-blue-100 text-blue-800 dark:bg-blue-900/30 dark:text-blue-400`;
    case 'member':
    default:
      return `${baseClasses} bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-300`;
  }
};
</script>

<template>
  <div>
    <section
      class="rounded-lg bg-white p-4 shadow-sm dark:bg-gray-900 sm:p-6 lg:p-8"
      aria-labelledby="members-heading">
      <!-- Header Section -->
      <div class="mb-6 flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1
            id="members-heading"
            class="text-2xl font-bold tracking-tight text-gray-900 dark:text-white">
            {{ t('web.organizations.members.title') }}
          </h1>
          <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
            {{ t('web.organizations.members.description') }}
          </p>
        </div>
      </div>

      <!-- Members Table -->
      <div class="relative rounded-lg border border-gray-200 dark:border-gray-700">
        <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
          <thead class="bg-gray-50 font-brand dark:bg-gray-800">
            <tr>
              <th
                scope="col"
                class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
                {{ t('web.organizations.members.member') }}
              </th>
              <th
                scope="col"
                class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
                {{ t('web.organizations.members.role') }}
              </th>
              <th
                scope="col"
                class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
                {{ t('web.organizations.members.joined') }}
              </th>
              <th
                scope="col"
                class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
                {{ t('web.organizations.members.actions') }}
              </th>
            </tr>
          </thead>

          <tbody class="divide-y divide-gray-200 bg-white dark:divide-gray-700 dark:bg-gray-900">
            <tr
              v-for="member in members"
              :key="member.extid"
              class="transition-colors duration-150 hover:bg-gray-50 dark:hover:bg-gray-800">
              <!-- Member Info -->
              <td class="whitespace-nowrap px-6 py-4">
                <div class="flex items-center">
                  <div
                    class="flex size-10 shrink-0 items-center justify-center rounded-full bg-gray-200 dark:bg-gray-700">
                    <OIcon
                      collection="heroicons"
                      name="user"
                      class="size-5 text-gray-500 dark:text-gray-400"
                      aria-hidden="true" />
                  </div>
                  <div class="ml-4">
                    <div class="font-medium text-gray-900 dark:text-white">
                      {{ member.display_name || member.email }}
                    </div>
                    <div
                      v-if="member.display_name"
                      class="text-sm text-gray-500 dark:text-gray-400">
                      {{ member.email }}
                    </div>
                  </div>
                </div>
              </td>

              <!-- Role -->
              <td class="whitespace-nowrap px-6 py-4">
                <MemberRoleSelector
                  v-if="canChangeRole(member)"
                  :model-value="member.role"
                  :available-roles="getAssignableRoles()"
                  :disabled="isLoading"
                  @update:model-value="(role) => handleRoleChange(member, role)" />
                <span
                  v-else
                  :class="getRoleBadgeClasses(member.role)">
                  {{ getRoleLabel(member.role) }}
                </span>
              </td>

              <!-- Joined Date -->
              <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500 dark:text-gray-400">
                {{ formatDate(member.joined_at) }}
              </td>

              <!-- Actions -->
              <td class="whitespace-nowrap px-6 py-4 text-right text-sm font-medium">
                <button
                  v-if="canModifyMember(member)"
                  type="button"
                  :disabled="isLoading"
                  class="text-red-600 hover:text-red-900 disabled:cursor-not-allowed disabled:opacity-50 dark:text-red-400 dark:hover:text-red-300"
                  :aria-label="t('web.organizations.members.remove_member_title')"
                  @click="handleRemoveClick(member)">
                  <OIcon
                    collection="heroicons"
                    name="trash"
                    class="size-5" />
                </button>
                <span
                  v-else
                  class="text-gray-400 dark:text-gray-600">
                  --
                </span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <!-- Confirm Remove Dialog -->
    <ConfirmDialog
      v-if="isRevealed && memberToRemove"
      :title="t('web.organizations.members.remove_member_title')"
      :message="t('web.organizations.members.remove_member_confirm', { name: memberToRemove.display_name || memberToRemove.email })"
      type="danger"
      @confirm="confirm"
      @cancel="cancel" />
  </div>
</template>
