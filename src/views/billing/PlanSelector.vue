<!-- src/views/billing/PlanSelector.vue -->

<script setup lang="ts">
import BasicFormAlerts from '@/components/BasicFormAlerts.vue';
import OIcon from '@/components/icons/OIcon.vue';
import SettingsLayout from '@/components/layout/SettingsLayout.vue';
import { classifyError } from '@/schemas/errors';
import { useOrganizationStore } from '@/stores/organizationStore';
import type { Plan, BillingInterval } from '@/types/billing';
import { formatCurrency } from '@/types/billing';
import { CAPABILITIES } from '@/types/organization';
import { AxiosInstance } from 'axios';
import { computed, inject, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';

const { t } = useI18n();
const route = useRoute();
const organizationStore = useOrganizationStore();
const $api = inject('api') as AxiosInstance;

const billingInterval = ref<BillingInterval>('month');
const selectedOrgId = ref<string | null>(null);
const isCreatingCheckout = ref(false);
const error = ref('');
const suggestedPlanId = ref<string | null>(null);

// Plan definitions (these would normally come from API)
const plans = ref<Plan[]>([
  {
    id: 'free',
    type: 'free',
    name: 'Free',
    description: 'Perfect for personal use',
    price_monthly: 0,
    price_yearly: 0,
    teams_limit: 1,
    members_per_team_limit: 1,
    features: [
      'create_secrets',
      'basic_sharing',
      'create_team',
    ],
  },
  {
    id: 'identity_plus',
    type: 'single_team',
    name: 'Identity Plus',
    description: 'Enhanced features for professionals',
    price_monthly: 999,
    price_yearly: 9990,
    teams_limit: 1,
    members_per_team_limit: 5,
    features: [
      'create_secrets',
      'basic_sharing',
      'create_team',
      'custom_domains',
      'priority_support',
    ],
  },
  {
    id: 'multi_team',
    type: 'multi_team',
    name: 'Multi-Team',
    description: 'For organizations managing multiple teams',
    price_monthly: 2999,
    price_yearly: 29990,
    teams_limit: 10,
    members_per_team_limit: 20,
    features: [
      'create_secrets',
      'basic_sharing',
      'create_teams',
      'custom_domains',
      'api_access',
      'priority_support',
      'audit_logs',
    ],
  },
]);

const organizations = computed(() => organizationStore.organizations);
const selectedOrg = computed(() =>
  organizations.value.find(org => org.id === selectedOrgId.value)
);

const currentPlanId = computed(() => selectedOrg.value?.planid || 'free');

const yearlySavingsPercent = computed(() =>
   17 // ~2 months free
);

const getFeatureLabel = (feature: string): string => {
  const labels: Record<string, string> = {
    [CAPABILITIES.CREATE_SECRETS]: 'Unlimited secrets',
    [CAPABILITIES.BASIC_SHARING]: 'Basic sharing features',
    [CAPABILITIES.CREATE_TEAM]: 'Single team',
    [CAPABILITIES.CREATE_TEAMS]: 'Multiple teams',
    [CAPABILITIES.CUSTOM_DOMAINS]: 'Custom domains',
    [CAPABILITIES.API_ACCESS]: 'Full API access',
    [CAPABILITIES.PRIORITY_SUPPORT]: 'Priority support',
    [CAPABILITIES.AUDIT_LOGS]: 'Audit logs',
  };
  return labels[feature] || feature;
};

const getPlanPricePerMonth = (plan: Plan): number => {
  if (billingInterval.value === 'month') return plan.price_monthly;
  return Math.floor(plan.price_yearly / 12);
};

const isPlanRecommended = (plan: Plan): boolean => plan.id === 'identity_plus';

const isPlanCurrent = (plan: Plan): boolean => plan.id === currentPlanId.value;

const canUpgrade = (plan: Plan): boolean => {
  if (currentPlanId.value === 'free') return plan.id !== 'free';
  if (currentPlanId.value === 'identity_plus') return plan.id === 'multi_team';
  return false;
};

const canDowngrade = (plan: Plan): boolean => {
  if (currentPlanId.value === 'multi_team') return plan.id !== 'multi_team';
  if (currentPlanId.value === 'identity_plus') return plan.id === 'free';
  return false;
};

const getButtonLabel = (plan: Plan): string => {
  if (isPlanCurrent(plan)) return t('web.billing.plans.current');
  if (canUpgrade(plan)) return t('web.billing.plans.upgrade');
  if (canDowngrade(plan)) return t('web.billing.plans.downgrade');
  return t('web.billing.plans.select_plan');
};

const handlePlanSelect = async (plan: Plan) => {
  if (isPlanCurrent(plan) || !selectedOrgId.value || plan.id === 'free') return;

  isCreatingCheckout.value = true;
  error.value = '';

  try {
    const response = await $api.post(`/api/billing/org/${selectedOrgId.value}/checkout`, {
      plan_id: plan.id,
      interval: billingInterval.value,
    });

    // Redirect to Stripe Checkout
    if (response.data.checkout_url) {
      window.location.href = response.data.checkout_url;
    } else {
      error.value = 'Failed to create checkout session';
    }
  } catch (err) {
    const classified = classifyError(err);
    error.value = classified.message || 'Failed to initiate checkout';
    console.error('[PlanSelector] Checkout error:', err);
  } finally {
    isCreatingCheckout.value = false;
  }
};

onMounted(async () => {
  try {
    if (organizations.value.length === 0) {
      await organizationStore.fetchOrganizations();
    }

    if (organizations.value.length > 0) {
      selectedOrgId.value = organizations.value[0].id;
    }

    // Check for upgrade_to query param
    const upgradeToParam = route.query.upgrade_to as string;
    if (upgradeToParam) {
      suggestedPlanId.value = upgradeToParam;
    }
  } catch (err) {
    const classified = classifyError(err);
    error.value = classified.message || 'Failed to load organizations';
    console.error('[PlanSelector] Error loading organizations:', err);
  }
});
</script>

<template>
  <SettingsLayout>
    <div class="space-y-8">
      <!-- Header -->
      <div class="text-center">
        <h1 class="text-3xl font-bold text-gray-900 dark:text-white">
          {{ t('web.billing.plans.title') }}
        </h1>
        <p class="mt-2 text-base text-gray-600 dark:text-gray-400">
          Choose the perfect plan for your organization
        </p>
      </div>

      <!-- Billing Interval Toggle -->
      <div class="flex items-center justify-center gap-3">
        <button
          @click="billingInterval = 'month'"
          :class="[
            'rounded-md px-4 py-2 text-sm font-medium transition-colors',
            billingInterval === 'month'
              ? 'bg-brand-600 text-white dark:bg-brand-500'
              : 'bg-gray-100 text-gray-700 hover:bg-gray-200 dark:bg-gray-800 dark:text-gray-300 dark:hover:bg-gray-700',
          ]">
          {{ t('web.billing.plans.monthly') }}
        </button>
        <button
          @click="billingInterval = 'year'"
          :class="[
            'rounded-md px-4 py-2 text-sm font-medium transition-colors',
            billingInterval === 'year'
              ? 'bg-brand-600 text-white dark:bg-brand-500'
              : 'bg-gray-100 text-gray-700 hover:bg-gray-200 dark:bg-gray-800 dark:text-gray-300 dark:hover:bg-gray-700',
          ]">
          {{ t('web.billing.plans.yearly') }}
        </button>
      </div>

      <div v-if="billingInterval === 'year'" class="text-center">
        <p class="text-sm font-medium text-green-600 dark:text-green-400">
          {{ t('web.billing.plans.save_yearly', { percent: yearlySavingsPercent }) }}
        </p>
      </div>

      <!-- Organization Selector -->
      <div v-if="organizations.length > 1" class="mx-auto max-w-md">
        <label for="org-select" class="mb-2 block text-sm font-medium text-gray-700 dark:text-gray-300">
          {{ t('web.billing.overview.organization_selector') }}
        </label>
        <select
          id="org-select"
          v-model="selectedOrgId"
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

      <!-- Plan Cards -->
      <div class="mx-auto grid max-w-7xl grid-cols-1 gap-8 md:grid-cols-3">
        <div
          v-for="plan in plans"
          :key="plan.id"
          :class="[
            'relative flex flex-col rounded-2xl border bg-white shadow-sm transition-shadow hover:shadow-lg dark:bg-gray-800',
            isPlanRecommended(plan)
              ? 'border-brand-500 ring-2 ring-brand-500 dark:border-brand-400 dark:ring-brand-400'
              : 'border-gray-200 dark:border-gray-700',
            suggestedPlanId === plan.id ? 'ring-2 ring-yellow-500' : '',
          ]">
          <!-- Recommended Badge -->
          <div
            v-if="isPlanRecommended(plan)"
            class="absolute -top-5 left-1/2 -translate-x-1/2 rounded-full bg-brand-600 px-3 py-1 text-xs font-semibold text-white dark:bg-brand-500">
            Most Popular
          </div>

          <!-- Suggested Badge -->
          <div
            v-if="suggestedPlanId === plan.id"
            class="absolute -top-5 right-4 rounded-full bg-yellow-500 px-3 py-1 text-xs font-semibold text-white">
            Suggested
          </div>

          <div class="flex-1 p-6">
            <!-- Plan Header -->
            <div class="mb-4">
              <h3 class="text-xl font-bold text-gray-900 dark:text-white">
                {{ plan.name }}
              </h3>
              <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
                {{ plan.description }}
              </p>
            </div>

            <!-- Price -->
            <div class="mb-6">
              <div class="flex items-baseline gap-2">
                <span class="text-4xl font-bold text-gray-900 dark:text-white">
                  {{ formatCurrency(getPlanPricePerMonth(plan)) }}
                </span>
                <span class="text-sm text-gray-500 dark:text-gray-400">
                  /month
                </span>
              </div>
              <p v-if="billingInterval === 'year' && plan.price_yearly > 0" class="mt-1 text-xs text-gray-500 dark:text-gray-400">
                Billed {{ formatCurrency(plan.price_yearly) }} yearly
              </p>
            </div>

            <!-- Team & Member Limits -->
            <div class="mb-6 space-y-2 text-sm">
              <p class="text-gray-700 dark:text-gray-300">
                {{ t('web.billing.plans.teams_limit', { count: plan.teams_limit }) }}
              </p>
              <p class="text-gray-700 dark:text-gray-300">
                {{ t('web.billing.plans.members_limit', { count: plan.members_per_team_limit }) }}
              </p>
            </div>

            <!-- Features -->
            <div class="space-y-3">
              <p class="text-sm font-semibold text-gray-900 dark:text-white">
                {{ t('web.billing.plans.features') }}
              </p>
              <ul class="space-y-2">
                <li
                  v-for="feature in plan.features"
                  :key="feature"
                  class="flex items-start gap-2 text-sm text-gray-700 dark:text-gray-300">
                  <OIcon
                    collection="heroicons"
                    name="check"
                    class="mt-0.5 size-5 shrink-0 text-green-500 dark:text-green-400"
                    aria-hidden="true"
                  />
                  <span>{{ getFeatureLabel(feature) }}</span>
                </li>
              </ul>
            </div>
          </div>

          <!-- Action Button -->
          <div class="border-t border-gray-200 p-6 dark:border-gray-700">
            <button
              @click="handlePlanSelect(plan)"
              :disabled="isPlanCurrent(plan) || isCreatingCheckout || plan.id === 'free'"
              :class="[
                'w-full rounded-md px-4 py-2 text-sm font-semibold transition-colors',
                isPlanCurrent(plan)
                  ? 'cursor-default bg-gray-100 text-gray-700 dark:bg-gray-700 dark:text-gray-300'
                  : canUpgrade(plan)
                    ? 'bg-brand-600 text-white hover:bg-brand-500 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-brand-500 dark:hover:bg-brand-400'
                    : 'bg-white text-gray-700 ring-1 ring-inset ring-gray-300 hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-gray-800 dark:text-gray-300 dark:ring-gray-600 dark:hover:bg-gray-700',
              ]">
              <span v-if="isCreatingCheckout && !isPlanCurrent(plan)">
                {{ t('web.COMMON.processing') }}
              </span>
              <span v-else>
                {{ getButtonLabel(plan) }}
              </span>
            </button>
          </div>
        </div>
      </div>

      <!-- Contact Sales -->
      <div class="rounded-lg border border-gray-200 bg-gray-50 p-8 text-center dark:border-gray-700 dark:bg-gray-900/50">
        <h3 class="text-lg font-semibold text-gray-900 dark:text-white">
          Need something custom?
        </h3>
        <p class="mt-2 text-sm text-gray-600 dark:text-gray-400">
          Contact our sales team for enterprise plans with custom limits and features
        </p>
        <button
          type="button"
          class="mt-4 inline-flex items-center gap-2 rounded-md bg-gray-900 px-4 py-2 text-sm font-semibold text-white hover:bg-gray-800 dark:bg-white dark:text-gray-900 dark:hover:bg-gray-100">
          {{ t('web.billing.plans.contact_sales') }}
        </button>
      </div>
    </div>
  </SettingsLayout>
</template>
