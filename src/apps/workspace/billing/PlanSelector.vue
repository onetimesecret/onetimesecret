<!-- src/apps/workspace/billing/PlanSelector.vue -->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import BasicFormAlerts from '@/shared/components/forms/BasicFormAlerts.vue';
import BillingLayout from '@/shared/components/layout/BillingLayout.vue';
import FeedbackToggle from '@/shared/components/ui/FeedbackToggle.vue';
import OIcon from '@/shared/components/icons/OIcon.vue';
import PlanCard from '@/shared/components/billing/PlanCard.vue';
import PlanChangeModal from './PlanChangeModal.vue';
import { useEntitlements } from '@/shared/composables/useEntitlements';
import { classifyError } from '@/schemas/errors';
import { BillingService, type Plan as BillingPlan, type SubscriptionStatusResponse } from '@/services/billing.service';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import type { BillingInterval } from '@/types/billing';
import type { Organization } from '@/types/organization';
import { computed, onMounted, ref } from 'vue';
import { useRoute } from 'vue-router';

const { t } = useI18n();
const route = useRoute();
const organizationStore = useOrganizationStore();

// Org extid comes from URL (e.g., /billing/:extid/plans)
const orgExtid = computed(() => route.params.extid as string);

const billingInterval = ref<BillingInterval>('month');
const isCreatingCheckout = ref(false);
const isLoadingPlans = ref(false);
const isLoadingOrg = ref(false);
const error = ref('');
const suggestedPlanId = ref<string | null>(null);
const successMessage = ref('');

// Plans loaded from API
const plans = ref<BillingPlan[]>([]);

// Selected organization loaded from route extid
const selectedOrg = ref<Organization | null>(null);

// Subscription status for plan switching
const subscriptionStatus = ref<SubscriptionStatusResponse | null>(null);
const hasActiveSubscription = computed(() => subscriptionStatus.value?.has_active_subscription ?? false);

// Plan change modal state
const showPlanChangeModal = ref(false);
const targetPlan = ref<BillingPlan | null>(null);

// Current plan for the modal (find from plans list based on subscription)
const currentPlanForModal = computed(() => {
  if (!subscriptionStatus.value?.current_price_id) return null;
  return plans.value.find(p => p.stripe_price_id === subscriptionStatus.value?.current_price_id) ?? null;
});

// Use entitlements composable for definitions loading
const {
  initDefinitions,
  isLoadingDefinitions,
  definitionsError,
} = useEntitlements(selectedOrg);

/**
 * Get the current organization's tier by finding the matching plan.
 * The org has planid (e.g., 'identity_plus_v1_monthly') but we need
 * the tier (e.g., 'single_team') for comparison with available plans.
 */
const currentTier = computed((): string => {
  const planid = selectedOrg.value?.planid;
  if (!planid) return 'free';

  // Find the plan that matches the org's planid to get its tier
  const matchingPlan = plans.value.find(p => p.id === planid);
  if (matchingPlan) return matchingPlan.tier;

  // Fallback: try to infer tier from planid naming convention
  // e.g., 'identity_plus_v1_monthly' -> look for known tier patterns
  if (planid.includes('multi_team') || planid.includes('team_plus')) return 'multi_team';
  if (planid.includes('single_team') || planid.includes('identity_plus')) return 'single_team';

  return 'free';
});

// Filter plans by selected billing interval
const filteredPlans = computed(() => plans.value.filter(plan => plan.interval === billingInterval.value));

/**
 * Combined loading state for the component
 */
const isLoadingContent = computed(() => isLoadingPlans.value || isLoadingDefinitions.value || isLoadingOrg.value);

/**
 * Check if plan should show "Most Popular" badge.
 * Uses API-provided is_popular flag if available.
 */
const isPlanRecommended = (plan: BillingPlan): boolean => plan.is_popular ?? plan.tier === 'single_team';

const isPlanCurrent = (plan: BillingPlan): boolean => plan.tier === currentTier.value;

const canUpgrade = (plan: BillingPlan): boolean => {
  if (currentTier.value === 'free') return plan.tier !== 'free';
  if (currentTier.value === 'single_team') return plan.tier === 'multi_team';
  return false;
};

const canDowngrade = (plan: BillingPlan): boolean => {
  if (currentTier.value === 'multi_team') return plan.tier !== 'multi_team';
  if (currentTier.value === 'single_team') return plan.tier === 'free';
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
  if (isPlanCurrent(plan) || !selectedOrg.value?.extid || plan.tier === 'free') return;

  // Clear any previous messages
  error.value = '';
  successMessage.value = '';

  // If user has active subscription, show plan change modal instead of checkout
  if (hasActiveSubscription.value) {
    targetPlan.value = plan;
    showPlanChangeModal.value = true;
    return;
  }

  // New subscriber flow: redirect to Stripe Checkout
  isCreatingCheckout.value = true;

  try {
    // Pass plan object - service derives product from plan.id
    const response = await BillingService.createCheckoutSession(
      selectedOrg.value.extid,
      { id: plan.id, interval: plan.interval }
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

const handlePlanChangeClose = () => {
  showPlanChangeModal.value = false;
  targetPlan.value = null;
};

const handlePlanChangeSuccess = async (newPlan: string) => {
  showPlanChangeModal.value = false;
  targetPlan.value = null;
  successMessage.value = `Successfully switched to ${newPlan}`;

  // Refresh subscription status and organization data
  if (orgExtid.value) {
    await loadSubscriptionStatus(orgExtid.value);
    // Refresh org data
    const org = await organizationStore.fetchOrganization(orgExtid.value);
    selectedOrg.value = org;
  }
};

// Helper to load subscription status with error handling
const loadSubscriptionStatus = async (extid: string) => {
  try {
    subscriptionStatus.value = await BillingService.getSubscriptionStatus(extid);
  } catch (_err) {
    // Non-fatal: user may not have a subscription yet
    console.log('[PlanSelector] No active subscription found');
  }
};

onMounted(async () => {
  try {
    isLoadingOrg.value = true;

    // Load entitlement definitions and plans in parallel
    await Promise.all([
      initDefinitions(),
      loadPlans(),
    ]);

    // Load organization data using extid from URL
    if (orgExtid.value) {
      const org = await organizationStore.fetchOrganization(orgExtid.value);
      selectedOrg.value = org;
      // Load subscription status to determine checkout vs plan change flow
      await loadSubscriptionStatus(orgExtid.value);
    }

    // Check for product/interval query params (from billing redirect flow)
    // These come from /pricing page -> signup/login -> redirect here
    const productParam = route.query.product as string;
    const intervalParam = route.query.interval as string;

    if (productParam) {
      // Set billing interval from query param
      if (intervalParam === 'yearly' || intervalParam === 'year') {
        billingInterval.value = 'year';
      } else {
        billingInterval.value = 'month';
      }

      // Find the matching plan based on product and interval
      // Product is like 'identity_plus_v1', plan.id is like 'identity_plus_v1_monthly'
      const intervalSuffix = billingInterval.value === 'year' ? 'yearly' : 'monthly';
      const expectedPlanId = `${productParam}_${intervalSuffix}`;

      // Find plan by exact match or prefix match
      const matchingPlan = plans.value.find(
        p => p.id === expectedPlanId || p.id.startsWith(productParam)
      );

      if (matchingPlan) {
        suggestedPlanId.value = matchingPlan.id;
      }
    }

    // Legacy: Check for upgrade_to query param (backwards compatibility)
    const upgradeToParam = route.query.upgrade_to as string;
    if (upgradeToParam && !suggestedPlanId.value) {
      suggestedPlanId.value = upgradeToParam;
    }
  } catch (err) {
    const classified = classifyError(err);
    error.value = classified.message || 'Failed to load billing data';
    console.error('[PlanSelector] Error loading billing data:', err);
  } finally {
    isLoadingOrg.value = false;
  }
});
</script>

<template>
  <BillingLayout>
    <div class="space-y-8">
      <!-- Billing Interval Toggle -->
      <div class="flex items-center justify-center gap-3"
role="group"
aria-label="Billing interval">
        <button
          @click="billingInterval = 'month'"
          :aria-pressed="billingInterval === 'month'"
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
          :aria-pressed="billingInterval === 'year'"
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

      <!-- Success Message -->
      <div v-if="successMessage"
class="rounded-md bg-green-50 p-4 dark:bg-green-900/20"
role="status"
aria-live="polite">
        <div class="flex">
          <OIcon
            collection="heroicons"
            name="check-circle"
            class="size-5 text-green-400"
            aria-hidden="true" />
          <div class="ml-3">
            <p class="text-sm font-medium text-green-800 dark:text-green-200">{{ successMessage }}</p>
          </div>
        </div>
      </div>

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
          {{ t('web.billing.plans.no_plans_available', { interval: billingInterval === 'year' ? t('web.billing.plans.yearly').toLowerCase() : t('web.billing.plans.monthly').toLowerCase() }) }}
        </p>
      </div>

      <!-- Plan Cards -->
      <div v-else class="mx-auto grid max-w-[1600px] grid-cols-1 gap-6 sm:grid-cols-2 xl:grid-cols-4">
        <PlanCard
          v-for="plan in filteredPlans"
          :key="plan.id"
          :plan="plan"
          :is-current="isPlanCurrent(plan)"
          :is-recommended="isPlanRecommended(plan)"
          :is-suggested="suggestedPlanId === plan.id"
          :button-label="getButtonLabel(plan)"
          :button-disabled="isPlanCurrent(plan) || isCreatingCheckout || plan.id === 'free'"
          :is-processing="isCreatingCheckout && !isPlanCurrent(plan)"
          @select="handlePlanSelect" />
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

    <!-- Plan Change Modal (for existing subscribers) -->
    <PlanChangeModal
      :open="showPlanChangeModal"
      :org-ext-id="selectedOrg?.extid ?? ''"
      :current-plan="currentPlanForModal"
      :target-plan="targetPlan"
      @close="handlePlanChangeClose"
      @success="handlePlanChangeSuccess"
    />
  </BillingLayout>
</template>
