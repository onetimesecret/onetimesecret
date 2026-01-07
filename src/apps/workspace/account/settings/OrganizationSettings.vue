<!-- src/apps/workspace/account/settings/OrganizationSettings.vue -->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import BasicFormAlerts from '@/shared/components/forms/BasicFormAlerts.vue';
import OIcon from '@/shared/components/icons/OIcon.vue';
import MembersTable from '@/apps/workspace/components/members/MembersTable.vue';
import EntitlementUpgradePrompt from '@/apps/workspace/components/billing/EntitlementUpgradePrompt.vue';
import { useEntitlements } from '@/shared/composables/useEntitlements';
import { useAsyncHandler } from '@/shared/composables/useAsyncHandler';
import { useEntitlementError } from '@/shared/composables/useEntitlementError';
import { classifyError } from '@/schemas/errors';
import type { ApplicationError } from '@/schemas/errors';
import { BillingService } from '@/services/billing.service';
import { WindowService } from '@/services/window.service';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import { useMembersStore } from '@/shared/stores/membersStore';
import type { Subscription } from '@/types/billing';
import { getPlanLabel, getSubscriptionStatusLabel } from '@/types/billing';
import type { CreateInvitationPayload, Organization, OrganizationInvitation } from '@/types/organization';
import { computed, onMounted, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { z } from 'zod';

const { t } = useI18n();
const route = useRoute();
const organizationStore = useOrganizationStore();
const membersStore = useMembersStore();

const orgId = computed(() => route.params.extid as string);
const organization = ref<Organization | null>(null);
const subscription = ref<Subscription | null>(null);
const invitations = ref<OrganizationInvitation[]>([]);

/**
 * UX Principle: Optimize for frequency of use
 *
 * Tab order and default selection follow the principle that the most frequently
 * performed actions should require the fewest clicks. When users navigate to an
 * organization's detail page, their intent hierarchy is typically:
 *
 *   1. Team (members)  - Most frequent: invite members, manage roles, review team
 *   2. Billing         - Occasional: check plan, view usage, upgrade
 *   3. Settings        - Rare: change org name or billing email (set-and-forget)
 *
 * By defaulting to the Team tab, we eliminate one click for the most common
 * workflow. Settings (formerly "General") is placed last since org name and
 * billing email rarely change after initial setup.
 *
 * This aligns with Fitts's Law corollary: reduce interaction cost for frequent
 * actions, accept higher cost for infrequent ones.
 */
const activeTab = ref<'general' | 'members' | 'billing'>('members');

const isLoading = ref(false);
const isSaving = ref(false);
const isLoadingBilling = ref(false);
const error = ref('');
const success = ref('');

// Invitation form state
const showInviteForm = ref(false);
const inviteFormData = ref<CreateInvitationPayload>({
  email: '',
  role: 'member',
});
const inviteErrors = ref<Record<string, string>>({});
const inviteGeneralError = ref('');
const inviteUpgradeError = ref<ApplicationError | null>(null);
const isInviting = ref(false);

const { wrap } = useAsyncHandler({
  notify: false,
});

const billingEnabled = computed(() => WindowService.get('billing_enabled') ?? false);

// Entitlements - formatEntitlement uses API-driven i18n keys
const {
  entitlements,
  can,
  formatEntitlement,
  initDefinitions,
  isLoadingDefinitions,
  definitionsError,
  ENTITLEMENTS,
} = useEntitlements(organization);

/**
 * Determine if this is a single-user Identity Plus account.
 * Identity Plus has custom domains but not multi-team entitlements.
 */
const isIdentityPlus = computed(() => can(ENTITLEMENTS.CUSTOM_DOMAINS));

/**
 * Determine if this is the user's default organization.
 * Billing is managed through the default organization only.
 */
const isDefaultOrganization = computed(() => organization.value?.is_default ?? false);

// Form data
const formData = ref({
  display_name: '',
  description: '',
  contact_email: '',
});

const isDirty = computed(() => {
  if (!organization.value) return false;
  return (
    formData.value.display_name !== organization.value.display_name ||
    formData.value.description !== (organization.value.description || '') ||
    formData.value.contact_email !== (organization.value.contact_email || '')
  );
});

const loadOrganization = async () => {
  isLoading.value = true;
  error.value = '';
  try {
    const org = await organizationStore.fetchOrganization(orgId.value);
    if (org) {
      organization.value = org;
      formData.value = {
        display_name: org.display_name,
        description: org.description || '',
        contact_email: org.contact_email || '',
      };
    } else {
      error.value = t('web.organizations.not_found');
    }
  } catch (err) {
    const classified = classifyError(err);
    error.value = classified.message || t('web.organizations.load_error');
    console.error('[OrganizationSettings] Error loading organization:', err);
  } finally {
    isLoading.value = false;
  }
};

const loadInvitations = async () => {
  try {
    invitations.value = await organizationStore.fetchInvitations(orgId.value);
  } catch (err) {
    console.error('[OrganizationSettings] Error loading invitations:', err);
  }
};

const loadMembers = async () => {
  try {
    await membersStore.fetchMembers(orgId.value);
  } catch (err) {
    console.error('[OrganizationSettings] Error loading members:', err);
  }
};

const loadBilling = async () => {
  if (!billingEnabled.value) return;

  isLoadingBilling.value = true;
  try {
    if (organization.value?.extid) {
      const overview = await BillingService.getOverview(organization.value.extid);

      // Convert API response to Subscription type
      if (overview.subscription && overview.plan) {
        subscription.value = {
          id: overview.subscription.id,
          org_id: organization.value.id,
          plan_type: overview.plan.tier as any,
          status: overview.subscription.status as any,
          teams_limit: overview.plan.limits.teams || 0,
          teams_used: overview.usage.teams,
          members_per_team_limit: overview.plan.limits.members_per_team || 0,
          billing_interval: overview.plan.interval as any,
          current_period_start: new Date(overview.subscription.period_end * 1000), // Placeholder
          current_period_end: new Date(overview.subscription.period_end * 1000),
          cancel_at_period_end: overview.subscription.canceled,
          created_at: new Date(),
          updated_at: new Date(),
        };
      } else {
        subscription.value = null;
      }
    } else {
      subscription.value = null;
    }
  } catch (err) {
    console.error('[OrganizationSettings] Error loading billing:', err);
  } finally {
    isLoadingBilling.value = false;
  }
};

const handleSave = async () => {
  if (!organization.value || !isDirty.value) return;

  isSaving.value = true;
  error.value = '';
  success.value = '';

  try {
    // Use extid from route params for API call
    await organizationStore.updateOrganization(orgId.value, {
      display_name: formData.value.display_name,
      description: formData.value.description,
    });
    success.value = t('web.organizations.update_success');
    await loadOrganization(); // Reload to get latest data
  } catch (err) {
    const classified = classifyError(err);
    error.value = classified.message || t('web.organizations.update_error');
    console.error('[OrganizationSettings] Error updating organization:', err);
  } finally {
    isSaving.value = false;
  }
};

const handleCancel = () => {
  if (organization.value) {
    formData.value = {
      display_name: organization.value.display_name,
      description: organization.value.description || '',
      contact_email: organization.value.contact_email || '',
    };
  }
};

const handleInviteMember = async () => {
  if (isInviting.value) return;

  inviteErrors.value = {};
  inviteGeneralError.value = '';
  inviteUpgradeError.value = null;
  isInviting.value = true;

  try {
    await organizationStore.createInvitation(orgId.value, inviteFormData.value);

    inviteFormData.value = {
      email: '',
      role: 'member',
    };
    showInviteForm.value = false;
    success.value = t('web.organizations.invitations.invite_sent');

    await loadInvitations();
  } catch (err) {
    if (err instanceof z.ZodError) {
      err.issues.forEach((issue) => {
        const field = issue.path[0] as string;
        inviteErrors.value[field] = issue.message;
      });
    } else {
      const classified = classifyError(err);
      const { isUpgradeRequired } = useEntitlementError(classified);

      // Check if this is an upgrade-required error
      if (isUpgradeRequired.value) {
        inviteUpgradeError.value = classified;
      } else {
        inviteGeneralError.value = classified.message || t('web.organizations.invitations.invite_error');
      }
    }
  } finally {
    isInviting.value = false;
  }
};

const handleResendInvitation = async (token: string) => {
  error.value = '';
  success.value = '';

  const result = await wrap(() => organizationStore.resendInvitation(orgId.value, token));

  if (result !== null) {
    success.value = t('web.organizations.invitations.resend_success');
    await loadInvitations(); // Refresh the list
  } else {
    error.value = t('web.organizations.invitations.resend_error');
  }
};

const handleRevokeInvitation = async (token: string) => {
  error.value = '';
  success.value = '';

  const result = await wrap(() => organizationStore.revokeInvitation(orgId.value, token));

  if (result !== null) {
    success.value = t('web.organizations.invitations.revoke_success');
    await loadInvitations(); // Refresh the list
  } else {
    error.value = t('web.organizations.invitations.revoke_error');
  }
};

const _formatDate = (timestamp: number): string => new Date(timestamp * 1000).toLocaleDateString(undefined, {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  });

const canManageMembers = computed(() => {
  if (!organization.value) return false;
  return can(ENTITLEMENTS.MANAGE_MEMBERS);
});

// Member management event handlers
const handleMemberUpdated = () => {
  // Member was updated in the store, no additional action needed
  success.value = t('web.organizations.members.role_updated');
};

const handleMemberRemoved = () => {
  success.value = t('web.organizations.members.member_removed');
};

onMounted(async () => {
  // Initialize entitlement definitions for formatting
  await initDefinitions();

  await loadOrganization();
  // Default tab is 'members', so load members and invitations on mount
  await Promise.all([loadMembers(), loadInvitations()]);
});

watch(activeTab, async (newTab) => {
  if (newTab === 'members') {
    // Load members and invitations when switching to members tab
    const promises: Promise<void>[] = [];
    if (!membersStore.isInitialized || membersStore.currentOrgExtid !== orgId.value) {
      promises.push(loadMembers());
    }
    if (invitations.value.length === 0) {
      promises.push(loadInvitations());
    }
    if (promises.length > 0) {
      await Promise.all(promises);
    }
  } else if (newTab === 'billing' && !subscription.value && billingEnabled.value) {
    await loadBilling();
  }
});
</script>

<template>
  <div class="mx-auto max-w-[1400px] px-4 py-8 sm:px-6 lg:px-8">
    <div class="space-y-6">
      <!-- Breadcrumb -->
      <nav class="flex" aria-label="Breadcrumb">
        <ol class="flex items-center space-x-2">
          <li>
            <router-link
              to="/org"
              class="text-sm text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-300">
              {{ t('web.organizations.title') }}
            </router-link>
          </li>
          <li>
            <OIcon
              collection="heroicons"
              name="chevron-right"
              class="size-4 text-gray-400"
              aria-hidden="true" />
          </li>
          <li class="text-sm font-medium text-gray-900 dark:text-white">
            {{ organization?.display_name || t('web.COMMON.loading') }}
          </li>
        </ol>
      </nav>

      <!-- Tabs: Team (primary), Billing (conditional), Settings (infrequent) -->
      <div class="border-b border-gray-200 dark:border-gray-700">
        <nav class="-mb-px flex space-x-8" aria-label="Tabs">
          <!-- Team tab - primary action, shown first -->
          <button
            @click="activeTab = 'members'"
            :class="[
              'whitespace-nowrap border-b-2 px-1 py-4 text-sm font-medium',
              activeTab === 'members'
                ? 'border-brand-500 text-brand-600 dark:border-brand-400 dark:text-brand-400'
                : 'border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700 dark:text-gray-400 dark:hover:border-gray-600 dark:hover:text-gray-300',
            ]">
            {{ t('web.organizations.tabs.members') }}
          </button>
          <!-- Billing tab - only shown for default organization -->
          <button
            v-if="isDefaultOrganization"
            @click="activeTab = 'billing'"
            :class="[
              'whitespace-nowrap border-b-2 px-1 py-4 text-sm font-medium',
              activeTab === 'billing'
                ? 'border-brand-500 text-brand-600 dark:border-brand-400 dark:text-brand-400'
                : 'border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700 dark:text-gray-400 dark:hover:border-gray-600 dark:hover:text-gray-300',
            ]">
            {{ t('web.organizations.tabs.billing') }}
          </button>
          <!-- Settings tab - infrequently changed fields -->
          <button
            @click="activeTab = 'general'"
            :class="[
              'whitespace-nowrap border-b-2 px-1 py-4 text-sm font-medium',
              activeTab === 'general'
                ? 'border-brand-500 text-brand-600 dark:border-brand-400 dark:text-brand-400'
                : 'border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700 dark:text-gray-400 dark:hover:border-gray-600 dark:hover:text-gray-300',
            ]">
            {{ isIdentityPlus ? t('web.organizations.tabs.company_branding') : t('web.organizations.tabs.general') }}
          </button>
        </nav>
      </div>

      <!-- Loading State -->
      <div v-if="isLoading" class="flex items-center justify-center py-12">
        <div class="text-center">
          <OIcon
            collection="heroicons"
            name="arrow-path"
            class="mx-auto size-8 animate-spin text-gray-400"
            aria-hidden="true" />
          <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
            {{ t('web.COMMON.loading') }}
          </p>
        </div>
      </div>

      <!-- Content -->
      <div v-else>
        <!-- General Tab -->
        <section
          v-if="activeTab === 'general'"
          class="rounded-lg border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
          <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
            <h3 class="text-base font-semibold text-gray-900 dark:text-white">
              {{ t('web.organizations.general_settings') }}
            </h3>
          </div>

          <div class="p-6">
            <BasicFormAlerts
              v-if="error"
              :error="error" />
            <BasicFormAlerts
              v-if="success"
              :success="success" />

            <form @submit.prevent="handleSave" class="mt-4 space-y-6">
              <!-- Display Name -->
              <div>
                <label
                  for="display-name"
                  class="block text-sm font-medium text-gray-700 dark:text-gray-300">
                  {{ t('web.organizations.display_name') }}
                  <span class="text-red-500">*</span>
                </label>
                <input
                  id="display-name"
                  v-model="formData.display_name"
                  type="text"
                  required
                  maxlength="100"
                  class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-400 sm:text-sm" />
              </div>

              <!-- Description (hidden for now) -->
              <div v-if="false">
                <label
                  for="description"
                  class="block text-sm font-medium text-gray-700 dark:text-gray-300">
                  {{ t('web.organizations.description') }}
                </label>
                <textarea
                  id="description"
                  v-model="formData.description"
                  rows="3"
                  maxlength="500"
                  class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-400 sm:text-sm"></textarea>
                <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
                  {{ formData.description.length }}/500
                </p>
              </div>

              <!-- Contact Email (only for default organization) -->
              <div v-if="isDefaultOrganization">
                <label
                  for="contact-email"
                  class="block text-sm font-medium text-gray-700 dark:text-gray-300">
                  {{ t('web.organizations.contact_email') }}
                  <span class="text-red-500">*</span>
                </label>
                <input
                  id="contact-email"
                  v-model="formData.contact_email"
                  type="email"
                  readonly
                  disabled
                  class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-400 sm:text-sm" />
                <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
                  {{ t('web.organizations.contact_email_help') }}
                </p>
              </div>

              <!-- Billing info notice for non-default organizations -->
              <div
                v-else
                class="rounded-lg border border-blue-200 bg-blue-50 p-4 dark:border-blue-800 dark:bg-blue-900/20">
                <div class="flex">
                  <OIcon
                    collection="heroicons"
                    name="information-circle"
                    class="size-5 flex-shrink-0 text-blue-400 dark:text-blue-300"
                    aria-hidden="true" />
                  <div class="ml-3">
                    <p class="text-sm text-blue-700 dark:text-blue-300">
                      {{ t('web.organizations.billing_managed_by_default') }}
                    </p>
                  </div>
                </div>
              </div>

              <!-- Action Buttons -->
              <div class="flex items-center justify-end gap-3">
                <button
                  v-if="isDirty"
                  type="button"
                  @click="handleCancel"
                  :disabled="isSaving"
                  class="rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-gray-700 dark:text-gray-100 dark:ring-gray-600 dark:hover:bg-gray-600">
                  {{ t('web.COMMON.word_cancel') }}
                </button>
                <button
                  type="submit"
                  :disabled="!isDirty || isSaving"
                  class="rounded-md bg-brand-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-brand-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-brand-500 dark:hover:bg-brand-400">
                  <span v-if="!isSaving">{{ t('web.COMMON.save_changes') }}</span>
                  <span v-else>{{ t('web.COMMON.saving') }}</span>
                </button>
              </div>
            </form>
          </div>
        </section>

        <!-- Members Tab -->
        <section
          v-if="activeTab === 'members'"
          class="rounded-lg border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
          <!-- Header with Primary CTA -->
          <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
            <div class="flex items-center justify-between">
              <div>
                <h3 class="text-base font-semibold text-gray-900 dark:text-white">
                  {{ t('web.organizations.tabs.members') }}
                </h3>
                <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
                  {{ membersStore.memberCount }} {{ membersStore.memberCount === 1 ? t('web.organizations.members.member_singular') : t('web.organizations.members.member_plural') }}
                </p>
              </div>
              <!-- Primary CTA: Invite Member (if entitled) or Upgrade (if not) -->
              <button
                v-if="canManageMembers"
                type="button"
                @click="showInviteForm = !showInviteForm"
                class="inline-flex items-center rounded-md bg-brand-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-brand-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600 dark:bg-brand-500 dark:hover:bg-brand-400">
                <OIcon
                  collection="heroicons"
                  name="user-plus"
                  class="-ml-0.5 mr-1.5 size-5"
                  aria-hidden="true" />
                {{ t('web.organizations.invitations.invite_member') }}
              </button>
              <router-link
                v-else
                to="/billing/plans"
                class="inline-flex items-center rounded-md bg-brand-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-brand-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600 dark:bg-brand-500 dark:hover:bg-brand-400">
                <OIcon
                  collection="heroicons"
                  name="arrow-up-circle"
                  class="-ml-0.5 mr-1.5 size-5"
                  aria-hidden="true" />
                {{ t('web.billing.overview.upgrade_plan') }}
              </router-link>
            </div>
          </div>

          <div class="p-6">
            <BasicFormAlerts
              v-if="error"
              :error="error" />
            <BasicFormAlerts
              v-if="success"
              :success="success" />

            <!-- Entitlement Upgrade Prompt -->
            <EntitlementUpgradePrompt
              v-if="inviteUpgradeError"
              :error="inviteUpgradeError"
              resource-type="members"
              class="mb-4"
              @close="inviteUpgradeError = null" />

            <!-- Invite Form (inline) -->
            <div
              v-if="showInviteForm && canManageMembers"
              class="mb-6 rounded-lg border border-gray-200 bg-gray-50 p-4 dark:border-gray-700 dark:bg-gray-700/50">
              <form
                @submit.prevent="handleInviteMember"
                class="space-y-4">
                <BasicFormAlerts
                  v-if="inviteGeneralError"
                  :error="inviteGeneralError" />

                <div class="flex flex-col gap-4 sm:flex-row sm:items-end">
                  <div class="flex-1">
                    <label
                      for="invite-email"
                      class="block text-sm font-medium text-gray-700 dark:text-gray-300">
                      {{ t('web.organizations.invitations.email_address') }}
                    </label>
                    <input
                      id="invite-email"
                      v-model="inviteFormData.email"
                      type="email"
                      required
                      :placeholder="t('web.organizations.invitations.email_placeholder')"
                      :class="[
                        'mt-1 block w-full rounded-md shadow-sm sm:text-sm',
                        'focus:border-brand-500 focus:ring-brand-500',
                        'dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-400',
                        inviteErrors.email
                          ? 'border-red-300 text-red-900 placeholder:text-red-300 focus:border-red-500 focus:ring-red-500'
                          : 'border-gray-300 dark:border-gray-600',
                      ]" />
                  </div>
                  <div class="w-full sm:w-32">
                    <label
                      for="invite-role"
                      class="block text-sm font-medium text-gray-700 dark:text-gray-300">
                      {{ t('web.organizations.invitations.role') }}
                    </label>
                    <select
                      id="invite-role"
                      v-model="inviteFormData.role"
                      class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white sm:text-sm">
                      <option value="member">{{ t('web.organizations.invitations.roles.member') }}</option>
                      <option value="admin">{{ t('web.organizations.invitations.roles.admin') }}</option>
                    </select>
                  </div>
                  <div class="flex gap-2">
                    <button
                      type="button"
                      @click="showInviteForm = false"
                      :disabled="isInviting"
                      class="rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-700 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 disabled:opacity-50 dark:bg-gray-700 dark:text-gray-200 dark:ring-gray-600 dark:hover:bg-gray-600">
                      {{ t('web.COMMON.word_cancel') }}
                    </button>
                    <button
                      type="submit"
                      :disabled="isInviting || !inviteFormData.email"
                      class="rounded-md bg-brand-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-brand-500 disabled:opacity-50 dark:bg-brand-500 dark:hover:bg-brand-400">
                      {{ isInviting ? t('web.COMMON.processing') : t('web.organizations.invitations.send_invite') }}
                    </button>
                  </div>
                </div>
              </form>
            </div>

            <!-- Members Table (compact mode) -->
            <div v-if="membersStore.members.length > 0">
              <MembersTable
                :members="membersStore.members"
                :org-extid="orgId"
                :is-loading="membersStore.loading"
                compact
                @member-updated="handleMemberUpdated"
                @member-removed="handleMemberRemoved" />
            </div>

            <!-- Empty state for members -->
            <div v-else-if="!membersStore.loading" class="py-8 text-center">
              <OIcon
                collection="heroicons"
                name="users"
                class="mx-auto size-12 text-gray-400"
                aria-hidden="true" />
              <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
                {{ t('web.organizations.members.no_members') }}
              </p>
            </div>

            <!-- Loading state -->
            <div v-else class="flex items-center justify-center py-8">
              <OIcon
                collection="heroicons"
                name="arrow-path"
                class="size-6 animate-spin text-gray-400"
                aria-hidden="true" />
            </div>

            <!-- Pending Invitations (collapsed subsection) -->
            <div v-if="invitations.length > 0" class="mt-6 border-t border-gray-200 pt-6 dark:border-gray-700">
              <h4 class="text-sm font-medium text-gray-700 dark:text-gray-300">
                {{ t('web.organizations.invitations.pending_invitations') }}
              </h4>
              <div class="mt-3 space-y-2">
                <div
                  v-for="invitation in invitations"
                  :key="invitation.id"
                  class="flex items-center justify-between rounded-md bg-gray-50 px-3 py-2 dark:bg-gray-700/50">
                  <div class="flex items-center gap-3">
                    <span class="text-sm text-gray-900 dark:text-white">{{ invitation.email }}</span>
                    <span class="inline-flex items-center rounded-full bg-yellow-100 px-2 py-0.5 text-xs font-medium text-yellow-800 dark:bg-yellow-900/30 dark:text-yellow-400">
                      {{ t('web.organizations.invitations.status.pending') }}
                    </span>
                  </div>
                  <div v-if="invitation.token" class="flex gap-2">
                    <button
                      type="button"
                      @click="handleResendInvitation(invitation.token!)"
                      class="text-xs text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200">
                      {{ t('web.organizations.invitations.resend') }}
                    </button>
                    <button
                      type="button"
                      @click="handleRevokeInvitation(invitation.token!)"
                      class="text-xs text-red-500 hover:text-red-700 dark:text-red-400 dark:hover:text-red-300">
                      {{ t('web.organizations.invitations.revoke') }}
                    </button>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </section>

        <!-- Billing Tab -->
        <section
          v-if="activeTab === 'billing'"
          class="space-y-6">
          <!-- Billing Disabled Notice -->
          <div v-if="!billingEnabled" class="rounded-lg border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
            <div class="p-6">
              <div class="rounded-lg border-2 border-dashed border-gray-300 p-12 text-center dark:border-gray-600">
                <OIcon
                  collection="heroicons"
                  name="credit-card"
                  class="mx-auto size-12 text-gray-400"
                  aria-hidden="true" />
                <h3 class="mt-2 text-sm font-semibold text-gray-900 dark:text-white">
                  {{ t('web.organizations.billing_coming_soon') }}
                </h3>
                <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
                  {{ t('web.organizations.billing_coming_soon_description') }}
                </p>
              </div>
            </div>
          </div>

          <!-- Billing Enabled -->
          <template v-else>
            <!-- Subscription Overview -->
            <div class="rounded-lg border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
              <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
                <h3 class="text-base font-semibold text-gray-900 dark:text-white">
                  {{ t('web.billing.subscription.status') }}
                </h3>
              </div>

              <div class="p-6">
                <div v-if="isLoadingBilling" class="flex items-center justify-center py-8">
                  <OIcon
                    collection="heroicons"
                    name="arrow-path"
                    class="size-6 animate-spin text-gray-400"
                    aria-hidden="true" />
                </div>

                <div v-else-if="subscription" class="space-y-4">
                  <!-- Plan Info -->
                  <div class="flex items-start justify-between">
                    <div>
                      <p class="text-sm font-medium text-gray-500 dark:text-gray-400">
                        {{ t('web.billing.subscription.catalog_name') }}
                      </p>
                      <p class="mt-1 text-lg font-semibold text-gray-900 dark:text-white">
                        {{ getPlanLabel(subscription.plan_type) }}
                      </p>
                    </div>
                    <span
                      :class="[
                        'inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium',
                        subscription.status === 'active'
                          ? 'bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-400'
                          : 'bg-red-100 text-red-800 dark:bg-red-900/30 dark:text-red-400',
                      ]">
                      {{ getSubscriptionStatusLabel(subscription.status) }}
                    </span>
                  </div>

                  <!-- Team Usage -->
                  <div>
                    <p class="text-sm font-medium text-gray-500 dark:text-gray-400">
                      {{ t('web.billing.subscription.team_usage') }}
                    </p>
                    <p class="mt-1 text-sm text-gray-900 dark:text-white">
                      {{ t('web.billing.subscription.teams_used', { used: subscription.teams_used, limit: subscription.teams_limit }) }}
                    </p>
                    <div class="mt-2 h-2 w-full overflow-hidden rounded-full bg-gray-200 dark:bg-gray-700">
                      <div
                        :class="[
                          'h-full transition-all',
                          subscription.teams_used >= subscription.teams_limit
                            ? 'bg-red-500'
                            : 'bg-brand-500',
                        ]"
                        :style="{ width: `${Math.min((subscription.teams_used / subscription.teams_limit) * 100, 100)}%` }"></div>
                    </div>
                  </div>

                  <!-- Current Entitlements -->
                  <div class="border-t border-gray-200 pt-4 dark:border-gray-700">
                    <p class="mb-3 text-sm font-medium text-gray-500 dark:text-gray-400">
                      {{ t('web.billing.overview.plan_features') }}
                    </p>

                    <!-- Loading skeleton for entitlements -->
                    <div v-if="isLoadingDefinitions" class="grid grid-cols-1 gap-2 sm:grid-cols-2">
                      <div
                        v-for="i in 4"
                        :key="i"
                        class="flex animate-pulse items-center gap-2">
                        <div class="size-5 rounded-full bg-gray-200 dark:bg-gray-700"></div>
                        <div class="h-4 w-32 rounded bg-gray-200 dark:bg-gray-700"></div>
                      </div>
                    </div>

                    <!-- Error state for entitlements -->
                    <div v-else-if="definitionsError" class="text-sm text-amber-600 dark:text-amber-400">
                      {{ t('web.billing.overview.entitlements_load_error') }}
                    </div>

                    <!-- Entitlements list -->
                    <div v-else-if="entitlements.length > 0" class="grid grid-cols-1 gap-2 sm:grid-cols-2">
                      <div
                        v-for="ent in entitlements"
                        :key="ent"
                        class="flex items-center gap-2 text-sm text-gray-700 dark:text-gray-300">
                        <OIcon
                          collection="heroicons"
                          name="check-circle"
                          class="size-5 text-green-500 dark:text-green-400"
                          aria-hidden="true" />
                        {{ formatEntitlement(ent) }}
                      </div>
                    </div>

                    <!-- No entitlements -->
                    <div v-else class="text-sm text-gray-500 dark:text-gray-400">
                      {{ t('web.billing.overview.no_entitlements') }}
                    </div>
                  </div>

                  <!-- Action Buttons -->
                  <div class="flex flex-wrap gap-3 pt-4">
                    <router-link
                      to="/billing/plans"
                      class="inline-flex items-center gap-2 rounded-md bg-brand-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-brand-500 dark:bg-brand-500 dark:hover:bg-brand-400">
                      <OIcon
                        collection="heroicons"
                        name="arrow-up-circle"
                        class="size-4"
                        aria-hidden="true" />
                      {{ t('web.billing.overview.upgrade_plan') }}
                    </router-link>
                    <router-link
                      to="/billing/overview"
                      class="inline-flex items-center gap-2 rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 dark:bg-gray-700 dark:text-gray-100 dark:ring-gray-600 dark:hover:bg-gray-600">
                      <OIcon
                        collection="heroicons"
                        name="cog-6-tooth-solid"
                        class="size-4"
                        aria-hidden="true" />
                      {{ t('web.billing.overview.manage_billing') }}
                    </router-link>
                    <router-link
                      to="/billing/invoices"
                      class="inline-flex items-center gap-2 rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 dark:bg-gray-700 dark:text-gray-100 dark:ring-gray-600 dark:hover:bg-gray-600">
                      <OIcon
                        collection="heroicons"
                        name="document-text"
                        class="size-4"
                        aria-hidden="true" />
                      {{ t('web.billing.overview.view_invoices') }}
                    </router-link>
                  </div>
                </div>

                <!-- No Subscription (Free Plan) -->
                <div v-else class="text-center">
                  <OIcon
                    collection="tabler"
                    name="square-letter-s"
                    class="mx-auto size-12 text-gray-400"
                    aria-hidden="true" />
                  <h3 class="mt-2 text-sm font-semibold text-gray-900 dark:text-white">
                    {{ t('web.billing.plans.free_plan') }}
                  </h3>
                  <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
                    Upgrade to unlock more teams and features
                  </p>
                  <router-link
                    to="/billing/plans"
                    class="mt-4 inline-flex items-center gap-2 rounded-md bg-brand-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-brand-500 dark:bg-brand-500 dark:hover:bg-brand-400">
                    <OIcon
                      collection="heroicons"
                      name="arrow-up-circle"
                      class="size-4"
                      aria-hidden="true" />
                    {{ t('web.billing.overview.upgrade_plan') }}
                  </router-link>
                </div>
              </div>
            </div>
          </template>
        </section>
      </div>
    </div>
  </div>
</template>
