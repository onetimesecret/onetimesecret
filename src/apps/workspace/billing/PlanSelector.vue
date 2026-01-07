<!-- src/apps/workspace/billing/PlanSelector.vue -->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import BasicFormAlerts from '@/shared/components/forms/BasicFormAlerts.vue';
import FeedbackToggle from '@/shared/components/ui/FeedbackToggle.vue';
import OIcon from '@/shared/components/icons/OIcon.vue';
import PlanChangeModal from './PlanChangeModal.vue';
import { useEntitlements } from '@/shared/composables/useEntitlements';
import { classifyError } from '@/schemas/errors';
import { BillingService, type Plan as BillingPlan, type SubscriptionStatusResponse } from '@/services/billing.service';
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
const successMessage = ref('');

// Plans loaded from API
const plans = ref<BillingPlan[]>([]);

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

const organizations = computed(() => organizationStore.organizations);
const selectedOrg = computed(() =>
  organizations.value.find(org => org.id === selectedOrgId.value)
);

// Use entitlements composable for definitions loading
const selectedOrgRef = computed(() => selectedOrg.value ?? null);
const {
  initDefinitions,
  isLoadingDefinitions,
  definitionsError,
} = useEntitlements(selectedOrgRef);

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
 * Get the teams limit for a plan, handling unlimited (-1)
 * Note: Prefixed with _ as currently unused (template section commented out)
 */
const _getTeamsLimit = (plan: BillingPlan): number | string => {
  const limit = plan.limits?.['teams.max'] ?? plan.limits?.teams ?? 1;
  return limit === -1 ? '∞' : limit;
};

/**
 * Get the members per team limit for a plan, handling unlimited (-1)
 * Note: Prefixed with _ as currently unused (template section commented out)
 */
const _getMembersLimit = (plan: BillingPlan): number | string => {
  const limit = plan.limits?.['members_per_team.max'] ?? plan.limits?.members_per_team ?? 1;
  return limit === -1 ? '∞' : limit;
};

/**
 * Combined loading state for the component
 */
const isLoadingContent = computed(() => isLoadingPlans.value || isLoadingDefinitions.value);

/**
 * Tier hierarchy for inheritance (lower index = lower tier).
 * Higher tiers inherit from lower tiers, so:
 * - free: shows all its features (no base)
 * - single_team: shows "Everything in Free, plus:" + new features
 * - multi_team: shows "Everything in Single Team, plus:" + new features
 */
const TIER_HIERARCHY = ['free', 'single_team', 'multi_team'] as const;

/**
 * Get the base plan for inheritance display.
 * Higher tiers reference their immediate lower tier.
 */
const getBasePlan = (plan: BillingPlan): BillingPlan | undefined => {
  const tierIndex = TIER_HIERARCHY.indexOf(plan.tier as (typeof TIER_HIERARCHY)[number]);
  if (tierIndex <= 0) return undefined; // Lowest tier (free) has no base

  const baseTier = TIER_HIERARCHY[tierIndex - 1];
  return filteredPlans.value.find(p => p.tier === baseTier && p.interval === plan.interval);
};

/**
 * Get only NEW features for this plan (excluding base plan features).
 * For lowest tier plans, shows all features.
 * Features are i18n locale keys like 'web.billing.features.custom_domains'.
 */
const getNewFeatures = (plan: BillingPlan): string[] => {
  const basePlan = getBasePlan(plan);
  if (!basePlan) return plan.features; // Show all for lowest tier

  // Filter out features that exist in base plan
  return plan.features.filter(feat => !basePlan.features.includes(feat));
};

/**
 * Get the monthly price for display.
 * Uses API-provided monthly_equivalent_amount for yearly plans if available.
 */
const getPlanPricePerMonth = (plan: BillingPlan): number => {
  if (plan.interval === 'year') {
    return plan.monthly_equivalent_amount ?? Math.floor(plan.amount / 12);
  }
  return plan.amount;
};

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
  if (isPlanCurrent(plan) || !selectedOrgId.value || plan.tier === 'free') return;

  const selectedOrganization = organizations.value.find(org => org.id === selectedOrgId.value);
  if (!selectedOrganization?.extid) {
    error.value = 'Organization not found';
    return;
  }

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

const handlePlanChangeClose = () => {
  showPlanChangeModal.value = false;
  targetPlan.value = null;
};

const handlePlanChangeSuccess = async (newPlan: string) => {
  showPlanChangeModal.value = false;
  targetPlan.value = null;
  successMessage.value = `Successfully switched to ${newPlan}`;

  // Refresh subscription status and organization data
  const selectedOrganization = organizations.value.find(org => org.id === selectedOrgId.value);
  if (selectedOrganization) {
    await loadSubscriptionStatus(selectedOrganization);
    await organizationStore.fetchOrganizations();
  }
};

// Helper to load subscription status with error handling
const loadSubscriptionStatus = async (org: { extid?: string }) => {
  if (!org.extid) return;
  try {
    subscriptionStatus.value = await BillingService.getSubscriptionStatus(org.extid);
  } catch (_err) {
    // Non-fatal: user may not have a subscription yet
    console.log('[PlanSelector] No active subscription found');
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
      // Load subscription status to determine checkout vs plan change flow
      await loadSubscriptionStatus(organizations.value[0]);
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
          {{ t('web.billing.plans.subtitle') }}
        </p>
      </div>

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
            {{ t('web.billing.plans.most_popular') }}
          </div>

          <!-- Suggested Badge -->
          <div
            v-if="suggestedPlanId === plan.id"
            class="absolute -top-5 right-4 rounded-full bg-yellow-500 px-3 py-1 text-xs font-semibold text-white">
            {{ t('web.billing.plans.suggested') }}
          </div>

          <!-- Current Badge - positioned prominently like Most Popular -->
          <div
            v-if="isPlanCurrent(plan)"
            class="absolute -top-3 right-4 z-10 rounded-full border-2 border-green-600 bg-green-600 px-3 py-1 text-xs font-semibold text-white shadow-md dark:border-green-500 dark:bg-green-500">
            {{ t('web.billing.plans.current_badge') }}
          </div>

          <div class="flex-1 p-6">
            <!-- Plan Header -->
            <div class="mb-4">
              <div class="flex items-center gap-2">
                <h3 class="text-xl font-bold text-gray-900 dark:text-white" :data-plan-id="plan.id">
                  {{ plan.name }}
                </h3>
                <span
                  v-if="plan.plan_name_label"
                  class="rounded-full bg-gray-100 px-2 py-0.5 text-xs font-medium text-gray-600 dark:bg-gray-700 dark:text-gray-300">
                  {{ t(plan.plan_name_label) }}
                </span>
              </div>
            </div>

            <!-- Price -->
            <div class="mb-6">
              <div class="flex items-baseline gap-2">
                <span class="text-4xl font-bold text-gray-900 dark:text-white">
                  {{ formatCurrency(getPlanPricePerMonth(plan), plan.currency) }}
                </span>
                <span class="text-sm text-gray-500 dark:text-gray-400">
                  {{ t('web.billing.plans.per_month') }}
                </span>
              </div>
              <p v-if="plan.interval === 'year' && plan.amount > 0" class="mt-1 text-sm font-medium text-gray-500 dark:text-gray-400">
                {{ t('web.billing.plans.yearly') }}: {{ formatCurrency(plan.amount, plan.currency) }}
              </p>
            </div>

            <!-- Team & Member Limits -->
            <!-- <div class="mb-6 space-y-2 text-sm">
              <p class="text-gray-700 dark:text-gray-300">
                {{ typeof getTeamsLimit(plan) === 'string'
                  ? t('web.billing.plans.unlimited_teams')
                  : t('web.billing.plans.teams_limit', { count: getTeamsLimit(plan) })
                }}
              </p>
              <p class="text-gray-700 dark:text-gray-300">
                {{ typeof getMembersLimit(plan) === 'string'
                  ? t('web.billing.plans.unlimited_members')
                  : t('web.billing.plans.members_limit', { count: getMembersLimit(plan) })
                }}
              </p>
            </div> -->

            <!-- Features -->
            <div class="space-y-3">
              <p class="text-sm font-semibold text-gray-900 dark:text-white">
                {{ t('web.billing.plans.features') }}
              </p>

              <!-- Show base plan reference for higher tiers -->
              <p v-if="getBasePlan(plan)" class="text-xs font-medium text-gray-500 dark:text-gray-400">
                ✓ {{ t('web.billing.plans.everything_in', { plan: getBasePlan(plan)?.name }) }}
              </p>

              <ul class="space-y-2">
                <li
                  v-for="feature in getNewFeatures(plan)"
                  :key="feature"
                  class="flex items-start gap-2 text-sm text-gray-700 dark:text-gray-300">
                  <OIcon
                    collection="heroicons"
                    name="check"
                    class="mt-0.5 size-5 shrink-0 text-green-500 dark:text-green-400"
                    aria-hidden="true" />
                  <span>{{ t(feature) }}</span>
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

    <!-- Plan Change Modal (for existing subscribers) -->
    <PlanChangeModal
      :open="showPlanChangeModal"
      :org-ext-id="selectedOrg?.extid ?? ''"
      :current-plan="currentPlanForModal"
      :target-plan="targetPlan"
      @close="handlePlanChangeClose"
      @success="handlePlanChangeSuccess"
    />
  </div>
</template>
