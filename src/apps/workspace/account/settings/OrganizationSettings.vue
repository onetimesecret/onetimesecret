<!-- src/apps/workspace/account/settings/OrganizationSettings.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
import BasicFormAlerts from '@/shared/components/forms/BasicFormAlerts.vue';
import OIcon from '@/shared/components/icons/OIcon.vue';
import BillingLayout from '@/shared/components/layout/BillingLayout.vue';
import { useEntitlements } from '@/shared/composables/useEntitlements';
import { useAsyncHandler } from '@/shared/composables/useAsyncHandler';
import { classifyError } from '@/schemas/errors';
import { BillingService } from '@/services/billing.service';
import { WindowService } from '@/services/window.service';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import type { Subscription } from '@/types/billing';
import { getPlanLabel, getSubscriptionStatusLabel } from '@/types/billing';
import type { CreateInvitationPayload, Organization, OrganizationInvitation } from '@/types/organization';
import { ENTITLEMENTS } from '@/types/organization';
import { computed, onMounted, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { z } from 'zod';

const { t } = useI18n();
const route = useRoute();
const organizationStore = useOrganizationStore();

const orgId = computed(() => route.params.extid as string);
const organization = ref<Organization | null>(null);
const subscription = ref<Subscription | null>(null);
const invitations = ref<OrganizationInvitation[]>([]);
const activeTab = ref<'general' | 'members' | 'billing'>('general');

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
const isInviting = ref(false);

const { wrap } = useAsyncHandler({
  notify: false,
});

const billingEnabled = computed(() => WindowService.get('billing_enabled') ?? false);

// Entitlements
const { entitlements, can } = useEntitlements(organization);

/**
 * Determine if this is a single-user Identity Plus account.
 * Identity Plus has custom domains but not multi-team entitlements.
 */
const isIdentityPlus = computed(() => can(ENTITLEMENTS.CUSTOM_DOMAINS));

// Format entitlement for display
const formatEntitlement = (ent: string): string => {
  const labels: Record<string, string> = {
    [ENTITLEMENTS.CREATE_SECRETS]: 'Create Secrets',
    [ENTITLEMENTS.VIEW_METADATA]: 'View Metadata',
    [ENTITLEMENTS.MANAGE_MEMBERS]: 'Manage Members',
    [ENTITLEMENTS.CUSTOM_DOMAINS]: 'Custom Domains',
    [ENTITLEMENTS.API_ACCESS]: 'API Access',
    [ENTITLEMENTS.PRIORITY_SUPPORT]: 'Priority Support',
    [ENTITLEMENTS.AUDIT_LOGS]: 'Audit Logs',
  };
  return labels[ent] || ent;
};

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
    await organizationStore.updateOrganization(organization.value.id, {
      display_name: formData.value.display_name,
      description: formData.value.description,
      contact_email: formData.value.contact_email,
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
      inviteGeneralError.value = classified.message || t('web.organizations.invitations.invite_error');
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

const formatDate = (timestamp: number): string => new Date(timestamp * 1000).toLocaleDateString(undefined, {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  });

const canManageMembers = computed(() => {
  if (!organization.value) return false;
  return can(ENTITLEMENTS.MANAGE_MEMBERS);
});

onMounted(async () => {
  await loadOrganization();
  if (activeTab.value === 'members') {
    await loadInvitations();
  } else if (activeTab.value === 'billing') {
    await loadBilling();
  }
});

watch(activeTab, async (newTab) => {
  if (newTab === 'members' && invitations.value.length === 0) {
    await loadInvitations();
  } else if (newTab === 'billing' && !subscription.value && billingEnabled.value) {
    await loadBilling();
  }
});
</script>

<template>
  <BillingLayout>
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

      <!-- Tabs -->
      <div class="border-b border-gray-200 dark:border-gray-700">
        <nav class="-mb-px flex space-x-8" aria-label="Tabs">
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
          <!-- Members tab shown when user can manage members -->
          <button
            v-if="canManageMembers"
            @click="activeTab = 'members'"
            :class="[
              'whitespace-nowrap border-b-2 px-1 py-4 text-sm font-medium',
              activeTab === 'members'
                ? 'border-brand-500 text-brand-600 dark:border-brand-400 dark:text-brand-400'
                : 'border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700 dark:text-gray-400 dark:hover:border-gray-600 dark:hover:text-gray-300',
            ]">
            {{ t('web.organizations.tabs.members') }}
          </button>
          <button
            @click="activeTab = 'billing'"
            :class="[
              'whitespace-nowrap border-b-2 px-1 py-4 text-sm font-medium',
              activeTab === 'billing'
                ? 'border-brand-500 text-brand-600 dark:border-brand-400 dark:text-brand-400'
                : 'border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700 dark:text-gray-400 dark:hover:border-gray-600 dark:hover:text-gray-300',
            ]">
            {{ t('web.organizations.tabs.billing') }}
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

              <!-- Description -->
              <div>
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

              <!-- Contact Email -->
              <div>
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
                  required
                  class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-400 sm:text-sm" />
                <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
                  {{ t('web.organizations.contact_email_help') }}
                </p>
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
          <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
            <div class="flex items-center justify-between">
              <h3 class="text-base font-semibold text-gray-900 dark:text-white">
                {{ t('web.organizations.invitations.pending_invitations') }}
              </h3>
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
            </div>
          </div>

          <div class="p-6">
            <BasicFormAlerts
              v-if="error"
              :error="error" />
            <BasicFormAlerts
              v-if="success"
              :success="success" />

            <!-- Invite Form -->
            <div
              v-if="showInviteForm"
              class="mb-6 rounded-lg border border-gray-200 bg-gray-50 p-6 dark:border-gray-700 dark:bg-gray-700/50">
              <h4 class="text-lg font-medium text-gray-900 dark:text-white">
                {{ t('web.organizations.invitations.invite_new_member') }}
              </h4>

              <form
                @submit.prevent="handleInviteMember"
                class="mt-4 space-y-4">
                <BasicFormAlerts
                  v-if="inviteGeneralError"
                  :error="inviteGeneralError" />

                <div class="grid gap-4 sm:grid-cols-2">
                  <div>
                    <label
                      for="invite-email"
                      class="block text-sm font-medium text-gray-700 dark:text-gray-300">
                      {{ t('web.organizations.invitations.email_address') }}
                      <span class="text-red-500">*</span>
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
                    <p
                      v-if="inviteErrors.email"
                      class="mt-1 text-sm text-red-600 dark:text-red-400">
                      {{ inviteErrors.email }}
                    </p>
                  </div>

                  <div>
                    <label
                      for="invite-role"
                      class="block text-sm font-medium text-gray-700 dark:text-gray-300">
                      {{ t('web.organizations.invitations.role') }}
                    </label>
                    <select
                      id="invite-role"
                      v-model="inviteFormData.role"
                      class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white sm:text-sm">
                      <option value="member">
                        {{ t('web.organizations.invitations.roles.member') }}
                      </option>
                      <option value="admin">
                        {{ t('web.organizations.invitations.roles.admin') }}
                      </option>
                    </select>
                  </div>
                </div>

                <div class="flex justify-end gap-3">
                  <button
                    type="button"
                    @click="showInviteForm = false"
                    :disabled="isInviting"
                    class="rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-gray-700 dark:text-gray-100 dark:ring-gray-600 dark:hover:bg-gray-600">
                    {{ t('web.COMMON.word_cancel') }}
                  </button>
                  <button
                    type="submit"
                    :disabled="isInviting || !inviteFormData.email"
                    class="inline-flex items-center rounded-md bg-brand-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-brand-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-brand-500 dark:hover:bg-brand-400">
                    <span v-if="!isInviting">{{ t('web.organizations.invitations.send_invite') }}</span>
                    <span v-else>{{ t('web.COMMON.processing') }}</span>
                  </button>
                </div>
              </form>
            </div>

            <!-- Invitations List -->
            <div v-if="invitations.length > 0" class="space-y-3">
              <div
                v-for="invitation in invitations"
                :key="invitation.id"
                class="flex items-center justify-between rounded-lg border border-gray-200 p-4 dark:border-gray-700">
                <div class="flex-1">
                  <div class="flex items-center gap-3">
                    <p class="font-medium text-gray-900 dark:text-white">
                      {{ invitation.email }}
                    </p>
                    <span
                      :class="[
                        'inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium',
                        invitation.status === 'pending'
                          ? 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900/30 dark:text-yellow-400'
                          : invitation.status === 'accepted'
                          ? 'bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-400'
                          : 'bg-gray-100 text-gray-800 dark:bg-gray-900/30 dark:text-gray-400',
                      ]">
                      {{ t(`web.organizations.invitations.status.${invitation.status}`) }}
                    </span>
                  </div>
                  <div class="mt-1 flex items-center gap-4 text-sm text-gray-500 dark:text-gray-400">
                    <span>{{ t(`web.organizations.invitations.roles.${invitation.role}`) }}</span>
                    <span>{{ t('web.organizations.invitations.invited_at') }}: {{ formatDate(invitation.invited_at) }}</span>
                    <span>{{ t('web.organizations.invitations.expires_at') }}: {{ formatDate(invitation.expires_at) }}</span>
                    <span v-if="invitation.resend_count > 0">
                      {{ invitation.resend_count === 1 ? t('web.organizations.invitations.resent_count', { count: invitation.resend_count }) : t('web.organizations.invitations.resent_count_plural', { count: invitation.resend_count }) }}
                    </span>
                  </div>
                </div>
                <div
                  v-if="invitation.status === 'pending' && invitation.token"
                  class="flex gap-2">
                  <button
                    type="button"
                    @click="handleResendInvitation(invitation.token!)"
                    class="rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 dark:bg-gray-700 dark:text-gray-100 dark:ring-gray-600 dark:hover:bg-gray-600">
                    {{ t('web.organizations.invitations.resend') }}
                  </button>
                  <button
                    type="button"
                    @click="handleRevokeInvitation(invitation.token!)"
                    class="rounded-md bg-red-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-red-500 dark:bg-red-500 dark:hover:bg-red-400">
                    {{ t('web.organizations.invitations.revoke') }}
                  </button>
                </div>
              </div>
            </div>
            <div v-else class="py-12 text-center">
              <OIcon
                collection="heroicons"
                name="envelope"
                class="mx-auto size-12 text-gray-400"
                aria-hidden="true" />
              <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
                {{ t('web.organizations.invitations.no_pending_invitations') }}
              </p>
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
                  <div v-if="entitlements.length > 0" class="border-t border-gray-200 pt-4 dark:border-gray-700">
                    <p class="mb-3 text-sm font-medium text-gray-500 dark:text-gray-400">
                      Your Plan Includes:
                    </p>
                    <div class="grid grid-cols-1 gap-2 sm:grid-cols-2">
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
                  </div>

                  <!-- Action Buttons -->
                  <div class="flex flex-wrap gap-3 pt-4">
                    <router-link
                      to="/account/billing/plans"
                      class="inline-flex items-center gap-2 rounded-md bg-brand-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-brand-500 dark:bg-brand-500 dark:hover:bg-brand-400">
                      <OIcon
                        collection="heroicons"
                        name="arrow-up-circle"
                        class="size-4"
                        aria-hidden="true" />
                      {{ t('web.billing.overview.upgrade_plan') }}
                    </router-link>
                    <router-link
                      to="/account/billing"
                      class="inline-flex items-center gap-2 rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 dark:bg-gray-700 dark:text-gray-100 dark:ring-gray-600 dark:hover:bg-gray-600">
                      <OIcon
                        collection="heroicons"
                        name="cog-6-tooth-solid"
                        class="size-4"
                        aria-hidden="true" />
                      {{ t('web.billing.overview.manage_billing') }}
                    </router-link>
                    <router-link
                      to="/account/billing/invoices"
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
                    to="/account/billing/plans"
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
  </BillingLayout>
</template>
