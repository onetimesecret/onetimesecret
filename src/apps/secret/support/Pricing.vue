<!-- src/apps/secret/support/Pricing.vue -->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import { RouterLink, useRoute } from 'vue-router';
import BasicFormAlerts from '@/shared/components/forms/BasicFormAlerts.vue';
import OIcon from '@/shared/components/icons/OIcon.vue';
import FeedbackToggle from '@/shared/components/ui/FeedbackToggle.vue';
import { classifyError } from '@/schemas/errors';
import { BillingService, type Plan as BillingPlan } from '@/services/billing.service';
import type { BillingInterval } from '@/types/billing';
import { formatCurrency } from '@/types/billing';
import { computed, onMounted, ref, watch } from 'vue';

const { t } = useI18n();
const route = useRoute();

// Map URL interval slugs to internal billing interval
// Supports: month, monthly -> 'month' and year, yearly, annual -> 'year'
const INTERVAL_MAP: Record<string, BillingInterval> = {
  'month': 'month',
  'monthly': 'month',
  'year': 'year',
  'yearly': 'year',
  'annual': 'year',
};

// Get billing interval from URL param or default to month
const getInitialBillingInterval = (): BillingInterval => {
  const intervalParam = route.params.interval as string | undefined;
  if (intervalParam && INTERVAL_MAP[intervalParam.toLowerCase()]) {
    return INTERVAL_MAP[intervalParam.toLowerCase()];
  }
  return 'month';
};

// Get highlighted product from URL param (e.g., 'identity_plus', 'team_plus')
// This will be matched against plan.id prefix
const highlightedProduct = computed((): string | null => {
  const productParam = route.params.product as string | undefined;
  if (productParam) {
    return productParam.toLowerCase();
  }
  return null;
});

const billingInterval = ref<BillingInterval>(getInitialBillingInterval());
const isLoadingPlans = ref(false);
const error = ref('');

// Watch for route param changes to update billing interval
watch(
  () => route.params.interval,
  (newInterval) => {
    if (newInterval && typeof newInterval === 'string') {
      const mapped = INTERVAL_MAP[newInterval.toLowerCase()];
      if (mapped) {
        billingInterval.value = mapped;
      }
    }
  },
  { immediate: true }
);

// Plans loaded from API
const plans = ref<BillingPlan[]>([]);

// Filter plans by selected billing interval
const filteredPlans = computed(() => plans.value.filter(plan => plan.interval === billingInterval.value));

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
 * Uses API-provided is_popular flag.
 */
const isPlanRecommended = (plan: BillingPlan): boolean => plan.is_popular === true;

/**
 * Check if plan should be highlighted based on URL product parameter.
 * Matches the product param against the plan ID prefix.
 * Example: product='identity_plus' matches plan.id='identity_plus_v1_monthly'
 */
const isPlanHighlighted = (plan: BillingPlan): boolean => {
  if (!highlightedProduct.value) return false;
  return plan.id.toLowerCase().startsWith(highlightedProduct.value);
};

/**
 * Determine CTA text based on plan tier
 */
const getCtaLabel = (plan: BillingPlan): string => {
  if (plan.tier === 'free') return t('web.pricing.get_started_free');
  return t('web.pricing.start_trial');
};

/**
 * Extract product name from plan ID for signup query params.
 * Plan ID format: {product}_v{version}_{interval}
 * Example: identity_plus_v1_monthly -> identity_plus_v1
 *
 * @param planId - The full plan ID (e.g., 'identity_plus_v1_monthly')
 * @returns Product identifier without interval (e.g., 'identity_plus_v1')
 */
const extractProductFromPlanId = (planId: string): string =>
  // Remove the interval suffix (monthly, yearly, etc.)
   planId.replace(/_(monthly|yearly|month|year)$/i, '')
;

/**
 * Get the interval name for query params from plan interval.
 * Uses 'monthly' or 'yearly' format for URL query params.
 */
const getIntervalForQuery = (plan: BillingPlan): string => plan.interval === 'year' ? 'yearly' : 'monthly';

/**
 * Build signup URL with product and interval query params.
 * Free plans go to /signup without params.
 * Paid plans include product and interval for checkout flow.
 */
const getSignupUrl = (plan: BillingPlan): string => {
  if (plan.tier === 'free') {
    return '/signup';
  }
  const product = extractProductFromPlanId(plan.id);
  const interval = getIntervalForQuery(plan);
  return `/signup?product=${encodeURIComponent(product)}&interval=${encodeURIComponent(interval)}`;
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
    console.error('[Pricing] Error loading plans:', err);
  } finally {
    isLoadingPlans.value = false;
  }
};

onMounted(async () => {
  await loadPlans();
});
</script>

<template>
  <div class="container mx-auto max-w-6xl px-4 py-8">
    <section aria-labelledby="pricing-title">
      <!-- Header -->
      <div class="mb-8 text-center">
        <h1
          id="pricing-title"
          class="mb-3 text-3xl font-bold text-gray-900 dark:text-gray-100">
          {{ t('web.pricing.title') }}
        </h1>
        <p class="mx-auto max-w-2xl text-lg text-gray-600 dark:text-gray-400">
          {{ t('web.pricing.subtitle') }}
        </p>
      </div>

      <!-- Billing Interval Toggle -->
      <div
        class="mb-8 flex items-center justify-center gap-3"
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

      <!-- Error Alert -->
      <BasicFormAlerts v-if="error" :error="error" />

      <!-- Loading State -->
      <div v-if="isLoadingPlans" class="flex items-center justify-center py-12">
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
      <div
        v-else-if="filteredPlans.length === 0 && !error"
        class="rounded-lg border border-gray-200 bg-gray-50 p-8 text-center dark:border-gray-700 dark:bg-gray-900/50">
        <p class="text-gray-600 dark:text-gray-400">
          {{ t('web.billing.plans.no_plans_available', { interval: billingInterval === 'year' ? t('web.billing.plans.yearly').toLowerCase() : t('web.billing.plans.monthly').toLowerCase() }) }}
        </p>
      </div>

      <!-- Plan Cards -->
      <div v-else class="mx-auto flex max-w-[1400px] flex-wrap items-stretch justify-center gap-6">
        <div
          v-for="plan in filteredPlans"
          :key="plan.id"
          :class="[
            'relative flex w-full max-w-sm flex-col rounded-2xl border bg-white transition-all hover:shadow-lg dark:bg-gray-800 sm:w-80',
            isPlanHighlighted(plan)
              ? 'border-yellow-500 ring-2 ring-yellow-500 shadow-xl md:scale-105 dark:border-yellow-400 dark:ring-yellow-400'
              : isPlanRecommended(plan)
                ? 'border-brand-500 ring-2 ring-brand-500 shadow-xl md:scale-105 dark:border-brand-400 dark:ring-brand-400'
                : 'border-gray-200 shadow-sm dark:border-gray-700',
          ]"
          :style="{ zIndex: isPlanHighlighted(plan) || isPlanRecommended(plan) ? 10 : 1 }">
          <!-- Highlighted Badge (from URL) -->
          <div
            v-if="isPlanHighlighted(plan)"
            class="absolute -top-5 left-1/2 -translate-x-1/2 rounded-full bg-yellow-500 px-3 py-1 text-xs font-semibold text-white">
            {{ t('web.pricing.recommended_for_you') }}
          </div>
          <!-- Recommended Badge -->
          <div
            v-else-if="isPlanRecommended(plan)"
            class="absolute -top-5 left-1/2 -translate-x-1/2 rounded-full bg-brand-600 px-3 py-1 text-xs font-semibold text-white dark:bg-brand-500">
            {{ t('web.billing.plans.most_popular') }}
          </div>

          <div class="flex-1 p-6">
            <!-- Plan Header -->
            <div class="mb-4">
              <div class="flex items-center gap-2">
                <h2 class="text-xl font-bold text-gray-900 dark:text-white">
                  {{ plan.name }}
                </h2>
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
                    aria-hidden="true" />
                  <span>{{ t(feature) }}</span>
                </li>
              </ul>
            </div>
          </div>

          <!-- Action Button -->
          <div class="border-t border-gray-200 p-6 dark:border-gray-700">
            <RouterLink
              :to="getSignupUrl(plan)"
              :class="[
                'block w-full rounded-md px-4 py-2 text-center text-sm font-semibold transition-colors',
                isPlanRecommended(plan) || isPlanHighlighted(plan)
                  ? 'bg-brand-600 text-white hover:bg-brand-500 dark:bg-brand-500 dark:hover:bg-brand-400'
                  : 'bg-white text-gray-700 ring-1 ring-inset ring-gray-300 hover:bg-gray-50 dark:bg-gray-800 dark:text-gray-300 dark:ring-gray-600 dark:hover:bg-gray-700',
              ]">
              {{ getCtaLabel(plan) }}
            </RouterLink>
          </div>
        </div>
      </div>

      <!-- Custom Needs Section -->
      <div class="mt-12 rounded-lg border border-gray-200 bg-gray-50 p-8 text-center dark:border-gray-700 dark:bg-gray-900/50">
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

      <!-- Sign in prompt for existing users -->
      <div class="mt-8 text-center">
        <p class="text-sm text-gray-600 dark:text-gray-400">
          {{ t('web.pricing.already_have_account') }}
          <RouterLink
            to="/signin"
            class="font-medium text-brand-600 hover:text-brand-500 dark:text-brand-400 dark:hover:text-brand-300">
            {{ t('web.pricing.sign_in') }}
          </RouterLink>
        </p>
      </div>
    </section>
  </div>
</template>
