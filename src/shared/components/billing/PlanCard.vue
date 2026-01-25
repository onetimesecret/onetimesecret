<!-- src/shared/components/billing/PlanCard.vue -->
<!--
  Shared plan card component for pricing/plans pages.
  Displays plan details, features, and action button.
-->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import type { Plan as BillingPlan } from '@/services/billing.service';
  import { formatCurrency } from '@/types/billing';
  import { computed } from 'vue';

  const props = defineProps<{
    plan: BillingPlan;
    /** Whether this plan is the user's current plan */
    isCurrent?: boolean;
    /** Whether this plan is recommended/popular */
    isRecommended?: boolean;
    /** Whether this plan is highlighted (e.g., from URL param) */
    isHighlighted?: boolean;
    /** Whether this plan is suggested (e.g., from redirect flow) */
    isSuggested?: boolean;
    /** Button label text */
    buttonLabel: string;
    /** Whether the action button should be disabled */
    buttonDisabled?: boolean;
    /** Whether the component is in a loading/processing state */
    isProcessing?: boolean;
  }>();

  const emit = defineEmits<{
    select: [plan: BillingPlan];
  }>();

  const { t } = useI18n();

  /**
   * Get the monthly price for display.
   * Uses API-provided monthly_equivalent_amount for yearly plans if available.
   */
  const pricePerMonth = computed((): number => {
    if (props.plan.interval === 'year') {
      return props.plan.monthly_equivalent_amount ?? Math.floor(props.plan.amount / 12);
    }
    return props.plan.amount;
  });

  /**
   * Determine card styling based on state
   */
  const cardClasses = computed(() => {
    let variantClasses = 'border-gray-200 shadow-sm dark:border-gray-700';

    if (props.isHighlighted) {
      variantClasses =
        'border-yellow-500 ring-2 ring-yellow-500 shadow-xl md:scale-105 dark:border-yellow-400 dark:ring-yellow-400';
    } else if (props.isRecommended) {
      variantClasses =
        'border-brand-500 ring-2 ring-brand-500 shadow-xl md:scale-105 dark:border-brand-400 dark:ring-brand-400';
    }

    return [
      'relative flex w-full flex-col rounded-2xl border bg-white transition-all hover:shadow-lg dark:bg-gray-800',
      variantClasses,
      props.isSuggested && !props.isHighlighted ? 'ring-2 ring-yellow-500' : '',
    ];
  });

  const cardZIndex = computed(() => (props.isHighlighted || props.isRecommended ? 10 : 1));

  const buttonClasses = computed(() => {
    if (props.isCurrent) {
      return 'cursor-default bg-gray-100 text-gray-700 dark:bg-gray-700 dark:text-gray-300';
    }
    if (props.isRecommended || props.isHighlighted) {
      return 'bg-brand-600 text-white hover:bg-brand-500 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-brand-500 dark:hover:bg-brand-400';
    }
    return 'bg-white text-gray-700 ring-1 ring-inset ring-gray-300 hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-gray-800 dark:text-gray-300 dark:ring-gray-600 dark:hover:bg-gray-700';
  });

  const handleSelect = () => {
    emit('select', props.plan);
  };
</script>

<template>
  <div
    :class="cardClasses"
    :style="{ zIndex: cardZIndex }">
    <!-- Highlighted Badge (from URL) -->
    <div
      v-if="isHighlighted"
      class="absolute -top-5 left-1/2 -translate-x-1/2 rounded-full bg-yellow-500 px-3 py-1 text-xs font-semibold text-white">
      {{ t('web.pricing.recommended_for_you') }}
    </div>

    <!-- Recommended Badge -->
    <div
      v-else-if="isRecommended"
      class="absolute -top-5 left-1/2 -translate-x-1/2 rounded-full bg-brand-600 px-3 py-1 text-xs font-semibold text-white dark:bg-brand-500">
      {{ t('web.billing.plans.most_popular') }}
    </div>

    <!-- Suggested Badge -->
    <div
      v-if="isSuggested && !isHighlighted"
      class="absolute -top-5 right-4 rounded-full bg-yellow-500 px-3 py-1 text-xs font-semibold text-white">
      {{ t('web.billing.plans.suggested') }}
    </div>

    <!-- Current Badge -->
    <div
      v-if="isCurrent"
      class="absolute -top-3 right-4 z-10 rounded-full border-2 border-brandcomp-600 bg-brandcomp-600 px-3 py-1 text-xs font-semibold text-white shadow-md dark:border-brandcomp-500 dark:bg-brandcomp-500">
      {{ t('web.billing.plans.current_badge') }}
    </div>

    <div class="flex-1 p-6">
      <!-- Plan Header -->
      <div class="mb-4">
        <div class="flex items-center gap-2">
          <h3
            class="text-xl font-bold text-gray-900 dark:text-white"
            :data-plan-id="plan.id">
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
          <!-- All tiers display formatted currency for consistency -->
          <span class="font-brand text-4xl font-bold text-gray-900 dark:text-white">
            {{ formatCurrency(pricePerMonth, plan.currency) }}
          </span>
          <span
            v-if="plan.tier !== 'free'"
            class="text-sm text-gray-500 dark:text-gray-400">
            {{ t('web.billing.plans.per_month') }}
          </span>
        </div>
        <p
          v-if="plan.interval === 'year' && plan.amount > 0"
          class="mt-1 text-sm font-medium text-gray-500 dark:text-gray-400">
          {{ t('web.billing.plans.yearly') }}: {{ formatCurrency(plan.amount, plan.currency) }}
        </p>
      </div>

      <!-- Features -->
      <div class="space-y-3">
        <p class="text-sm font-semibold text-gray-900 dark:text-white">
          {{ t('web.billing.plans.features') }}
        </p>

        <!-- "Includes everything in X, plus:" header when plan includes another -->
        <p
          v-if="plan.includes_plan_name"
          class="text-sm italic text-gray-600 dark:text-gray-400">
          {{ t('web.billing.plans.everything_in', { plan: plan.includes_plan_name }) }}
        </p>

        <ul class="space-y-2">
          <li
            v-for="feature in plan.features"
            :key="feature"
            class="flex items-start gap-2 text-sm text-gray-700 dark:text-gray-300">
            <OIcon
              collection="heroicons"
              name="check"
              class="mt-0.5 size-5 shrink-0 text-brandcomp-500 dark:text-brandcomp-400"
              aria-hidden="true" />
            <span>{{ t(feature) }}</span>
          </li>
        </ul>
      </div>
    </div>

    <!-- Action Button -->
    <div class="border-t border-gray-200 p-6 dark:border-gray-700">
      <slot
        name="action"
        :plan="plan"
        :handle-select="handleSelect">
        <button
          @click="handleSelect"
          :disabled="buttonDisabled"
          :class="[
            'w-full rounded-md px-4 py-2 text-sm font-semibold transition-colors',
            buttonClasses,
          ]">
          <span v-if="isProcessing">
            {{ t('web.COMMON.processing') }}
          </span>
          <span v-else>
            {{ buttonLabel }}
          </span>
        </button>
      </slot>
    </div>
  </div>
</template>
