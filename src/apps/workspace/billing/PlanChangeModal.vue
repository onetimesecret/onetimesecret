<!-- src/apps/workspace/billing/PlanChangeModal.vue -->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import OIcon from '@/shared/components/icons/OIcon.vue';
import { Dialog, DialogPanel, DialogTitle, TransitionChild, TransitionRoot } from '@headlessui/vue';
import { BillingService, type Plan as BillingPlan, type PlanChangePreviewResponse } from '@/services/billing.service';
import { formatCurrency } from '@/types/billing';
import { classifyError } from '@/schemas/errors';
import { computed, ref, watch } from 'vue';

const { t } = useI18n();

const props = defineProps<{
  open: boolean;
  orgExtId: string;
  currentPlan: BillingPlan | null;
  targetPlan: BillingPlan | null;
}>();

const emit = defineEmits<{
  (e: 'close'): void;
  (e: 'success', newPlan: string): void;
}>();

// State
const isLoadingPreview = ref(false);
const isChangingPlan = ref(false);
const preview = ref<PlanChangePreviewResponse | null>(null);
const error = ref('');

// Computed
// Determine if this is an upgrade based on price (industry standard approach).
// Higher price = upgrade, lower price = downgrade.
// Falls back to display_order for same-price plans (e.g., interval changes).
const isUpgrade = computed(() => {
  if (!props.currentPlan || !props.targetPlan) return false;

  // Primary: Compare by amount (monthly-equivalent for fair comparison)
  const currentAmount = props.currentPlan.monthly_equivalent_amount ?? props.currentPlan.amount;
  const targetAmount = props.targetPlan.monthly_equivalent_amount ?? props.targetPlan.amount;

  if (targetAmount !== currentAmount) {
    return targetAmount > currentAmount;
  }

  // Fallback: Compare by display_order for same-price plans
  return props.targetPlan.display_order > props.currentPlan.display_order;
});

const dialogTitle = computed(() => {
  const planName = props.targetPlan?.name ?? '';
  return isUpgrade.value
    ? t('web.billing.plans.upgrade_to', { plan: planName })
    : t('web.billing.plans.downgrade_to', { plan: planName });
});

const confirmButtonLabel = computed(() =>
  isUpgrade.value ? t('web.billing.plans.confirm_upgrade') : t('web.billing.plans.confirm_downgrade')
);

const formattedNextBillingDate = computed(() => {
  if (!preview.value?.next_billing_date) return null;
  return new Date(preview.value.next_billing_date * 1000).toLocaleDateString(undefined, {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  });
});

// Check if API returns the new breakdown fields
const hasNewProrationFields = computed(() => {
  if (!preview.value) return false;
  return preview.value.immediate_amount !== undefined && preview.value.next_period_amount !== undefined;
});

// Determine if this is a downgrade with significant credit that exceeds or equals next bill
const showCreditBreakdown = computed(() => {
  if (!preview.value || isUpgrade.value) return false;

  // Show breakdown when there's credit being applied
  const credit = preview.value.credit_applied ?? 0;
  const nextBill = preview.value.next_period_amount ?? preview.value.new_plan.amount;

  return credit > 0 && credit >= nextBill;
});

// Calculate remaining credit after next bill is covered
const remainingCreditAfterBill = computed(() => {
  if (!preview.value) return 0;

  // Use API-provided remaining_credit if available
  if (preview.value.remaining_credit !== undefined) {
    return preview.value.remaining_credit;
  }

  // Calculate from ending_balance (negative = credit)
  if (preview.value.ending_balance !== undefined && preview.value.ending_balance < 0) {
    return Math.abs(preview.value.ending_balance);
  }

  // Fallback calculation: credit - next bill amount
  const credit = preview.value.credit_applied ?? 0;
  const nextBill = preview.value.next_period_amount ?? preview.value.new_plan.amount;
  const remaining = credit - nextBill;

  return remaining > 0 ? remaining : 0;
});

// Credit amount applied to next bill (capped at bill amount)
const creditAppliedToBill = computed(() => {
  if (!preview.value) return 0;

  const credit = preview.value.credit_applied ?? 0;
  const nextBill = preview.value.next_period_amount ?? preview.value.new_plan.amount;

  return Math.min(credit, nextBill);
});

// Amount actually due at next billing (after credit applied)
const amountDueAtNextBilling = computed(() => {
  if (!preview.value) return 0;

  // Use API-provided value if available
  if (preview.value.actual_next_billing_due !== undefined) {
    return preview.value.actual_next_billing_due;
  }

  const credit = preview.value.credit_applied ?? 0;
  const nextBill = preview.value.next_period_amount ?? preview.value.new_plan.amount;
  const due = nextBill - credit;

  return due > 0 ? due : 0;
});

// Load preview when modal opens with target plan
watch(
  () => [props.open, props.targetPlan],
  async ([isOpen, plan]) => {
    if (isOpen && plan) {
      await loadPreview();
    } else {
      // Reset state when closing
      preview.value = null;
      error.value = '';
    }
  },
  { immediate: true }
);

async function loadPreview() {
  if (!props.targetPlan?.stripe_price_id || !props.orgExtId) return;

  isLoadingPreview.value = true;
  error.value = '';

  try {
    preview.value = await BillingService.previewPlanChange(
      props.orgExtId,
      props.targetPlan.stripe_price_id
    );
  } catch (err) {
    const classified = classifyError(err);
    error.value = classified.message || 'Failed to load pricing preview';
    console.error('[PlanChangeModal] Preview error:', err);
  } finally {
    isLoadingPreview.value = false;
  }
}

async function handleConfirm() {
  if (!props.targetPlan?.stripe_price_id || !props.orgExtId) return;

  isChangingPlan.value = true;
  error.value = '';

  try {
    const result = await BillingService.changePlan(
      props.orgExtId,
      props.targetPlan.stripe_price_id
    );

    if (result.success) {
      // Emit the display name from props, not the API's plan ID
      emit('success', props.targetPlan?.name ?? result.new_plan);
    } else {
      error.value = t('web.billing.plans.change_failed');
    }
  } catch (err) {
    const classified = classifyError(err);
    error.value = classified.message || 'Failed to change plan';
    console.error('[PlanChangeModal] Change plan error:', err);
  } finally {
    isChangingPlan.value = false;
  }
}

function handleClose() {
  if (!isChangingPlan.value) {
    emit('close');
  }
}
</script>

<template>
  <TransitionRoot as="template" :show="open">
    <Dialog class="relative z-50"
aria-describedby="plan-change-description"
@close="handleClose">
      <!-- Backdrop -->
      <TransitionChild
        as="template"
        enter="ease-out duration-300"
        enter-from="opacity-0"
        enter-to="opacity-100"
        leave="ease-in duration-200"
        leave-from="opacity-100"
        leave-to="opacity-0">
        <div class="fixed inset-0 bg-gray-500/75 transition-opacity dark:bg-gray-900/80" ></div>
      </TransitionChild>

      <!-- Modal Content -->
      <div class="fixed inset-0 z-10 w-screen overflow-y-auto">
        <div class="flex min-h-full items-end justify-center p-4 text-center sm:items-center sm:p-0">
          <TransitionChild
            as="template"
            enter="ease-out duration-300"
            enter-from="opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"
            enter-to="opacity-100 translate-y-0 sm:scale-100"
            leave="ease-in duration-200"
            leave-from="opacity-100 translate-y-0 sm:scale-100"
            leave-to="opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95">
            <DialogPanel
              class="relative overflow-hidden rounded-lg bg-white px-4 pb-4 pt-5 text-left shadow-xl transition-all dark:bg-gray-800 sm:my-8 sm:w-full sm:max-w-lg sm:p-6">

              <!-- Header -->
              <div class="sm:flex sm:items-start">
                <div
                  :class="[
                    'mx-auto flex size-12 shrink-0 items-center justify-center rounded-full sm:mx-0 sm:size-10',
                    isUpgrade
                      ? 'bg-brand-100 dark:bg-brand-900/30'
                      : 'bg-yellow-100 dark:bg-yellow-900/30'
                  ]">
                  <OIcon
                    collection="heroicons"
                    :name="isUpgrade ? 'arrow-trending-up' : 'arrow-trending-down'"
                    :class="[
                      'size-6',
                      isUpgrade
                        ? 'text-brand-600 dark:text-brand-400'
                        : 'text-yellow-600 dark:text-yellow-400'
                    ]"
                    aria-hidden="true" />
                </div>
                <div class="mt-3 text-center sm:ml-4 sm:mt-0 sm:text-left">
                  <DialogTitle
                    as="h3"
                    class="text-base font-semibold leading-6 text-gray-900 dark:text-white">
                    {{ dialogTitle }}
                  </DialogTitle>
                  <div class="mt-2">
                    <p id="plan-change-description" class="text-sm text-gray-500 dark:text-gray-400">
                      {{ t('web.billing.plans.change_immediate') }}
                    </p>
                  </div>
                </div>
              </div>

              <!-- Loading State -->
              <div v-if="isLoadingPreview" class="mt-6 flex items-center justify-center py-8">
                <OIcon
                  collection="heroicons"
                  name="arrow-path"
                  class="size-8 animate-spin text-gray-400"
                  aria-hidden="true" />
              </div>

              <!-- Error State -->
              <div v-else-if="error"
class="mt-6 rounded-md bg-red-50 p-4 dark:bg-red-900/20"
role="alert"
aria-live="polite">
                <div class="flex">
                  <OIcon
                    collection="heroicons"
                    name="x-circle"
                    class="size-5 text-red-400"
                    aria-hidden="true" />
                  <div class="ml-3">
                    <p class="text-sm text-red-700 dark:text-red-300">{{ error }}</p>
                  </div>
                </div>
              </div>

              <!-- Preview Content -->
              <div v-else-if="preview" class="mt-6">
                <!-- Plan Comparison -->
                <div class="rounded-lg border border-gray-200 bg-gray-50 p-4 dark:border-gray-700 dark:bg-gray-900/50">
                  <div class="space-y-3 text-sm">
                    <div class="flex justify-between">
                      <span class="text-gray-600 dark:text-gray-400">{{ t('web.billing.plans.current_plan_label') }}</span>
                      <span class="font-medium text-gray-900 dark:text-white">
                        {{ currentPlan?.name }} ({{ formatCurrency(preview.current_plan.amount, preview.currency) }}/{{ preview.current_plan.interval }})
                      </span>
                    </div>
                    <div class="flex justify-between">
                      <span class="text-gray-600 dark:text-gray-400">{{ t('web.billing.plans.new_plan_label') }}</span>
                      <span class="font-medium text-gray-900 dark:text-white">
                        {{ targetPlan?.name }} ({{ formatCurrency(preview.new_plan.amount, preview.currency) }}/{{ preview.new_plan.interval }})
                      </span>
                    </div>

                    <!-- Credit from unused time (shown for downgrades) -->
                    <div v-if="preview.credit_applied > 0" class="flex justify-between border-t border-gray-200 pt-3 dark:border-gray-700">
                      <span class="text-gray-600 dark:text-gray-400">{{ t('web.billing.plans.credit_label') }}</span>
                      <span class="font-medium text-green-600 dark:text-green-400">
                        {{ formatCurrency(preview.credit_applied, preview.currency) }}
                      </span>
                    </div>

                    <!-- Divider -->
                    <div class="border-t border-gray-300 dark:border-gray-600"></div>

                    <!-- Credit breakdown for downgrades with significant credit -->
                    <template v-if="showCreditBreakdown">
                      <!-- Section heading -->
                      <h4 class="pt-1 text-xs font-semibold uppercase tracking-wide text-gray-500 dark:text-gray-400">
                        {{ t('web.billing.plans.credit_applies_heading') }}
                      </h4>

                      <!-- Breakdown list using semantic description list -->
                      <dl class="space-y-2 border-l-2 border-gray-200 pl-3 dark:border-gray-600">
                        <!-- Next bill amount -->
                        <div class="flex justify-between">
                          <dt class="text-gray-600 dark:text-gray-400">
                            {{ t('web.billing.plans.next_bill_amount') }}
                          </dt>
                          <dd class="font-medium text-gray-900 dark:text-white">
                            {{ formatCurrency(preview.next_period_amount ?? preview.new_plan.amount, preview.currency) }}
                          </dd>
                        </div>

                        <!-- Credit applied -->
                        <div class="flex justify-between">
                          <dt class="text-gray-600 dark:text-gray-400">
                            {{ t('web.billing.plans.credit_applied_to_bill') }}
                          </dt>
                          <dd class="font-medium text-green-600 dark:text-green-400">
                            -{{ formatCurrency(creditAppliedToBill, preview.currency) }}
                          </dd>
                        </div>

                        <!-- Amount due at next billing (emphasized when $0) -->
                        <div class="flex justify-between">
                          <dt class="font-medium text-gray-900 dark:text-white">
                            {{ t('web.billing.plans.amount_due_next_billing') }}
                          </dt>
                          <dd :class="[
                            'font-bold',
                            amountDueAtNextBilling === 0
                              ? 'text-green-600 dark:text-green-400'
                              : 'text-gray-900 dark:text-white'
                          ]">
                            {{ formatCurrency(amountDueAtNextBilling, preview.currency) }}
                          </dd>
                        </div>

                        <!-- Remaining credit (if any) -->
                        <div v-if="remainingCreditAfterBill > 0" class="flex justify-between border-t border-gray-200 pt-2 dark:border-gray-600">
                          <dt class="text-gray-600 dark:text-gray-400">
                            {{ t('web.billing.plans.remaining_account_credit') }}
                          </dt>
                          <dd class="font-medium text-green-600 dark:text-green-400">
                            {{ formatCurrency(remainingCreditAfterBill, preview.currency) }}
                          </dd>
                        </div>
                      </dl>

                      <!-- Explanatory note for remaining credit -->
                      <p v-if="remainingCreditAfterBill > 0" class="text-xs italic text-gray-500 dark:text-gray-400">
                        {{ t('web.billing.plans.credit_future_note') }}
                      </p>
                    </template>

                    <!-- Standard proration breakdown (upgrades or credit < next bill) -->
                    <template v-else-if="hasNewProrationFields">
                      <!-- Due Today (only show if > 0) -->
                      <div v-if="preview.immediate_amount && preview.immediate_amount > 0" class="flex justify-between">
                        <span class="font-medium text-gray-900 dark:text-white">
                          {{ t('web.billing.plans.due_today') }}
                        </span>
                        <span class="font-bold text-gray-900 dark:text-white">
                          {{ formatCurrency(preview.immediate_amount, preview.currency) }}
                        </span>
                      </div>
                      <!-- Next Billing -->
                      <div class="flex justify-between">
                        <span class="font-medium text-gray-900 dark:text-white">
                          {{ t('web.billing.plans.next_billing', { date: formattedNextBillingDate ?? '' }) }}
                        </span>
                        <span class="font-bold text-gray-900 dark:text-white">
                          {{ formatCurrency(preview.next_period_amount!, preview.currency) }}
                        </span>
                      </div>
                    </template>

                    <!-- Legacy fallback: Amount Due (when API doesn't provide new fields) -->
                    <div v-else class="flex justify-between">
                      <span class="font-medium text-gray-900 dark:text-white">
                        {{ t('web.billing.plans.next_invoice') }}{{ formattedNextBillingDate ? ` (${formattedNextBillingDate})` : '' }}:
                      </span>
                      <span class="font-bold text-gray-900 dark:text-white">
                        {{ formatCurrency(preview.amount_due, preview.currency) }}
                      </span>
                    </div>
                  </div>
                </div>

                <!-- Feature Limits Notice -->
                <p class="mt-4 text-xs text-gray-500 dark:text-gray-400">
                  {{ t('web.billing.plans.limits_update_notice') }}
                </p>
              </div>

              <!-- Actions -->
              <div class="mt-6 sm:flex sm:flex-row-reverse sm:gap-3">
                <button
                  type="button"
                  :disabled="isChangingPlan || isLoadingPreview || !!error"
                  :class="[
                    'inline-flex w-full justify-center rounded-md px-3 py-2 text-sm font-semibold text-white shadow-sm sm:w-auto',
                    isUpgrade
                      ? 'bg-brand-600 hover:bg-brand-500 dark:bg-brand-500 dark:hover:bg-brand-400'
                      : 'bg-yellow-600 hover:bg-yellow-500 dark:bg-yellow-500 dark:hover:bg-yellow-400',
                    (isChangingPlan || isLoadingPreview || error) && 'cursor-not-allowed opacity-50'
                  ]"
                  @click="handleConfirm">
                  <OIcon
                    v-if="isChangingPlan"
                    collection="heroicons"
                    name="arrow-path"
                    class="mr-2 size-4 animate-spin"
                    aria-hidden="true" />
                  {{ isChangingPlan ? t('web.COMMON.processing') : confirmButtonLabel }}
                </button>
                <button
                  type="button"
                  :disabled="isChangingPlan"
                  class="mt-3 inline-flex w-full justify-center rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-gray-700 dark:text-white dark:ring-gray-600 dark:hover:bg-gray-600 sm:mt-0 sm:w-auto"
                  @click="handleClose">
                  {{ t('web.COMMON.word_cancel') }}
                </button>
              </div>
            </DialogPanel>
          </TransitionChild>
        </div>
      </div>
    </Dialog>
  </TransitionRoot>
</template>
