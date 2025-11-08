<!-- src/views/billing/BillingOverview.vue -->

<script setup lang="ts">
import BasicFormAlerts from '@/components/BasicFormAlerts.vue';
import OIcon from '@/components/icons/OIcon.vue';
import BillingLayout from '@/components/layout/BillingLayout.vue';
import { useCapabilities } from '@/composables/useCapabilities';
import { classifyError } from '@/schemas/errors';
import { useOrganizationStore } from '@/stores/organizationStore';
import type { PaymentMethod } from '@/types/billing';
import { getPlanLabel } from '@/types/billing';
import type { Organization } from '@/types/organization';
import { CAPABILITIES } from '@/types/organization';
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const organizationStore = useOrganizationStore();

const selectedOrgId = ref<string | null>(null);
const selectedOrg = ref<Organization | null>(null);
const paymentMethod = ref<PaymentMethod | null>(null);
const nextBillingDate = ref<Date | null>(null);
const isLoading = ref(false);
const error = ref('');

const organizations = computed(() => organizationStore.organizations);
const { capabilities } = useCapabilities(selectedOrg);

const planName = computed(() => {
  if (!selectedOrg.value?.planid) return t('web.billing.plans.free_plan');
  return getPlanLabel(selectedOrg.value.planid as any) || selectedOrg.value.planid;
});

const planStatus = computed(() => selectedOrg.value?.planid ? 'active' : 'free');

const formatCapability = (cap: string): string => {
  const labels: Record<string, string> = {
    [CAPABILITIES.CREATE_SECRETS]: t('web.billing.overview.capabilities.create_secrets'),
    [CAPABILITIES.BASIC_SHARING]: t('web.billing.overview.capabilities.basic_sharing'),
    [CAPABILITIES.CREATE_TEAM]: t('web.billing.overview.capabilities.create_team'),
    [CAPABILITIES.CREATE_TEAMS]: t('web.billing.overview.capabilities.create_teams'),
    [CAPABILITIES.CUSTOM_DOMAINS]: t('web.billing.overview.capabilities.custom_domains'),
    [CAPABILITIES.API_ACCESS]: t('web.billing.overview.capabilities.api_access'),
    [CAPABILITIES.PRIORITY_SUPPORT]: t('web.billing.overview.capabilities.priority_support'),
    [CAPABILITIES.AUDIT_LOGS]: t('web.billing.overview.capabilities.audit_logs'),
  };
  return labels[cap] || cap;
};

const loadOrganizationData = async (orgId: string) => {
  isLoading.value = true;
  error.value = '';
  try {
    const org = await organizationStore.fetchOrganization(orgId);
    selectedOrg.value = org;

    // Fetch capabilities if not already loaded
    if (!org.capabilities) {
      await organizationStore.fetchCapabilities(orgId);
    }

    // TODO: Load payment method and billing date from API
    // This is placeholder logic until backend implements the endpoints
    paymentMethod.value = null;
    nextBillingDate.value = null;
  } catch (err) {
    const classified = classifyError(err);
    error.value = classified.message || 'Failed to load billing information';
    console.error('[BillingOverview] Error loading organization:', err);
  } finally {
    isLoading.value = false;
  }
};

const handleOrgChange = (orgId: string) => {
  selectedOrgId.value = orgId;
  loadOrganizationData(orgId);
};

const formatCardBrand = (brand: string): string => brand.charAt(0).toUpperCase() + brand.slice(1);

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

onMounted(async () => {
  try {
    if (organizations.value.length === 0) {
      await organizationStore.fetchOrganizations();
    }

    if (organizations.value.length > 0) {
      const firstOrg = organizations.value[0];
      selectedOrgId.value = firstOrg.id;
      await loadOrganizationData(firstOrg.id);
    }
  } catch (err) {
    const classified = classifyError(err);
    error.value = classified.message || 'Failed to load organizations';
    console.error('[BillingOverview] Error loading organizations:', err);
  }
});
</script>

<template>
  <BillingLayout>
    <div class="space-y-6">
      <!-- Header -->
      <div>
        <h1 class="text-2xl font-bold text-gray-900 dark:text-white">
          {{ t('web.billing.overview.title') }}
        </h1>
      </div>

      <!-- Organization Selector (if multiple orgs) -->
      <div v-if="organizations.length > 1" class="rounded-lg border border-gray-200 bg-white p-4 dark:border-gray-700 dark:bg-gray-800">
        <label for="org-select" class="mb-2 block text-sm font-medium text-gray-700 dark:text-gray-300">
          {{ t('web.billing.overview.organization_selector') }}
        </label>
        <select
          id="org-select"
          v-model="selectedOrgId"
          @change="handleOrgChange(selectedOrgId!)"
          class="block w-full rounded-md border-gray-300 shadow-sm focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white sm:text-sm">
          <option
            v-for="org in organizations"
            :key="org.id"
            :value="org.id">
            {{ org.display_name }}
          </option>
        </select>
      </div>

      <!-- Error Alert -->
      <BasicFormAlerts v-if="error" :error="error" />

      <!-- Loading State -->
      <div v-if="isLoading" class="flex items-center justify-center py-12">
        <div class="text-center">
          <OIcon
            collection="heroicons"
            name="arrow-path"
            class="mx-auto size-8 animate-spin text-gray-400"
            aria-hidden="true"
          />
          <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
            {{ t('web.COMMON.loading') }}
          </p>
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
              </div>
              <router-link
                :to="{ name: 'Billing Plans' }"
                class="inline-flex items-center gap-2 rounded-md bg-brand-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-brand-500 dark:bg-brand-500 dark:hover:bg-brand-400">
                <OIcon
                  collection="heroicons"
                  name="arrow-up-circle"
                  class="size-4"
                  aria-hidden="true"
                />
                {{ planStatus === 'free' ? t('web.billing.overview.upgrade_plan') : 'Change Plan' }}
              </router-link>
            </div>

            <!-- Plan Features -->
            <div v-if="capabilities.length > 0" class="mt-6 border-t border-gray-200 pt-6 dark:border-gray-700">
              <p class="mb-3 text-sm font-medium text-gray-700 dark:text-gray-300">
                {{ t('web.billing.overview.plan_features') }}
              </p>
              <div class="grid grid-cols-1 gap-2 sm:grid-cols-2">
                <div
                  v-for="cap in capabilities"
                  :key="cap"
                  class="flex items-center gap-2 text-sm text-gray-700 dark:text-gray-300">
                  <OIcon
                    collection="heroicons"
                    name="check-circle"
                    class="size-5 text-green-500 dark:text-green-400"
                    aria-hidden="true"
                  />
                  {{ formatCapability(cap) }}
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Payment Method & Next Billing -->
        <div class="grid grid-cols-1 gap-6 md:grid-cols-2">
          <!-- Payment Method -->
          <div class="rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-700 dark:bg-gray-800">
            <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
              <h3 class="text-base font-semibold text-gray-900 dark:text-white">
                {{ t('web.billing.overview.payment_method') }}
              </h3>
            </div>
            <div class="p-6">
              <div v-if="paymentMethod?.card">
                <div class="flex items-center gap-3">
                  <div class="flex size-12 items-center justify-center rounded-lg bg-gray-100 dark:bg-gray-700">
                    <OIcon
                      collection="heroicons"
                      name="credit-card"
                      class="size-6 text-gray-600 dark:text-gray-400"
                      aria-hidden="true"
                    />
                  </div>
                  <div>
                    <p class="text-sm font-medium text-gray-900 dark:text-white">
                      {{ formatCardBrand(paymentMethod.card.brand) }} •••• {{ paymentMethod.card.last4 }}
                    </p>
                    <p class="text-xs text-gray-500 dark:text-gray-400">
                      Expires {{ paymentMethod.card.exp_month }}/{{ paymentMethod.card.exp_year }}
                    </p>
                  </div>
                </div>
              </div>
              <div v-else class="py-4 text-center">
                <OIcon
                  collection="heroicons"
                  name="credit-card"
                  class="mx-auto size-8 text-gray-400"
                  aria-hidden="true"
                />
                <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
                  {{ t('web.billing.overview.no_payment_method') }}
                </p>
              </div>
            </div>
          </div>

          <!-- Next Billing Date -->
          <div class="rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-700 dark:bg-gray-800">
            <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
              <h3 class="text-base font-semibold text-gray-900 dark:text-white">
                {{ t('web.billing.overview.next_billing_date') }}
              </h3>
            </div>
            <div class="p-6">
              <div v-if="nextBillingDate" class="text-center">
                <p class="text-2xl font-bold text-gray-900 dark:text-white">
                  {{ daysUntilBilling }}
                </p>
                <p class="text-sm text-gray-500 dark:text-gray-400">
                  days remaining
                </p>
                <p class="mt-2 text-xs text-gray-500 dark:text-gray-400">
                  Billing on {{ formatNextBillingDate(nextBillingDate) }}
                </p>
              </div>
              <div v-else class="py-4 text-center">
                <p class="text-sm text-gray-500 dark:text-gray-400">
                  No upcoming billing
                </p>
              </div>
            </div>
          </div>
        </div>

        <!-- Quick Actions -->
        <div class="rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-700 dark:bg-gray-800">
          <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
            <h3 class="text-base font-semibold text-gray-900 dark:text-white">
              {{ t('web.billing.overview.quick_actions') }}
            </h3>
          </div>
          <div class="grid grid-cols-1 gap-4 p-6 sm:grid-cols-3">
            <!-- View Plans -->
            <router-link
              :to="{ name: 'Billing Plans' }"
              class="flex flex-col items-center rounded-lg border border-gray-200 p-4 text-center transition-colors hover:border-brand-500 hover:bg-brand-50 dark:border-gray-700 dark:hover:border-brand-400 dark:hover:bg-brand-900/10">
              <div class="flex size-12 items-center justify-center rounded-full bg-brand-100 dark:bg-brand-900/30">
                <OIcon
                  collection="tabler"
                  name="square-letter-s"
                  class="size-6 text-brand-600 dark:text-brand-400"
                  aria-hidden="true"
                />
              </div>
              <p class="mt-3 text-sm font-medium text-gray-900 dark:text-white">
                View Plans
              </p>
              <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
                Compare and upgrade
              </p>
            </router-link>

            <!-- View Invoices -->
            <router-link
              :to="{ name: 'Billing Invoices' }"
              class="flex flex-col items-center rounded-lg border border-gray-200 p-4 text-center transition-colors hover:border-brand-500 hover:bg-brand-50 dark:border-gray-700 dark:hover:border-brand-400 dark:hover:bg-brand-900/10">
              <div class="flex size-12 items-center justify-center rounded-full bg-brand-100 dark:bg-brand-900/30">
                <OIcon
                  collection="heroicons"
                  name="document-text"
                  class="size-6 text-brand-600 dark:text-brand-400"
                  aria-hidden="true"
                />
              </div>
              <p class="mt-3 text-sm font-medium text-gray-900 dark:text-white">
                View Invoices
              </p>
              <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
                Download history
              </p>
            </router-link>

            <!-- Manage Billing -->
            <button
              type="button"
              disabled
              class="flex flex-col items-center rounded-lg border border-gray-200 p-4 text-center transition-colors hover:border-brand-500 hover:bg-brand-50 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-700 dark:hover:border-brand-400 dark:hover:bg-brand-900/10">
              <div class="flex size-12 items-center justify-center rounded-full bg-brand-100 dark:bg-brand-900/30">
                <OIcon
                  collection="heroicons"
                  name="cog-6-tooth"
                  class="size-6 text-brand-600 dark:text-brand-400"
                  aria-hidden="true"
                />
              </div>
              <p class="mt-3 text-sm font-medium text-gray-900 dark:text-white">
                Manage Billing
              </p>
              <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
                Update payment info
              </p>
            </button>
          </div>
        </div>
      </div>
    </div>
  </BillingLayout>
</template>
