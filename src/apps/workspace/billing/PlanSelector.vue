<!-- src/apps/workspace/billing/PlanSelector.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
import BasicFormAlerts from '@/shared/components/forms/BasicFormAlerts.vue';
import FeedbackToggle from '@/shared/components/ui/FeedbackToggle.vue';
import OIcon from '@/shared/components/icons/OIcon.vue';
import { useEntitlements } from '@/shared/composables/useEntitlements';
import { classifyError } from '@/schemas/errors';
import { BillingService, type Plan as BillingPlan } from '@/services/billing.service';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import type { BillingInterval } from '@/types/billing';
import { formatCurrency } from '@/types/billing';
import { computed, onMounted, ref } from 'vue';
import { useRoute } from 'vue-router';

const { t } = useI18n();
const route = useRoute();
const organizationStore = useOrganizationStore();

const billingInterval = ref<BillingInterval>('month');
const selectedOrgId = ref<string | null>(null);
const isCreatingCheckout = ref(false);
const isLoadingPlans = ref(false);
const error = ref('');
const suggestedPlanId = ref<string | null>(null);

// Plans loaded from API
const plans = ref<BillingPlan[]>([]);

const organizations = computed(() => organizationStore.organizations);
const selectedOrg = computed(() =>
  organizations.value.find(org => org.id === selectedOrgId.value)
);

// Use entitlements composable for formatting
const selectedOrgRef = computed(() => selectedOrg.value ?? null);
const {
  formatEntitlement,
  initDefinitions,
  isLoadingDefinitions,
  definitionsError,
} = useEntitlements(selectedOrgRef);

const currentPlanId = computed(() => selectedOrg.value?.planid || 'free');

// Filter plans by selected billing interval
const filteredPlans = computed(() => plans.value.filter(plan => plan.interval === billingInterval.value));

/**
 * Get the display label for a feature/entitlement
 * Uses API-driven i18n keys via useEntitlements
 */
const getFeatureLabel = (feature: string): string => formatEntitlement(feature);

/**
 * Combined loading state for the component
 */
const isLoadingContent = computed(() => isLoadingPlans.value || isLoadingDefinitions.value);

// Get base plan for comparison (Identity Plus is always the base)
const getBasePlan = (plan: BillingPlan): BillingPlan | undefined => {
  if (plan.tier === 'single_team') return undefined; // Identity Plus has no base
  // Find Identity Plus with same interval
  return filteredPlans.value.find(p => p.tier === 'single_team' && p.interval === plan.interval);
};

// Get only NEW features for this plan (excluding base plan features)
const getNewFeatures = (plan: BillingPlan): string[] => {
  const basePlan = getBasePlan(plan);
  if (!basePlan) return plan.entitlements; // Show all for Identity Plus

  // Filter out features that exist in base plan
  return plan.entitlements.filter(ent => !basePlan.entitlements.includes(ent));
};

const getPlanPricePerMonth = (plan: BillingPlan): number => {
  // For yearly plans, show the monthly equivalent
  if (plan.interval === 'year') {
    return Math.floor(plan.amount / 12);
  }
  // For monthly plans, show the amount as-is
  return plan.amount;
};

const isPlanRecommended = (plan: BillingPlan): boolean => plan.tier === 'single_team';

const isPlanCurrent = (plan: BillingPlan): boolean => plan.tier === currentPlanId.value;

const canUpgrade = (plan: BillingPlan): boolean => {
  if (currentPlanId.value === 'free') return plan.tier !== 'free';
  if (currentPlanId.value === 'single_team') return plan.tier === 'multi_team';
  return false;
};

const canDowngrade = (plan: BillingPlan): boolean => {
  if (currentPlanId.value === 'multi_team') return plan.tier !== 'multi_team';
  if (currentPlanId.value === 'single_team') return plan.tier === 'free';
  return false;
};

const getButtonLabel = (plan: BillingPlan): string => {
  if (isPlanCurrent(plan)) return t('web.billing.plans.current');
  if (canUpgrade(plan)) return t('web.billing.plans.upgrade');
  if (canDowngrade(plan)) return t('web.billing.plans.downgrade');
  return t('web.billing.plans.select_plan');
};

const loadPlans = async () => {
  isLoadingPlans.value = true;
  error.value = '';
  try {
    const response = await BillingService.listPlans();
    plans.value = response.plans;
  } catch (err) {
    const classified = classifyError(err);
    error.value = classified.message || 'Failed to load plans';
    console.error('[PlanSelector] Error loading plans:', err);
  } finally {
    isLoadingPlans.value = false;
  }
};

const handlePlanSelect = async (plan: BillingPlan) => {
  if (isPlanCurrent(plan) || !selectedOrgId.value || plan.tier === 'free') return;

  const selectedOrganization = organizations.value.find(org => org.id === selectedOrgId.value);
  if (!selectedOrganization?.extid) {
    error.value = 'Organization not found';
    return;
  }

  isCreatingCheckout.value = true;
  error.value = '';

  try {
    const response = await BillingService.createCheckoutSession(
      selectedOrganization.extid,
      plan.tier,
      billingInterval.value
    );

    // Redirect to Stripe Checkout
    if (response.checkout_url) {
      window.location.href = response.checkout_url;
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
    // Load entitlement definitions and plans in parallel
    await Promise.all([
      initDefinitions(),
      loadPlans(),
    ]);

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
  <div class="mx-auto max-w-[1400px] px-4 py-8 sm:px-6 lg:px-8">
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



      <!-- Organization Selector (hidden - billing uses default org) -->

      <!-- Error Alerts -->
      <BasicFormAlerts v-if="error" :error="error" />
      <BasicFormAlerts v-if="definitionsError" :error="definitionsError" />

      <!-- Loading State -->
      <div v-if="isLoadingContent" class="flex items-center justify-center py-12">
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

      <!-- No Plans Message -->
      <div v-else-if="filteredPlans.length === 0" class="rounded-lg border border-gray-200 bg-gray-50 p-8 text-center dark:border-gray-700 dark:bg-gray-900/50">
        <p class="text-gray-600 dark:text-gray-400">
          No {{ billingInterval === 'year' ? 'yearly' : 'monthly' }} plans available at this time.
        </p>
      </div>

      <!-- Plan Cards -->
      <div v-else class="mx-auto grid max-w-[1600px] grid-cols-1 gap-6 sm:grid-cols-2 xl:grid-cols-4">
        <div
          v-for="plan in filteredPlans"
          :key="plan.id"
          :class="[
            'relative flex flex-col rounded-2xl border bg-white transition-all hover:shadow-lg dark:bg-gray-800',
            isPlanRecommended(plan)
              ? 'border-brand-500 ring-2 ring-brand-500 shadow-xl md:scale-105 dark:border-brand-400 dark:ring-brand-400'
              : 'border-gray-200 shadow-sm dark:border-gray-700',
            suggestedPlanId === plan.id ? 'ring-2 ring-yellow-500' : '',
          ]"
          :style="{ zIndex: isPlanRecommended(plan) ? 10 : 1 }">
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
                {{ plan.tier }} plan
              </p>
            </div>

            <!-- Price -->
            <div class="mb-6">
              <div class="flex items-baseline gap-2">
                <span class="text-4xl font-bold text-gray-900 dark:text-white">
                  {{ formatCurrency(getPlanPricePerMonth(plan), plan.currency) }}
                </span>
                <span class="text-sm text-gray-500 dark:text-gray-400">
                  /month
                </span>
              </div>
              <p v-if="plan.interval === 'year' && plan.amount > 0" class="mt-1 text-xs text-gray-500 dark:text-gray-400">
                Billed {{ formatCurrency(plan.amount, plan.currency) }} yearly
              </p>
            </div>

            <!-- Team & Member Limits -->
            <div class="mb-6 space-y-2 text-sm">
              <p class="text-gray-700 dark:text-gray-300">
                {{ t('web.billing.plans.teams_limit', { count: plan.limits.teams || 1 }) }}
              </p>
              <p class="text-gray-700 dark:text-gray-300">
                {{ t('web.billing.plans.members_limit', { count: plan.limits.members_per_team || 1 }) }}
              </p>
            </div>

            <!-- Features -->
            <div class="space-y-3">
              <p class="text-sm font-semibold text-gray-900 dark:text-white">
                {{ t('web.billing.plans.features') }}
              </p>

              <!-- Show base plan reference for higher tiers -->
              <p v-if="getBasePlan(plan)" class="text-xs font-medium text-gray-500 dark:text-gray-400">
                ✓ Everything in {{ getBasePlan(plan)?.name }}, plus:
              </p>

              <ul class="space-y-2">
                <li
                  v-for="entitlement in getNewFeatures(plan)"
                  :key="entitlement"
                  class="flex items-start gap-2 text-sm text-gray-700 dark:text-gray-300">
                  <OIcon
                    collection="heroicons"
                    name="check"
                    class="mt-0.5 size-5 shrink-0 text-green-500 dark:text-green-400"
                    aria-hidden="true" />
                  <span>{{ getFeatureLabel(entitlement) }}</span>
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

      <!-- Custom Needs -->
      <div class="rounded-lg border border-gray-200 bg-gray-50 p-8 text-center dark:border-gray-700 dark:bg-gray-900/50">
        <h3 class="text-lg font-semibold text-gray-900 dark:text-white">
          {{ t('web.billing.plans.custom_needs_title') }}
        </h3>
        <p class="mt-2 text-sm text-gray-600 dark:text-gray-400">
          {{ t('web.billing.plans.custom_needs_description') }}
        </p>
        <div class="mt-4 flex justify-center">
          <FeedbackToggle />
        </div>
      </div>
    </div>
  </div>
</template>
