<!-- src/apps/workspace/billing/CurrencyMigrationModal.vue -->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import OIcon from '@/shared/components/icons/OIcon.vue';
import { Dialog, DialogPanel, DialogTitle, TransitionChild, TransitionRoot } from '@headlessui/vue';
import { BillingService } from '@/services/billing.service';
import { classifyError } from '@/schemas/errors';
import type { CurrencyConflictError, MigrationMode } from '@/schemas/models/billing';
import { computed, ref, watch } from 'vue';

const { t } = useI18n();

const props = defineProps<{
  open: boolean;
  orgExtId: string;
  conflict: CurrencyConflictError | null;
}>();

const emit = defineEmits<{
  (e: 'close'): void;
  (e: 'graceful-confirmed', cancelAt: number): void;
  (e: 'immediate-redirect', checkoutUrl: string): void;
}>();

// State
const isMigrating = ref(false);
const error = ref('');
const selectedMode = ref<MigrationMode>('graceful');

// Reset state when modal opens
watch(() => props.open, (isOpen) => {
  if (isOpen) {
    error.value = '';
    selectedMode.value = 'graceful';
  }
});

// Computed
const details = computed(() => props.conflict?.details ?? null);

const formattedPeriodEnd = computed(() => {
  if (!details.value?.current_plan?.current_period_end) return null;
  return new Date(details.value.current_plan.current_period_end * 1000).toLocaleDateString(undefined, {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  });
});

const existingCurrencyUpper = computed(() =>
  details.value?.existing_currency?.toUpperCase() ?? ''
);

const requestedCurrencyUpper = computed(() =>
  details.value?.requested_currency?.toUpperCase() ?? ''
);

const hasCreditBalance = computed(() =>
  details.value?.warnings.has_credit_balance ?? false
);

const hasWarnings = computed(() => {
  if (!details.value?.warnings) return false;
  const w = details.value.warnings;
  return w.has_credit_balance || w.has_pending_invoice_items || w.has_incompatible_coupons;
});

async function handleConfirm() {
  if (!details.value || !props.orgExtId) return;

  isMigrating.value = true;
  error.value = '';

  try {
    const result = await BillingService.migrateCurrency(props.orgExtId, {
      mode: selectedMode.value,
      new_price_id: details.value.requested_plan?.price_id ?? '',
    });

    if (result.success) {
      if (result.migration.mode === 'graceful') {
        emit('graceful-confirmed', result.migration.cancel_at);
      } else {
        emit('immediate-redirect', result.migration.checkout_url);
      }
    } else {
      error.value = t('web.billing.currency_migration.error');
    }
  } catch (err) {
    const classified = classifyError(err);
    error.value = classified.message || t('web.billing.currency_migration.error');
    console.error('[CurrencyMigrationModal] Migration error:', err);
  } finally {
    isMigrating.value = false;
  }
}

function handleClose() {
  if (!isMigrating.value) {
    emit('close');
  }
}
</script>

<template>
  <TransitionRoot as="template" :show="open">
    <Dialog
      class="relative z-50"
      aria-describedby="currency-migration-description"
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
        <div class="fixed inset-0 bg-gray-500/75 transition-opacity dark:bg-gray-900/80"></div>
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
                <div class="mx-auto flex size-12 shrink-0 items-center justify-center rounded-full bg-amber-100 sm:mx-0 sm:size-10 dark:bg-amber-900/30">
                  <OIcon
                    collection="heroicons"
                    name="currency-dollar"
                    class="size-6 text-amber-600 dark:text-amber-400"
                    aria-hidden="true" />
                </div>
                <div class="mt-3 text-center sm:ml-4 sm:mt-0 sm:text-left">
                  <DialogTitle
                    as="h3"
                    class="text-base font-semibold leading-6 text-gray-900 dark:text-white">
                    {{ t('web.billing.currency_migration.title') }}
                  </DialogTitle>
                  <div class="mt-2">
                    <p id="currency-migration-description" class="text-sm text-gray-500 dark:text-gray-400">
                      {{ t('web.billing.currency_migration.description', {
                        from: existingCurrencyUpper,
                        to: requestedCurrencyUpper,
                      }) }}
                    </p>
                  </div>
                </div>
              </div>

              <!-- Plan Details -->
              <div v-if="details" class="mt-6">
                <div class="rounded-lg border border-gray-200 bg-gray-50 p-4 dark:border-gray-700 dark:bg-gray-900/50">
                  <div class="space-y-3 text-sm">
                    <div class="flex justify-between">
                      <span class="text-gray-600 dark:text-gray-400">
                        {{ t('web.billing.currency_migration.current_plan') }}
                      </span>
                      <span class="font-medium text-gray-900 dark:text-white">
                        {{ details.current_plan?.name }} ({{ details.current_plan?.price_formatted }})
                      </span>
                    </div>
                    <div class="flex justify-between">
                      <span class="text-gray-600 dark:text-gray-400">
                        {{ t('web.billing.currency_migration.new_plan') }}
                      </span>
                      <span class="font-medium text-gray-900 dark:text-white">
                        {{ details.requested_plan?.name }} ({{ details.requested_plan?.price_formatted }})
                      </span>
                    </div>
                    <div class="border-t border-gray-200 pt-3 dark:border-gray-700">
                      <div class="flex justify-between">
                        <span class="text-gray-600 dark:text-gray-400">
                          {{ t('web.billing.currency_migration.current_period_ends') }}
                        </span>
                        <span class="font-medium text-gray-900 dark:text-white">
                          {{ formattedPeriodEnd }}
                        </span>
                      </div>
                    </div>
                  </div>
                </div>

                <!-- Warnings -->
                <div
                  v-if="hasWarnings"
                  class="mt-4 rounded-md bg-amber-50 p-4 dark:bg-amber-900/20"
                  role="alert">
                  <div class="flex">
                    <OIcon
                      collection="heroicons"
                      name="exclamation-triangle"
                      class="size-5 shrink-0 text-amber-400"
                      aria-hidden="true" />
                    <div class="ml-3 space-y-1">
                      <p v-if="hasCreditBalance" class="text-sm text-amber-700 dark:text-amber-300">
                        {{ t('web.billing.currency_migration.warning_credit_balance', {
                          currency: existingCurrencyUpper,
                        }) }}
                      </p>
                      <p v-if="details.warnings.has_pending_invoice_items" class="text-sm text-amber-700 dark:text-amber-300">
                        {{ t('web.billing.currency_migration.warning_pending_items') }}
                      </p>
                      <p v-if="details.warnings.has_incompatible_coupons" class="text-sm text-amber-700 dark:text-amber-300">
                        {{ t('web.billing.currency_migration.warning_coupons') }}
                      </p>
                    </div>
                  </div>
                </div>

                <!-- Migration Mode Selection -->
                <fieldset class="mt-5">
                  <legend class="text-sm font-medium text-gray-900 dark:text-white">
                    {{ t('web.billing.currency_migration.choose_timing') }}
                  </legend>
                  <div class="mt-3 space-y-3">
                    <!-- Graceful: Switch at end of billing period -->
                    <label
                      :class="[
                        'flex cursor-pointer items-start gap-3 rounded-lg border p-4 transition-colors',
                        selectedMode === 'graceful'
                          ? 'border-brand-500 bg-brand-50 dark:border-brand-400 dark:bg-brand-900/20'
                          : 'border-gray-200 bg-white hover:bg-gray-50 dark:border-gray-700 dark:bg-gray-800 dark:hover:bg-gray-750',
                      ]">
                      <input
                        v-model="selectedMode"
                        type="radio"
                        name="migration-mode"
                        value="graceful"
                        class="mt-0.5 size-4 border-gray-300 text-brand-600 focus:ring-brand-600 dark:border-gray-600" />
                      <div class="flex-1">
                        <span class="block text-sm font-medium text-gray-900 dark:text-white">
                          {{ t('web.billing.currency_migration.graceful_title') }}
                        </span>
                        <span class="mt-1 block text-sm text-gray-500 dark:text-gray-400">
                          {{ t('web.billing.currency_migration.graceful_description', {
                            date: formattedPeriodEnd ?? '',
                          }) }}
                        </span>
                      </div>
                    </label>

                    <!-- Immediate: Switch now -->
                    <label
                      :class="[
                        'flex cursor-pointer items-start gap-3 rounded-lg border p-4 transition-colors',
                        selectedMode === 'immediate'
                          ? 'border-brand-500 bg-brand-50 dark:border-brand-400 dark:bg-brand-900/20'
                          : 'border-gray-200 bg-white hover:bg-gray-50 dark:border-gray-700 dark:bg-gray-800 dark:hover:bg-gray-750',
                      ]">
                      <input
                        v-model="selectedMode"
                        type="radio"
                        name="migration-mode"
                        value="immediate"
                        class="mt-0.5 size-4 border-gray-300 text-brand-600 focus:ring-brand-600 dark:border-gray-600" />
                      <div class="flex-1">
                        <span class="block text-sm font-medium text-gray-900 dark:text-white">
                          {{ t('web.billing.currency_migration.immediate_title') }}
                        </span>
                        <span class="mt-1 block text-sm text-gray-500 dark:text-gray-400">
                          {{ t('web.billing.currency_migration.immediate_description') }}
                        </span>
                      </div>
                    </label>
                  </div>
                </fieldset>
              </div>

              <!-- Error State -->
              <div
                v-if="error"
                class="mt-4 rounded-md bg-red-50 p-4 dark:bg-red-900/20"
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

              <!-- Actions -->
              <div class="mt-6 sm:flex sm:flex-row-reverse sm:gap-3">
                <button
                  type="button"
                  :disabled="isMigrating || !details"
                  :class="[
                    'inline-flex w-full justify-center rounded-md px-3 py-2 text-sm font-semibold text-white shadow-sm sm:w-auto',
                    'bg-brand-600 hover:bg-brand-500 dark:bg-brand-500 dark:hover:bg-brand-400',
                    (isMigrating || !details) && 'cursor-not-allowed opacity-50',
                  ]"
                  @click="handleConfirm">
                  <OIcon
                    v-if="isMigrating"
                    collection="heroicons"
                    name="arrow-path"
                    class="mr-2 size-4 animate-spin"
                    aria-hidden="true" />
                  {{ isMigrating
                    ? t('web.COMMON.processing')
                    : t('web.billing.currency_migration.confirm')
                  }}
                </button>
                <button
                  type="button"
                  :disabled="isMigrating"
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
