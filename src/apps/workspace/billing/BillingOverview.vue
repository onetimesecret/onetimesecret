<!-- src/apps/workspace/billing/BillingOverview.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
import BasicFormAlerts from '@/shared/components/forms/BasicFormAlerts.vue';
import OIcon from '@/shared/components/icons/OIcon.vue';
import BillingLayout from '@/shared/components/layout/BillingLayout.vue';
import { useEntitlements } from '@/shared/composables/useEntitlements';
import { classifyError } from '@/schemas/errors';
import { BillingService } from '@/services/billing.service';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import type { PaymentMethod } from '@/types/billing';
import { getPlanDisplayName } from '@/types/billing';
import type { Organization } from '@/types/organization';
import { computed, onMounted, ref } from 'vue';

const { t } = useI18n();
const organizationStore = useOrganizationStore();

const selectedOrgId = ref<string | null>(null);
const selectedOrg = ref<Organization | null>(null);
const paymentMethod = ref<PaymentMethod | null>(null);
const nextBillingDate = ref<Date | null>(null);
const planFeatures = ref<string[]>([]);
const isLoading = ref(false);
const error = ref('');

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

      // Update next billing date from subscription
      if (overview.subscription?.period_end) {
        nextBillingDate.value = new Date(overview.subscription.period_end * 1000);
      } else {
        nextBillingDate.value = null;
      }

      // Store plan features (i18n locale keys)
      planFeatures.value = overview.plan?.features || [];

      // Payment method coming from backend in future update
      paymentMethod.value = overview.payment_method || null;
    }
  } catch (err) {
    const classified = classifyError(err);
    error.value = classified.message || 'Failed to load billing information';
    console.error('[BillingOverview] Error loading organization:', err);
  } finally {
    isLoading.value = false;
  }
};

const handleOrgChange = (orgId: string) => {
  // Find org by internal ID to get extid for API call
  const org = organizations.value.find((o) => o.id === orgId);
  if (org?.extid) {
    loadOrganizationData(org.extid);
  } else {
    console.warn('[BillingOverview] Organization not found in cache, cannot load:', orgId);
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

onMounted(async () => {
  try {
    // Initialize entitlement definitions for formatting
    await initDefinitions();

    if (organizations.value.length === 0) {
      await organizationStore.fetchOrganizations();
    }

    if (organizations.value.length > 0) {
      const firstOrg = organizations.value[0];
      selectedOrgId.value = firstOrg.id;
      if (firstOrg.extid) {
        await loadOrganizationData(firstOrg.extid);
      }
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
            :to="{ name: 'Billing Organizations' }"
            class="inline-flex items-center gap-2 rounded-md bg-brand-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-brand-500 dark:bg-brand-500 dark:hover:bg-brand-400">
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
                :to="{ name: 'Billing Plans' }"
                class="inline-flex items-center gap-2 rounded-md bg-brand-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-brand-500 dark:bg-brand-500 dark:hover:bg-brand-400">
                <OIcon
                  collection="heroicons"
                  name="arrow-up-circle"
                  class="size-4"
                  aria-hidden="true" />
                {{ planStatus === 'free' ? t('web.billing.overview.upgrade_plan') : t('web.billing.overview.change_plan') }}
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
      </div>
    </div>
  </BillingLayout>
</template>
