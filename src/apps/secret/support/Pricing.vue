<!-- src/apps/secret/support/Pricing.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import { RouterLink, useRoute } from 'vue-router';
  import BasicFormAlerts from '@/shared/components/forms/BasicFormAlerts.vue';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import PlanCard from '@/shared/components/billing/PlanCard.vue';
  import FeedbackToggle from '@/shared/components/ui/FeedbackToggle.vue';
  import { classifyError } from '@/schemas/errors';
  import { BillingService, type Plan as BillingPlan } from '@/services/billing.service';
  import type { BillingInterval } from '@/types/billing';
  import { computed, onMounted, ref, watch } from 'vue';

  const { t } = useI18n();
  const route = useRoute();

  // Map URL interval slugs to internal billing interval
  // Supports: month, monthly -> 'month' and year, yearly, annual -> 'year'
  const INTERVAL_MAP: Record<string, BillingInterval> = {
    month: 'month',
    monthly: 'month',
    year: 'year',
    yearly: 'year',
    annual: 'year',
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
  const filteredPlans = computed(() =>
    plans.value.filter((plan) => plan.interval === billingInterval.value)
  );

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
    planId.replace(/_(monthly|yearly|month|year)$/i, '');
  /**
   * Get the interval name for query params from plan interval.
   * Uses 'monthly' or 'yearly' format for URL query params.
   */
  const getIntervalForQuery = (plan: BillingPlan): string =>
    plan.interval === 'year' ? 'yearly' : 'monthly';

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
          {{ t('web.billing.secure_links_stronger_connections') }}
        </h1>
        <p class="mx-auto max-w-2xl text-lg text-gray-600 dark:text-gray-400">
          {{ t('web.billing.secure_your_brand_and_build_customer_trust_with_') }}
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
      <BasicFormAlerts
        v-if="error"
        :error="error" />

      <!-- Loading State -->
      <div
        v-if="isLoadingPlans"
        class="flex items-center justify-center py-12">
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
          {{
            t('web.billing.plans.no_plans_available', {
              interval:
                billingInterval === 'year'
                  ? t('web.billing.plans.yearly').toLowerCase()
                  : t('web.billing.plans.monthly').toLowerCase(),
            })
          }}
        </p>
      </div>

      <!-- Plan Cards -->
      <div
        v-else
        class="mx-auto flex max-w-[1400px] flex-wrap items-stretch justify-center gap-6">
        <PlanCard
          v-for="plan in filteredPlans"
          :key="plan.id"
          :plan="plan"
          :is-recommended="isPlanRecommended(plan)"
          :is-highlighted="isPlanHighlighted(plan)"
          :button-label="getCtaLabel(plan)"
          class="w-full max-w-sm sm:w-80">
          <template #action="{ plan: currentPlan }">
            <RouterLink
              :to="getSignupUrl(currentPlan)"
              :class="[
                'block w-full rounded-md px-4 py-2 text-center text-sm font-semibold transition-colors',
                isPlanRecommended(currentPlan) || isPlanHighlighted(currentPlan)
                  ? 'bg-brand-600 text-white hover:bg-brand-500 dark:bg-brand-500 dark:hover:bg-brand-400'
                  : 'bg-white text-gray-700 ring-1 ring-inset ring-gray-300 hover:bg-gray-50 dark:bg-gray-800 dark:text-gray-300 dark:ring-gray-600 dark:hover:bg-gray-700',
              ]">
              {{ getCtaLabel(currentPlan) }}
            </RouterLink>
          </template>
        </PlanCard>
      </div>

      <!-- Custom Needs Section -->
      <div
        class="mt-12 rounded-lg border border-gray-200 bg-gray-50 p-8 text-center dark:border-gray-700 dark:bg-gray-900/50">
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
