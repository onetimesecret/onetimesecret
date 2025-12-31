<!-- src/apps/workspace/members/MembersList.vue -->

<script setup lang="ts">
import MembersTable from '@/apps/workspace/components/members/MembersTable.vue';
import TableSkeleton from '@/shared/components/closet/TableSkeleton.vue';
import EmptyState from '@/shared/components/ui/EmptyState.vue';
import ErrorDisplay from '@/shared/components/ui/ErrorDisplay.vue';
import { useMembersManager } from '@/shared/composables/useMembersManager';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import type { OrganizationMember } from '@/types/organization';
import { storeToRefs } from 'pinia';
import { computed, onMounted, onUnmounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';

const { t } = useI18n();
const route = useRoute();

const orgStore = useOrganizationStore();
const { currentOrganization } = storeToRefs(orgStore);

const {
  members,
  isLoading,
  error,
  memberCount,
  canManageMembers,
  fetchMembers,
  clearError,
} = useMembersManager();

const orgExtid = computed(() => route.params.extid as string);

const membersList = computed(() => members.value ?? []);

const loadMembers = async () => {
  if (orgExtid.value) {
    clearError();
    await fetchMembers(orgExtid.value);
  }
};

const handleMemberUpdated = (member: OrganizationMember) => {
  // The store is already updated, but we could add additional handling here
  console.debug('[MembersList] Member updated:', member.extid);
};

const handleMemberRemoved = (memberExtid: string) => {
  // The store is already updated, but we could add additional handling here
  console.debug('[MembersList] Member removed:', memberExtid);
};

// Load members when component mounts or org changes
onMounted(() => {
  loadMembers();
});

// Watch for route param changes
watch(
  () => route.params.extid,
  (newExtid) => {
    if (newExtid) {
      loadMembers();
    }
  }
);

// Fetch organization if not already loaded
watch(
  orgExtid,
  async (extid) => {
    if (extid && !currentOrganization.value) {
      await orgStore.fetchOrganization(extid);
    }
  },
  { immediate: true }
);

onUnmounted(() => {
  clearError();
});
</script>

<template>
  <div class="container mx-auto min-w-[320px] max-w-4xl">
    <!-- Error Display -->
    <ErrorDisplay
      v-if="error"
      :error="error" />

    <!-- Loading State -->
    <div v-if="isLoading && memberCount === 0">
      <TableSkeleton />
    </div>

    <!-- Content -->
    <div v-else>
      <!-- Members Table -->
      <MembersTable
        v-if="memberCount > 0"
        :members="membersList"
        :org-extid="orgExtid"
        :is-loading="isLoading"
        @member-updated="handleMemberUpdated"
        @member-removed="handleMemberRemoved" />

      <!-- Empty State -->
      <EmptyState
        v-else
        :show-action="false">
        <template #title>
          {{ t('web.organizations.members.no_members') }}
        </template>
        <template #description>
          {{ t('web.organizations.members.no_members_description') }}
        </template>
      </EmptyState>
    </div>

    <!-- Permission Notice -->
    <div
      v-if="!canManageMembers && memberCount > 0"
      class="mt-4 rounded-md bg-gray-50 p-4 dark:bg-gray-800">
      <p class="text-sm text-gray-600 dark:text-gray-400">
        {{ t('web.organizations.members.insufficient_permissions') }}
      </p>
    </div>
  </div>
</template>
