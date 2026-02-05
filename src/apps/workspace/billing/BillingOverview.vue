<!-- src/apps/workspace/billing/BillingOverview.vue -->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import BasicFormAlerts from '@/shared/components/forms/BasicFormAlerts.vue';
import OIcon from '@/shared/components/icons/OIcon.vue';
import BillingLayout from '@/shared/components/layout/BillingLayout.vue';
import FederationNotification from './FederationNotification.vue';
import { useEntitlements } from '@/shared/composables/useEntitlements';
import { classifyError } from '@/schemas/errors';
import { BillingService, type FederationNotification as FederationNotificationData } from '@/services/billing.service';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import type { PaymentMethod } from '@/types/billing';
import { getPlanDisplayName, isLegacyPlan } from '@/types/billing';
import type { Organization } from '@/types/organization';
import { computed, onMounted, ref, watch } from 'vue';

const { t } = useI18n();
const route = useRoute();
const organizationStore = useOrganizationStore();

// Org extid comes from URL (e.g., /billing/:extid/overview)
const orgExtid = computed(() => route.params.extid as string);

const selectedOrg = ref<Organization | null>(null);
const paymentMethod = ref<PaymentMethod | null>(null);
const nextBillingDate = ref<Date | null>(null);
const planFeatures = ref<string[]>([]);
const federationNotification = ref<FederationNotificationData | null>(null);
const isLoading = ref(false);
const error = ref('');
const success = ref('');

// Billing email editing state
const isSavingBillingEmail = ref(false);
const isEditingBillingEmail = ref(false);
const billingEmailForm = ref({
  email: '',
});

// Check for upgrade success from checkout redirect
const showUpgradeSuccess = computed(() => route.query.upgraded === 'true');
const successMessage = computed(() =>
  showUpgradeSuccess.value ? t('web.billing.overview.upgrade_success') : '',
);

const organizations = computed(() => organizationStore.organizations);

const {
  entitlements,
  formatEntitlement,
  initDefinitions,
} = useEntitlements(selectedOrg);

const planName = computed(() => {
  if (!selectedOrg.value?.planid) return t('web.billing.plans.free_plan');
  return getPlanDisplayName(selectedOrg.value.planid);
});

const planStatus = computed(() => selectedOrg.value?.planid ? 'active' : 'free');

// Billing email is only editable for paid plans
const hasPaidPlan = computed(() => planStatus.value === 'active');

// Legacy plan detection for grandfathered customers
const isLegacyCustomer = computed(() =>
  selectedOrg.value?.planid ? isLegacyPlan(selectedOrg.value.planid) : false
);

// Extract billing overview state updates to reduce complexity
const applyBillingOverview = (overview: Awaited<ReturnType<typeof BillingService.getOverview>>) => {
  nextBillingDate.value = overview.subscription?.period_end
    ? new Date(overview.subscription.period_end * 1000)
    : null;
  planFeatures.value = overview.plan?.features || [];
  paymentMethod.value = overview.payment_method || null;
  federationNotification.value = overview.federation_notification || null;
};

const loadOrganizationData = async (extid: string) => {
  isLoading.value = true;
  error.value = '';
  try {
    const org = await organizationStore.fetchOrganization(extid);
    selectedOrg.value = org;

    // Fetch entitlements if not already loaded
    if ((!org.entitlements || org.entitlements.length === 0) && org.extid) {
      await organizationStore.fetchEntitlements(org.extid);
      // Re-fetch org from store since fetchEntitlements updates it there
      const updatedOrg = organizations.value.find((o) => o.extid === org.extid);
      if (updatedOrg) {
        selectedOrg.value = updatedOrg;
      }
    }

    // Load billing overview data from API
    if (org.extid) {
      const overview = await BillingService.getOverview(org.extid);
      applyBillingOverview(overview);
    }
  } catch (err) {
    const classified = classifyError(err);
    error.value = classified.message || 'Failed to load billing information';
    console.error('[BillingOverview] Error loading organization:', err);
  } finally {
    isLoading.value = false;
  }
};

const _formatCardBrand = (brand: string): string => brand.charAt(0).toUpperCase() + brand.slice(1);

const formatNextBillingDate = (date: Date): string => new Intl.DateTimeFormat('en-US', {
    month: 'long',
    day: 'numeric',
    year: 'numeric',
  }).format(date);

const daysUntilBilling = computed(() => {
  if (!nextBillingDate.value) return null;
  const diff = nextBillingDate.value.getTime() - Date.now();
  return Math.ceil(diff / (1000 * 60 * 60 * 24));
});

// Billing email inline edit handlers
const handleEditBillingEmail = () => {
  billingEmailForm.value.email = selectedOrg.value?.billing_email
    || selectedOrg.value?.contact_email
    || '';
  isEditingBillingEmail.value = true;
};

const handleCancelBillingEmailEdit = () => {
  billingEmailForm.value.email = selectedOrg.value?.billing_email
    || selectedOrg.value?.contact_email
    || '';
  isEditingBillingEmail.value = false;
};

const handleSaveBillingEmail = async () => {
  if (!selectedOrg.value) return;

  const newEmail = billingEmailForm.value.email.trim();
  const currentEmail = selectedOrg.value.billing_email || selectedOrg.value.contact_email || '';
  if (newEmail === currentEmail) {
    isEditingBillingEmail.value = false;
    return;
  }

  isSavingBillingEmail.value = true;
  error.value = '';
  success.value = '';

  try {
    await organizationStore.updateOrganization(orgExtid.value, {
      billing_email: newEmail,
    });

    success.value = t('web.organizations.billing_email_updated');
    isEditingBillingEmail.value = false;
    // Reload organization data to get the updated email
    await loadOrganizationData(orgExtid.value);
  } catch (err) {
    const classified = classifyError(err);
    error.value = classified.message || t('web.organizations.update_error');
    console.error('[BillingOverview] Error updating billing email:', err);
  } finally {
    isSavingBillingEmail.value = false;
  }
};

// Watch for org changes to update billing email form
watch(selectedOrg, (org) => {
  if (org) {
    billingEmailForm.value.email = org.billing_email || org.contact_email || '';
  }
});

// Handle federation notification dismissal
const handleFederationNotificationDismissed = () => {
  federationNotification.value = null;
};

onMounted(async () => {
  try {
    // Initialize entitlement definitions for formatting
    await initDefinitions();

    // Load organization data using extid from URL
    if (orgExtid.value) {
      await loadOrganizationData(orgExtid.value);
    }
  } catch (err) {
    const classified = classifyError(err);
    error.value = classified.message || 'Failed to load billing information';
    console.error('[BillingOverview] Error loading billing data:', err);
  }
});
</script>

<template>
  <BillingLayout>
    <div class="space-y-6">
      <!-- Upgrade Success Banner -->
      <div
        v-if="showUpgradeSuccess"
        class="rounded-lg border border-green-200 bg-green-50 p-4 dark:border-green-800 dark:bg-green-900/20">
        <div class="flex items-center gap-3">
          <OIcon
            collection="heroicons"
            name="check-circle"
            class="size-6 text-green-500 dark:text-green-400"
            aria-hidden="true" />
          <div>
            <p class="font-medium text-green-800 dark:text-green-300">
              {{ successMessage }}
            </p>
            <p class="mt-1 text-sm text-green-700 dark:text-green-400">
              {{ t('web.billing.overview.upgrade_success_description') }}
            </p>
          </div>
        </div>
      </div>

      <!-- Federation Notification (cross-region subscription sync) -->
      <FederationNotification
        v-if="federationNotification?.show"
        :org-extid="orgExtid"
        :notification="federationNotification"
        @dismissed="handleFederationNotificationDismissed" />

      <!-- Error Alert -->
      <BasicFormAlerts v-if="error" :error="error" />

      <!-- Success Alert -->
      <BasicFormAlerts v-if="success" :success="success" />

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

      <!-- Empty State: No Organizations -->
      <div v-else-if="organizations.length === 0" class="rounded-lg border border-gray-200 bg-white p-12 text-center dark:border-gray-700 dark:bg-gray-800">
        <OIcon
          collection="heroicons"
          name="building-office-2"
          class="mx-auto size-12 text-gray-400"
          aria-hidden="true" />
        <h3 class="mt-4 text-lg font-semibold text-gray-900 dark:text-white">
          {{ t('web.billing.overview.no_organizations_title') }}
        </h3>
        <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.billing.overview.no_organizations_description') }}
        </p>
        <div class="mt-6">
          <router-link
            :to="{ name: 'Organizations' }"
            class="inline-flex items-center gap-2 rounded-md bg-brand-600 px-4 py-2 font-brand text-sm font-semibold text-white shadow-sm hover:bg-brand-500 dark:bg-brand-500 dark:hover:bg-brand-400">
            <OIcon
              collection="heroicons"
              name="plus"
              class="size-4"
              aria-hidden="true" />
            {{ t('web.organizations.create_organization') }}
          </router-link>
        </div>
      </div>

      <!-- Content -->
      <div v-else-if="selectedOrg" class="space-y-6">
        <!-- Current Plan Card -->
        <div class="rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-700 dark:bg-gray-800">
          <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
            <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
              {{ t('web.billing.overview.current_plan') }}
            </h2>
          </div>
          <div class="p-6">
            <div class="flex items-start justify-between">
              <div>
                <p class="text-2xl font-bold text-gray-900 dark:text-white">
                  {{ planName }}
                </p>
                <span
                  :class="[
                    'mt-2 inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium',
                    planStatus === 'active'
                      ? 'bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-400'
                      : 'bg-gray-100 text-gray-800 dark:bg-gray-900/30 dark:text-gray-400',
                  ]">
                  {{ planStatus === 'active' ? t('web.billing.subscription.active') : t('web.billing.plans.free_plan') }}
                </span>
                <!-- Next Billing Date -->
                <p
                  v-if="nextBillingDate"
                  class="mt-2 text-sm text-gray-600 dark:text-gray-400"
                  data-testid="next-billing-date">
                  {{ t('web.billing.overview.next_billing_date') }}:
                  {{ formatNextBillingDate(nextBillingDate) }}
                  <span v-if="daysUntilBilling" class="text-gray-500 dark:text-gray-500">
                    ({{ daysUntilBilling }} {{ t('web.billing.overview.days_remaining') }})
                  </span>
                </p>
              </div>
              <router-link
                :to="{ name: 'Billing Plans', params: { extid: orgExtid } }"
                class="inline-flex items-center gap-2 rounded-md bg-brand-600 px-3 py-2 font-brand text-sm font-semibold text-white shadow-sm hover:bg-brand-500 dark:bg-brand-500 dark:hover:bg-brand-400">
                <OIcon
                  collection="heroicons"
                  :name="isLegacyCustomer ? 'cog-6-tooth' : 'arrow-up-circle'"
                  class="size-4"
                  aria-hidden="true" />
                {{ planStatus === 'free' ? t('web.billing.overview.upgrade_plan') : (isLegacyCustomer ? t('web.billing.overview.manage_subscription') : t('web.billing.overview.change_plan')) }}
              </router-link>
            </div>

            <!-- Plan Features -->
            <div class="mt-6 border-t border-gray-200 pt-6 dark:border-gray-700">
              <p class="mb-3 text-sm font-medium text-gray-700 dark:text-gray-300">
                {{ t('web.billing.overview.plan_features') }}
              </p>

              <!-- Loading skeleton -->
              <div v-if="isLoading" class="grid grid-cols-1 gap-2 sm:grid-cols-2">
                <div
                  v-for="i in 4"
                  :key="i"
                  class="flex animate-pulse items-center gap-2">
                  <div class="size-5 rounded-full bg-gray-200 dark:bg-gray-700"></div>
                  <div class="h-4 w-32 rounded bg-gray-200 dark:bg-gray-700"></div>
                </div>
              </div>

              <!-- Features list (i18n locale keys) -->
              <div v-else-if="planFeatures.length > 0" class="grid grid-cols-1 gap-2 sm:grid-cols-2">
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

              <!-- Fallback to entitlements if no features -->
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

              <!-- No features -->
              <div v-else class="text-sm text-gray-500 dark:text-gray-400">
                {{ t('web.billing.overview.no_entitlements') }}
              </div>
            </div>
          </div>
        </div>

        <!-- Billing Contact Card - only for paid plans -->
        <div
          v-if="hasPaidPlan"
          class="rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-700 dark:bg-gray-800"
          data-testid="billing-contact-card">
          <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
            <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
              {{ t('web.billing.overview.billing_contact') }}
            </h2>
          </div>
          <div class="p-6">
            <div data-testid="billing-email-field">
              <label class="block text-sm font-medium text-gray-700 dark:text-gray-300">
                {{ t('web.organizations.contact_email') }}
              </label>

              <!-- Display Mode: Show email as text with Edit button -->
              <div v-if="!isEditingBillingEmail" class="mt-2 flex items-center gap-3">
                <span class="text-sm text-gray-900 dark:text-white">
                  {{ selectedOrg?.billing_email || selectedOrg?.contact_email || t('web.COMMON.not_set') }}
                </span>
                <button
                  type="button"
                  data-testid="billing-email-edit-btn"
                  @click="handleEditBillingEmail"
                  class="text-sm font-medium text-brand-600 hover:text-brand-500 dark:text-brand-400 dark:hover:text-brand-300">
                  {{ t('web.COMMON.word_edit') }}
                </button>
              </div>

              <!-- Edit Mode: Inline form -->
              <div v-else class="mt-2 space-y-2">
                <div class="flex items-center gap-2">
                  <input
                    id="billing-email"
                    data-testid="billing-email-input"
                    v-model="billingEmailForm.email"
                    type="email"
                    required
                    :placeholder="t('web.organizations.contact_email')"
                    class="block w-full max-w-md rounded-md border-gray-300 shadow-sm focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-400 sm:text-sm"
                    @keyup.enter="handleSaveBillingEmail"
                    @keyup.escape="handleCancelBillingEmailEdit" />
                  <button
                    type="button"
                    data-testid="billing-email-save-btn"
                    @click="handleSaveBillingEmail"
                    :disabled="isSavingBillingEmail"
                    class="rounded-md bg-brand-600 px-3 py-1.5 text-sm font-semibold text-white shadow-sm hover:bg-brand-500 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-brand-500 dark:hover:bg-brand-400">
                    <span v-if="!isSavingBillingEmail">{{ t('web.COMMON.word_save') }}</span>
                    <OIcon
                      v-else
                      collection="heroicons"
                      name="arrow-path"
                      class="size-4 animate-spin"
                      aria-hidden="true" />
                  </button>
                  <button
                    type="button"
                    data-testid="billing-email-cancel-btn"
                    @click="handleCancelBillingEmailEdit"
                    :disabled="isSavingBillingEmail"
                    class="rounded-md bg-white px-3 py-1.5 text-sm font-semibold text-gray-700 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-gray-700 dark:text-gray-200 dark:ring-gray-600 dark:hover:bg-gray-600">
                    {{ t('web.COMMON.word_cancel') }}
                  </button>
                </div>
              </div>

              <p class="mt-2 text-xs text-gray-500 dark:text-gray-400">
                {{ t('web.organizations.contact_email_help') }}
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
  </BillingLayout>
</template>
