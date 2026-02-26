<!-- src/apps/workspace/account/settings/OrganizationSettings.vue -->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import BasicFormAlerts from '@/shared/components/forms/BasicFormAlerts.vue';
import OIcon from '@/shared/components/icons/OIcon.vue';
// LAUNCH: Identity-only - MembersTable hidden until team features enabled
// import MembersTable from '@/apps/workspace/components/members/MembersTable.vue';
import DomainsTable from '@/apps/workspace/components/domains/DomainsTable.vue';
import EmptyState from '@/shared/components/ui/EmptyState.vue';
// LAUNCH: Identity-only - EntitlementUpgradePrompt hidden until team features enabled
// import EntitlementUpgradePrompt from '@/apps/workspace/components/billing/EntitlementUpgradePrompt.vue';
import { useEntitlements } from '@/shared/composables/useEntitlements';
// LAUNCH: Identity-only - useAsyncHandler and useEntitlementError hidden until team features enabled
// import { useAsyncHandler } from '@/shared/composables/useAsyncHandler';
// import { useEntitlementError } from '@/shared/composables/useEntitlementError';
import { useDomainsManager } from '@/shared/composables/useDomainsManager';
import { classifyError } from '@/schemas/errors';
// LAUNCH: Identity-only - ApplicationError hidden until team features enabled
// import type { ApplicationError } from '@/schemas/errors';
import { BillingService } from '@/services/billing.service';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import { storeToRefs } from 'pinia';
import { useMembersStore } from '@/shared/stores/membersStore';
import type { Subscription } from '@/types/billing';
import { getPlanLabel, getSubscriptionStatusLabel, isLegacyPlan } from '@/types/billing';
// LAUNCH: Identity-only - CreateInvitationPayload hidden until team features enabled
import type { /* CreateInvitationPayload, */ Organization, OrganizationInvitation } from '@/types/organization';
import { computed, onMounted, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
// LAUNCH: Identity-only - zod hidden until team features enabled (used for invite form validation)
// import { z } from 'zod';

type TabType = 'general' | 'members' | 'domains' | 'subscription';

// URL tab names map to internal tab names
// URL: team -> internal: members
// URL: settings -> internal: general
// URL: subscription -> internal: subscription (renamed from billing for clarity)
const URL_TO_TAB: Record<string, TabType> = {
  team: 'members',
  domains: 'domains',
  subscription: 'subscription',
  billing: 'subscription', // backwards compatibility for old URLs
  settings: 'general',
};

const TAB_TO_URL: Record<TabType, string> = {
  members: 'team',
  domains: 'domains',
  subscription: 'subscription',
  general: 'settings',
};

const props = withDefaults(defineProps<{
  initialTab?: TabType;
}>(), {
  // LAUNCH: Identity-only - default to domains instead of members (team)
  initialTab: 'domains',
});

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const organizationStore = useOrganizationStore();
const membersStore = useMembersStore();

const orgId = computed(() => route.params.extid as string);

// Resolve initial tab from route param or prop
const resolveInitialTab = (): TabType => {
  const urlTab = route.params.tab as string | undefined;
  if (urlTab && URL_TO_TAB[urlTab]) {
    return URL_TO_TAB[urlTab];
  }
  return props.initialTab;
};
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
const activeTab = ref<TabType>(resolveInitialTab());

// Update URL when tab changes (without adding history entries)
const setActiveTab = (tab: TabType) => {
  activeTab.value = tab;
  const urlTab = TAB_TO_URL[tab];
  router.replace({ params: { ...route.params, tab: urlTab } });
};

// Watch for route param changes (e.g., back/forward navigation)
watch(
  () => route.params.tab,
  (newTab) => {
    const urlTab = newTab as string | undefined;
    if (urlTab && URL_TO_TAB[urlTab]) {
      activeTab.value = URL_TO_TAB[urlTab];
    } else if (!urlTab) {
      // LAUNCH: Identity-only - default to domains instead of members (team)
      activeTab.value = 'domains';
    }
  }
);

// Domains management
const {
  isLoading: isLoadingDomains,
  records: domainRecords,
  recordCount: domainCount,
  error: domainsError,
  refreshRecords: refreshDomains,
} = useDomainsManager();

const isLoading = ref(false);
const isSaving = ref(false);
const isLoadingBilling = ref(false);
// Billing email editing has been moved to BillingOverview.vue
const error = ref('');
const success = ref('');

// Plan data from billing overview
const planName = ref<string>('');
const planFeatures = ref<string[]>([]);

// LAUNCH: Identity-only - Invitation form state hidden until team features enabled
/*
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
*/

const bootstrapStore = useBootstrapStore();
const { billing_enabled } = storeToRefs(bootstrapStore);
const billingEnabled = computed(() => billing_enabled.value ?? false);

// Entitlements - formatEntitlement uses API-driven i18n keys
// LAUNCH: Identity-only - can and ENTITLEMENTS hidden until team features enabled
const {
  entitlements,
  // can,
  formatEntitlement,
  initDefinitions,
  // ENTITLEMENTS,
} = useEntitlements(organization);


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

// Billing email is only shown for paid plans (organizations with a planid set)
const hasPaidPlan = computed(() => !!organization.value?.planid);

// Legacy plan detection for grandfathered Early Supporter customers
const isLegacyCustomer = computed(() =>
  organization.value?.planid ? isLegacyPlan(organization.value.planid) : false
);

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
          teams_used: overview.usage.domains || 0,
          members_per_team_limit: overview.plan.limits.members_per_team || 0,
          billing_interval: overview.plan.interval as any,
          current_period_start: new Date(overview.subscription.period_end * 1000), // Placeholder
          current_period_end: new Date(overview.subscription.period_end * 1000),
          cancel_at_period_end: overview.subscription.canceled,
          created_at: new Date(),
          updated_at: new Date(),
        };
        // Store plan name and features for display
        planName.value = overview.plan.name || '';
        planFeatures.value = overview.plan.features || [];
      } else {
        subscription.value = null;
        planName.value = '';
        planFeatures.value = [];
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

// LAUNCH: Identity-only - Team member management functions hidden until team features enabled
/*
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

const formatDate = (timestamp: number): string => new Date(timestamp * 1000).toLocaleDateString(undefined, {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  });

const formatTimeRemaining = (expiresAt: number): string => {
  const now = Math.floor(Date.now() / 1000);
  const remaining = expiresAt - now;

  if (remaining <= 0) {
    return t('web.organizations.invitations.status.expired');
  }

  const days = Math.floor(remaining / 86400);
  const hours = Math.floor((remaining % 86400) / 3600);

  if (days > 0) {
    return t('web.organizations.invitations.expires_in_days', { days });
  } else if (hours > 0) {
    return t('web.organizations.invitations.expires_in_hours', { hours });
  } else {
    return t('web.organizations.invitations.expires_soon');
  }
};

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
*/

onMounted(async () => {
  // Initialize entitlement definitions for formatting
  await initDefinitions();

  await loadOrganization();

  // Load data for the initial tab
  if (activeTab.value === 'members') {
    await Promise.all([loadMembers(), loadInvitations()]);
  } else if (activeTab.value === 'domains') {
    await refreshDomains();
  } else if (activeTab.value === 'subscription' && billingEnabled.value) {
    await loadBilling();
  }
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
  } else if (newTab === 'domains') {
    // Load domains when switching to domains tab
    await refreshDomains();
  } else if (newTab === 'subscription' && !subscription.value && billingEnabled.value) {
    await loadBilling();
  }
});

// Watch for org changes via URL navigation (e.g., /org/A/domains -> /org/B/domains)
// Vue Router reuses the component, so onMounted doesn't run again.
// This ensures currentOrganization in the store is updated to match the URL.
watch(orgId, async (newOrgId, oldOrgId) => {
  if (newOrgId && newOrgId !== oldOrgId) {
    await loadOrganization();
    // Reload tab-specific data for the new org
    if (activeTab.value === 'members') {
      await Promise.all([loadMembers(), loadInvitations()]);
    } else if (activeTab.value === 'domains') {
      await refreshDomains();
    } else if (activeTab.value === 'subscription' && billingEnabled.value) {
      await loadBilling();
    }
  }
});
</script>

<template>
  <div class="mx-auto max-w-[1400px] px-4 py-8 sm:px-6 lg:px-8">
    <div class="space-y-6">
      <!-- Page Header -->
      <div class="flex items-center justify-between">
        <div class="flex items-center gap-3">
          <router-link
            to="/orgs"
            class="flex items-center gap-2 text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200"
            :title="t('web.organizations.title')">
            <OIcon
              collection="heroicons"
              name="arrow-left"
              class="size-5"
              aria-hidden="true" />
            <h1 class="m-0 text-xl font-brand font-semibold text-gray-900 dark:text-white">
              {{ organization?.display_name || t('web.COMMON.loading') }}
            </h1>
          </router-link>
        </div>
      </div>

      <!-- Tabs: Domains, Billing (conditional), Settings (infrequent) -->
      <!-- LAUNCH: Identity-only - Team tab hidden until team features enabled -->
      <div class="border-b border-gray-200 dark:border-gray-700">
        <nav class="-mb-px flex space-x-8" aria-label="Tabs">
          <!-- LAUNCH: Team tab hidden - uncomment when team features enabled
          <button
            @click="setActiveTab('members')"
            :class="[
              'whitespace-nowrap border-b-2 px-1 py-4 text-sm font-medium',
              activeTab === 'members'
                ? 'border-brand-500 text-brand-600 dark:border-brand-400 dark:text-brand-400'
                : 'border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700 dark:text-gray-400 dark:hover:border-gray-600 dark:hover:text-gray-300',
            ]">
            {{ t('web.organizations.tabs.members') }}
          </button>
          -->
          <!-- Domains tab -->
          <button
            data-testid="org-tab-domains"
            @click="setActiveTab('domains')"
            :class="[
              'whitespace-nowrap border-b-2 px-1 py-4 text-sm font-medium',
              activeTab === 'domains'
                ? 'border-brand-500 text-brand-600 dark:border-brand-400 dark:text-brand-400'
                : 'border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700 dark:text-gray-400 dark:hover:border-gray-600 dark:hover:text-gray-300',
            ]">
            {{ t('web.organizations.tabs.domains') }}
          </button>
          <!-- Subscription tab - shown for all organizations -->
          <button
            data-testid="org-tab-subscription"
            @click="setActiveTab('subscription')"
            :class="[
              'whitespace-nowrap border-b-2 px-1 py-4 text-sm font-medium',
              activeTab === 'subscription'
                ? 'border-brand-500 text-brand-600 dark:border-brand-400 dark:text-brand-400'
                : 'border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700 dark:text-gray-400 dark:hover:border-gray-600 dark:hover:text-gray-300',
            ]">
            {{ t('web.organizations.tabs.subscription') }}
          </button>
          <!-- Settings tab - infrequently changed fields -->
          <button
            data-testid="org-tab-settings"
            @click="setActiveTab('general')"
            :class="[
              'whitespace-nowrap border-b-2 px-1 py-4 text-sm font-medium',
              activeTab === 'general'
                ? 'border-brand-500 text-brand-600 dark:border-brand-400 dark:text-brand-400'
                : 'border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700 dark:text-gray-400 dark:hover:border-gray-600 dark:hover:text-gray-300',
            ]">
            {{ t('web.organizations.tabs.general')  }}
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
          data-testid="org-section-settings"
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

              <!-- Billing Email - read-only display for paid plans, editable on Billing Overview -->
              <div v-if="hasPaidPlan" data-testid="org-billing-email-field">
                <label class="block text-sm font-medium text-gray-700 dark:text-gray-300">
                  {{ t('web.organizations.contact_email') }}
                </label>
                <div class="mt-1 flex items-center gap-3">
                  <span class="text-sm text-gray-900 dark:text-white">
                    {{ organization?.contact_email || t('web.COMMON.not_set') }}
                  </span>
                  <router-link
                    :to="`/billing/${orgId}/overview`"
                    data-testid="org-billing-email-edit-link"
                    class="text-sm font-medium text-brand-600 hover:text-brand-500 dark:text-brand-400 dark:hover:text-brand-300">
                    {{ t('web.COMMON.word_edit') }}
                  </router-link>
                </div>
                <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
                  {{ t('web.organizations.billing_email_managed_on_billing') }}
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
                  class="rounded-md bg-brand-600 px-3 py-2 font-brand text-sm font-semibold text-white shadow-sm hover:bg-brand-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-brand-500 dark:hover:bg-brand-400">
                  <span v-if="!isSaving">{{ t('web.COMMON.save_changes') }}</span>
                  <span v-else>{{ t('web.COMMON.saving') }}</span>
                </button>
              </div>
            </form>
          </div>
        </section>

        <!-- LAUNCH: Identity-only - Members Tab hidden until team features enabled -->
        <!--
        <section
          v-if="activeTab === 'members'"
          class="rounded-lg border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
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
              <button
                type="button"
                @click="canManageMembers && (showInviteForm = !showInviteForm)"
                :disabled="!canManageMembers"
                :title="!canManageMembers ? t('web.organizations.invitations.upgrade_to_invite') : undefined"
                :class="[
                  'inline-flex items-center rounded-md px-3 py-2 text-sm font-semibold shadow-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2',
                  canManageMembers
                    ? 'bg-brand-600 text-white hover:bg-brand-500 focus-visible:outline-brand-600 dark:bg-brand-500 dark:hover:bg-brand-400'
                    : 'cursor-not-allowed bg-gray-300 text-gray-500 dark:bg-gray-600 dark:text-gray-400',
                ]">
                <OIcon
                  collection="heroicons"
                  name="user-plus"
                  class="-ml-0.5 mr-1.5 size-5"
                  aria-hidden="true" />
                {{ t('web.organizations.invitations.invite_member') }}
              </button>
            </div>
            <div
              v-if="!canManageMembers"
              class="mt-4 flex items-center gap-3 rounded-md bg-amber-50 px-4 py-3 dark:bg-amber-900/20">
              <OIcon
                collection="heroicons"
                name="information-circle"
                class="size-5 flex-shrink-0 text-amber-500 dark:text-amber-400"
                aria-hidden="true" />
              <p class="flex-1 text-sm text-amber-700 dark:text-amber-300">
                {{ t('web.organizations.invitations.upgrade_prompt') }}
              </p>
              <router-link
                :to="`/billing/${orgId}/plans`"
                class="inline-flex items-center gap-1 text-sm font-medium text-amber-700 hover:text-amber-800 dark:text-amber-300 dark:hover:text-amber-200">
                {{ t('web.billing.overview.view_plans_action') }}
                <OIcon
                  collection="heroicons"
                  name="arrow-right"
                  class="size-4"
                  aria-hidden="true" />
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

            <EntitlementUpgradePrompt
              v-if="inviteUpgradeError"
              :error="inviteUpgradeError"
              resource-type="members"
              class="mb-4"
              @close="inviteUpgradeError = null" />

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
                      class="rounded-md bg-brand-600 px-3 py-2 font-brand text-sm font-semibold text-white shadow-sm hover:bg-brand-500 disabled:opacity-50 dark:bg-brand-500 dark:hover:bg-brand-400">
                      {{ isInviting ? t('web.COMMON.processing') : t('web.organizations.invitations.send_invite') }}
                    </button>
                  </div>
                </div>
              </form>
            </div>

            <div v-if="membersStore.members.length > 0">
              <MembersTable
                :members="membersStore.members"
                :org-extid="orgId"
                :is-loading="membersStore.loading"
                compact
                @member-updated="handleMemberUpdated"
                @member-removed="handleMemberRemoved" />
            </div>

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

            <div v-else class="flex items-center justify-center py-8">
              <OIcon
                collection="heroicons"
                name="arrow-path"
                class="size-6 animate-spin text-gray-400"
                aria-hidden="true" />
            </div>

            <div v-if="invitations.length > 0" class="mt-6 border-t border-gray-200 pt-6 dark:border-gray-700">
              <h4 class="text-sm font-medium text-gray-700 dark:text-gray-300">
                {{ t('web.organizations.invitations.pending_invitations') }}
              </h4>
              <div class="mt-3 space-y-2">
                <div
                  v-for="invitation in invitations"
                  :key="invitation.id"
                  class="flex items-center justify-between rounded-md bg-gray-50 px-4 py-3 dark:bg-gray-700/50">
                  <div class="flex flex-col gap-1 sm:flex-row sm:items-center sm:gap-3">
                    <span class="text-sm font-medium text-gray-900 dark:text-white">{{ invitation.email }}</span>
                    <div class="flex items-center gap-2">
                      <span class="inline-flex items-center rounded-full bg-yellow-100 px-2 py-0.5 text-xs font-medium text-yellow-800 dark:bg-yellow-900/30 dark:text-yellow-400">
                        {{ t('web.organizations.invitations.status.pending') }}
                      </span>
                      <span class="text-xs text-gray-500 dark:text-gray-400">
                        {{ t('web.organizations.invitations.invited_at') }} {{ formatDate(invitation.invited_at) }}
                      </span>
                      <span class="text-xs text-gray-500 dark:text-gray-400">·</span>
                      <span class="text-xs text-gray-500 dark:text-gray-400">
                        {{ formatTimeRemaining(invitation.expires_at) }}
                      </span>
                    </div>
                  </div>
                  <div v-if="invitation.token" class="flex gap-2">
                    <button
                      type="button"
                      @click="handleResendInvitation(invitation.token!)"
                      class="cursor-pointer rounded px-2 py-1 text-xs font-medium text-gray-600 transition-colors hover:bg-gray-200 hover:text-gray-900 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-1 dark:text-gray-400 dark:hover:bg-gray-600 dark:hover:text-gray-100 dark:focus:ring-offset-gray-800">
                      {{ t('web.organizations.invitations.resend') }}
                    </button>
                    <button
                      type="button"
                      @click="handleRevokeInvitation(invitation.token!)"
                      class="cursor-pointer rounded px-2 py-1 text-xs font-medium text-red-600 transition-colors hover:bg-red-100 hover:text-red-800 focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-offset-1 dark:text-red-400 dark:hover:bg-red-900/30 dark:hover:text-red-300 dark:focus:ring-offset-gray-800">
                      {{ t('web.organizations.invitations.revoke') }}
                    </button>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </section>
        -->
        <!-- End LAUNCH: Identity-only - Members Tab -->

        <!-- Domains Tab -->
        <section
          v-if="activeTab === 'domains'"
          data-testid="org-section-domains"
          class="rounded-lg border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
          <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
            <div class="flex items-center justify-between">
              <div>
                <h3 class="text-base font-semibold text-gray-900 dark:text-white">
                  {{ t('web.domains.domains') }}
                </h3>
                <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
                  {{ t('web.domains.manage_and_configure_your_verified_custom_domains') }}
                </p>
              </div>
              <router-link
                :to="`/org/${orgId}/domains/add`"
                class="inline-flex items-center gap-2 rounded-md bg-brand-600 px-3 py-2 font-brand text-sm font-semibold text-white shadow-sm hover:bg-brand-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600 dark:bg-brand-500 dark:hover:bg-brand-400">
                <OIcon
                  collection="heroicons"
                  name="plus"
                  class="size-4"
                  aria-hidden="true" />
                {{ t('web.domains.add_domain') }}
              </router-link>
            </div>
          </div>

          <div class="p-6">
            <!-- Loading State -->
            <div v-if="isLoadingDomains" class="flex items-center justify-center py-8">
              <OIcon
                collection="heroicons"
                name="arrow-path"
                class="size-6 animate-spin text-gray-400"
                aria-hidden="true" />
            </div>

            <!-- Error State -->
            <BasicFormAlerts
              v-else-if="domainsError"
              :error="domainsError.message" />

            <!-- Domains Table -->
            <DomainsTable
              v-else-if="domainCount > 0 && domainRecords"
              :domains="domainRecords"
              :is-loading="isLoadingDomains"
              :orgid="orgId"
              compact />

            <!-- Empty State -->
            <EmptyState
              v-else
              :showAction="true"
              :action-route="`/org/${orgId}/domains/add`"
              :action-text="t('web.domains.add_domain')">
              <template #title>
                {{ t('web.domains.no_domains_found') }}
              </template>
              <template #description>
                {{ t('web.domains.get_started_by_adding_a_custom_domain') }}
              </template>
            </EmptyState>
          </div>
        </section>

        <!-- Subscription Tab -->
        <section
          v-if="activeTab === 'subscription'"
          data-testid="org-section-subscription"
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
                        {{ planName || getPlanLabel(subscription.plan_type) }}
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

                  <!-- Team Usage - only shown for plans with team features -->
                  <div v-if="subscription.teams_limit > 0">
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

                  <!-- Plan Features -->
                  <div class="border-t border-gray-200 pt-4 dark:border-gray-700">
                    <p class="mb-3 text-sm font-medium text-gray-500 dark:text-gray-400">
                      {{ t('web.billing.overview.plan_features') }}
                    </p>

                    <!-- Features from billing overview (i18n locale keys) -->
                    <div v-if="planFeatures.length > 0" class="grid grid-cols-1 gap-2 sm:grid-cols-2">
                      <div
                        v-for="feature in planFeatures"
                        :key="feature"
                        class="flex items-center gap-2 text-sm text-gray-700 dark:text-gray-300">
                        <OIcon
                          collection="heroicons"
                          name="check-circle"
                          class="size-5 text-green-500 dark:text-green-400"
                          aria-hidden="true" />
                        {{ t(feature) }}
                      </div>
                    </div>

                    <!-- Fallback to org entitlements if no plan features -->
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

                    <!-- Loading skeleton -->
                    <div v-else-if="isLoadingBilling" class="grid grid-cols-1 gap-2 sm:grid-cols-2">
                      <div
                        v-for="i in 4"
                        :key="i"
                        class="flex animate-pulse items-center gap-2">
                        <div class="size-5 rounded-full bg-gray-200 dark:bg-gray-700"></div>
                        <div class="h-4 w-32 rounded bg-gray-200 dark:bg-gray-700"></div>
                      </div>
                    </div>

                    <!-- No features available -->
                    <div v-else class="text-sm text-gray-500 dark:text-gray-400">
                      {{ t('web.billing.overview.no_entitlements') }}
                    </div>
                  </div>

                  <!-- Action Buttons -->
                  <div class="flex flex-wrap gap-3 pt-4">
                    <!-- Hide upgrade button for legacy customers - they're already valued supporters -->
                    <router-link
                      v-if="!isLegacyCustomer"
                      :to="`/billing/${orgId}/plans`"
                      class="inline-flex items-center gap-2 rounded-md bg-brand-600 px-3 py-2 font-brand text-sm font-semibold text-white shadow-sm hover:bg-brand-500 dark:bg-brand-500 dark:hover:bg-brand-400">
                      <OIcon
                        collection="heroicons"
                        name="arrow-up-circle"
                        class="size-4"
                        aria-hidden="true" />
                      {{ t('web.billing.overview.change_plan') }}
                    </router-link>
                    <router-link
                      :to="`/billing/${orgId}/overview`"
                      class="inline-flex items-center gap-2 rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 dark:bg-gray-700 dark:text-gray-100 dark:ring-gray-600 dark:hover:bg-gray-600">
                      <OIcon
                        collection="heroicons"
                        name="cog-6-tooth-solid"
                        class="size-4"
                        aria-hidden="true" />
                      {{ t('web.billing.overview.manage_billing') }}
                    </router-link>
                    <router-link
                      :to="`/billing/${orgId}/invoices`"
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

                <!-- Legacy Plan (Early Supporter) - no modern subscription record but has planid -->
                <div v-else-if="isLegacyCustomer" class="space-y-4">
                  <div class="flex items-start justify-between">
                    <div>
                      <p class="text-sm font-medium text-gray-500 dark:text-gray-400">
                        {{ t('web.billing.subscription.catalog_name') }}
                      </p>
                      <p class="mt-1 text-lg font-semibold text-gray-900 dark:text-white">
                        {{ t('web.billing.plans.early_supporter_plan') }}
                      </p>
                    </div>
                    <span class="inline-flex items-center rounded-full bg-amber-100 px-2.5 py-0.5 text-xs font-medium text-amber-800 dark:bg-amber-900/30 dark:text-amber-400">
                      {{ t('web.organizations.early_supporter_badge') }}
                    </span>
                  </div>
                  <p class="text-sm text-gray-500 dark:text-gray-400">
                    {{ t('web.billing.plans.legacy_plan_info') }}
                  </p>
                  <div class="flex flex-wrap gap-3 pt-4">
                    <router-link
                      :to="`/billing/${orgId}/overview`"
                      class="inline-flex items-center gap-2 rounded-md bg-brand-600 px-3 py-2 font-brand text-sm font-semibold text-white shadow-sm hover:bg-brand-500 dark:bg-brand-500 dark:hover:bg-brand-400">
                      <OIcon
                        collection="heroicons"
                        name="cog-6-tooth"
                        class="size-4"
                        aria-hidden="true" />
                      {{ t('web.billing.overview.manage_subscription') }}
                    </router-link>
                    <router-link
                      :to="`/billing/${orgId}/invoices`"
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
                    {{ t('web.COMMON.upgrade_description') }}
                  </p>
                  <router-link
                    :to="`/billing/${orgId}/plans`"
                    class="mt-4 inline-flex items-center gap-2 rounded-md bg-brand-600 px-3 py-2 font-brand text-sm font-semibold text-white shadow-sm hover:bg-brand-500 dark:bg-brand-500 dark:hover:bg-brand-400">
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
