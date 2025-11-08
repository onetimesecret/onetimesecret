<!-- src/components/teams/TeamMembersList.vue -->

<script setup lang="ts">
import ConfirmDialog from '@/components/ConfirmDialog.vue';
import OIcon from '@/components/icons/OIcon.vue';
import { classifyError } from '@/schemas/errors';
import { useTeamStore } from '@/stores/teamStore';
import {
  getRoleBadgeColor,
  getRoleLabel,
  getStatusBadgeColor,
  getStatusLabel,
  TeamRole,
  type TeamMember,
  type TeamWithRole,
} from '@/types/team';
import { Menu, MenuButton, MenuItem, MenuItems } from '@headlessui/vue';
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();

const props = defineProps<{
  team: TeamWithRole;
  members: TeamMember[];
  currentUserId?: string;
}>();

const emit = defineEmits<{
  (e: 'member-removed', memberId: string): void;
  (e: 'role-changed', memberId: string, role: TeamRole): void;
}>();

const teamStore = useTeamStore();

const isProcessing = ref(false);
const error = ref('');
const confirmDialog = ref<{
  show: boolean;
  memberId: string;
  memberEmail: string;
}>({
  show: false,
  memberId: '',
  memberEmail: '',
});

const canManageMembers = computed(() => props.team.current_user_role === TeamRole.OWNER || props.team.current_user_role === TeamRole.ADMIN);

const showRemoveConfirm = (member: TeamMember) => {
  confirmDialog.value = {
    show: true,
    memberId: member.id,
    memberEmail: member.email,
  };
};

const handleRemoveMember = async () => {
  const memberId = confirmDialog.value.memberId;
  confirmDialog.value.show = false;

  if (!memberId || isProcessing.value) return;

  isProcessing.value = true;
  error.value = '';

  try {
    await teamStore.removeMember(props.team.id, memberId);
    emit('member-removed', memberId);
  } catch (err) {
    const classified = classifyError(err);
    error.value = classified.userMessage || t('web.teams.remove_member_error');
  } finally {
    isProcessing.value = false;
  }
};

const handleChangeRole = async (memberId: string, newRole: TeamRole) => {
  if (isProcessing.value) return;

  isProcessing.value = true;
  error.value = '';

  try {
    await teamStore.updateMemberRole(props.team.id, memberId, { role: newRole });
    emit('role-changed', memberId, newRole);
  } catch (err) {
    const classified = classifyError(err);
    error.value = classified.userMessage || t('web.teams.change_role_error');
  } finally {
    isProcessing.value = false;
  }
};

const canModifyMember = (member: TeamMember): boolean => {
  if (!canManageMembers.value) return false;

  // Owners can modify anyone except themselves
  if (props.team.current_user_role === TeamRole.OWNER) {
    return member.user_id !== props.currentUserId;
  }

  // Admins can only modify regular members
  if (props.team.current_user_role === TeamRole.ADMIN) {
    return member.role === TeamRole.MEMBER && member.user_id !== props.currentUserId;
  }

  return false;
};

const getRoleBadge = (role: TeamRole) => ({
  color: getRoleBadgeColor(role),
  label: t(getRoleLabel(role)),
});

const getStatusBadge = (status: string) => ({
  color: getStatusBadgeColor(status as any),
  label: t(getStatusLabel(status as any)),
});
</script>

<template>
  <div class="space-y-4">
    <div v-if="error" class="rounded-md bg-red-50 p-4 dark:bg-red-900/20">
      <p class="text-sm text-red-800 dark:text-red-400">{{ error }}</p>
    </div>

    <div class="overflow-hidden rounded-lg border border-gray-200 bg-white shadow dark:border-gray-700 dark:bg-gray-800">
      <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
        <thead class="bg-gray-50 dark:bg-gray-900">
          <tr>
            <th scope="col" class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
              {{ t('web.teams.member') }}
            </th>
            <th scope="col" class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
              {{ t('web.teams.role') }}
            </th>
            <th scope="col" class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
              {{ t('web.teams.status') }}
            </th>
            <th scope="col" class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
              {{ t('web.teams.joined') }}
            </th>
            <th v-if="canManageMembers"
scope="col"
class="relative px-6 py-3">
              <span class="sr-only">{{ t('web.teams.actions') }}</span>
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-gray-200 bg-white dark:divide-gray-700 dark:bg-gray-800">
          <tr v-for="member in members"
:key="member.id"
class="hover:bg-gray-50 dark:hover:bg-gray-700/50">
            <td class="whitespace-nowrap px-6 py-4">
              <div class="flex items-center">
                <div class="flex size-10 shrink-0 items-center justify-center rounded-full bg-brand-100 dark:bg-brand-900">
                  <OIcon
                    collection="heroicons"
                    name="user"
                    class="size-5 text-brand-600 dark:text-brand-400"
                    aria-hidden="true"
                  />
                </div>
                <div class="ml-4">
                  <div class="text-sm font-medium text-gray-900 dark:text-white">
                    {{ member.email }}
                  </div>
                  <div v-if="member.user_id === currentUserId" class="text-xs text-gray-500 dark:text-gray-400">
                    {{ t('web.teams.you') }}
                  </div>
                </div>
              </div>
            </td>
            <td class="whitespace-nowrap px-6 py-4">
              <span
                :class="[
                  'inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium',
                  getRoleBadge(member.role).color
                ]"
              >
                {{ getRoleBadge(member.role).label }}
              </span>
            </td>
            <td class="whitespace-nowrap px-6 py-4">
              <span
                :class="[
                  'inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium',
                  getStatusBadge(member.status).color
                ]"
              >
                {{ getStatusBadge(member.status).label }}
              </span>
            </td>
            <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500 dark:text-gray-400">
              {{ member.joined_at ? new Date(member.joined_at).toLocaleDateString() : '-' }}
            </td>
            <td v-if="canManageMembers" class="relative whitespace-nowrap px-6 py-4 text-right text-sm font-medium">
              <Menu v-if="canModifyMember(member)"
as="div"
class="relative inline-block text-left">
                <MenuButton
                  :disabled="isProcessing"
                  class="flex items-center rounded-full text-gray-400 hover:text-gray-600 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 dark:text-gray-400 dark:hover:text-gray-300"
                >
                  <span class="sr-only">{{ t('web.teams.open_options') }}</span>
                  <OIcon collection="heroicons-solid"
name="ellipsis-vertical"
class="size-5" />
                </MenuButton>

                <transition
                  enter-active-class="transition ease-out duration-100"
                  enter-from-class="transform opacity-0 scale-95"
                  enter-to-class="transform opacity-100 scale-100"
                  leave-active-class="transition ease-in duration-75"
                  leave-from-class="transform opacity-100 scale-100"
                  leave-to-class="transform opacity-0 scale-95"
                >
                  <MenuItems
                    class="absolute right-0 z-10 mt-2 w-48 origin-top-right rounded-md bg-white shadow-lg ring-1 ring-black ring-opacity-5 focus:outline-none dark:bg-gray-800 dark:ring-gray-700"
                  >
                    <div class="py-1">
                      <MenuItem v-if="team.current_user_role === TeamRole.OWNER && member.role !== TeamRole.ADMIN" v-slot="{ active }">
                        <button
                          @click="handleChangeRole(member.id, TeamRole.ADMIN)"
                          :class="[
                            active ? 'bg-gray-100 text-gray-900 dark:bg-gray-700 dark:text-white' : 'text-gray-700 dark:text-gray-300',
                            'group flex w-full items-center px-4 py-2 text-sm'
                          ]"
                        >
                          <OIcon collection="heroicons"
name="shield-check"
class="mr-3 size-5"
aria-hidden="true" />
                          {{ t('web.teams.make_admin') }}
                        </button>
                      </MenuItem>
                      <MenuItem v-if="team.current_user_role === TeamRole.OWNER && member.role === TeamRole.ADMIN" v-slot="{ active }">
                        <button
                          @click="handleChangeRole(member.id, TeamRole.MEMBER)"
                          :class="[
                            active ? 'bg-gray-100 text-gray-900 dark:bg-gray-700 dark:text-white' : 'text-gray-700 dark:text-gray-300',
                            'group flex w-full items-center px-4 py-2 text-sm'
                          ]"
                        >
                          <OIcon collection="heroicons"
name="user"
class="mr-3 size-5"
aria-hidden="true" />
                          {{ t('web.teams.make_member') }}
                        </button>
                      </MenuItem>
                      <MenuItem v-slot="{ active }">
                        <button
                          @click="showRemoveConfirm(member)"
                          :class="[
                            active ? 'bg-red-50 text-red-900 dark:bg-red-900/20 dark:text-red-400' : 'text-red-700 dark:text-red-400',
                            'group flex w-full items-center px-4 py-2 text-sm'
                          ]"
                        >
                          <OIcon collection="heroicons"
name="user-minus"
class="mr-3 size-5"
aria-hidden="true" />
                          {{ t('web.teams.remove_member') }}
                        </button>
                      </MenuItem>
                    </div>
                  </MenuItems>
                </transition>
              </Menu>
            </td>
          </tr>

          <tr v-if="members.length === 0">
            <td colspan="5" class="px-6 py-12 text-center text-sm text-gray-500 dark:text-gray-400">
              {{ t('web.teams.no_members') }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <ConfirmDialog
      v-if="confirmDialog.show"
      :title="t('web.teams.remove_member_confirm_title')"
      :message="t('web.teams.remove_member_confirm_message', { email: confirmDialog.memberEmail })"
      :confirm-text="t('web.teams.remove')"
      :cancel-text="t('web.COMMON.word_cancel')"
      type="danger"
      @confirm="handleRemoveMember"
      @cancel="confirmDialog.show = false"
    />
  </div>
</template>
