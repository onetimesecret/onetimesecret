<!-- src/apps/workspace/billing/CancelSubscriptionModal.vue -->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import OIcon from '@/shared/components/icons/OIcon.vue';
import { Dialog, DialogPanel, DialogTitle, TransitionChild, TransitionRoot } from '@headlessui/vue';
import { BillingService } from '@/services/billing.service';
import { classifyError } from '@/schemas/errors';
import { computed, ref } from 'vue';

const { t } = useI18n();

const props = defineProps<{
  open: boolean;
  orgExtId: string;
  /** Plan name for display */
  planName: string;
  /** Unix timestamp when current period ends */
  periodEnd: number | null;
}>();

const emit = defineEmits<{
  (e: 'close'): void;
  (e: 'success'): void;
}>();

const isCanceling = ref(false);
const error = ref('');

const formattedPeriodEnd = computed(() => {
  if (!props.periodEnd) return null;
  return new Date(props.periodEnd * 1000).toLocaleDateString(undefined, {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  });
});

const handleCancel = async () => {
  if (isCanceling.value || !props.orgExtId) return;

  isCanceling.value = true;
  error.value = '';

  try {
    await BillingService.cancelSubscription(props.orgExtId);
    emit('success');
  } catch (err) {
    const classified = classifyError(err);
    error.value = classified.message || t('web.billing.cancel.error');
    console.error('[CancelSubscriptionModal] Cancellation error:', err);
  } finally {
    isCanceling.value = false;
  }
};

const handleClose = () => {
  if (!isCanceling.value) {
    emit('close');
  }
};
</script>

<template>
  <TransitionRoot as="template" :show="open">
    <Dialog as="div"
class="relative z-50"
@close="handleClose">
      <TransitionChild
        as="template"
        enter="ease-out duration-300"
        enter-from="opacity-0"
        enter-to="opacity-100"
        leave="ease-in duration-200"
        leave-from="opacity-100"
        leave-to="opacity-0">
        <div class="fixed inset-0 bg-gray-500/75 transition-opacity dark:bg-gray-900/75" ></div>
      </TransitionChild>

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
              class="relative transform overflow-hidden rounded-lg bg-white px-4 pb-4 pt-5 text-left shadow-xl transition-all dark:bg-gray-800 sm:my-8 sm:w-full sm:max-w-lg sm:p-6">
              <!-- Warning Icon -->
              <div class="mx-auto flex size-12 items-center justify-center rounded-full bg-red-100 dark:bg-red-900/30">
                <OIcon
                  collection="heroicons"
                  name="exclamation-triangle"
                  class="size-6 text-red-600 dark:text-red-400"
                  aria-hidden="true" />
              </div>

              <!-- Title -->
              <div class="mt-3 text-center sm:mt-5">
                <DialogTitle as="h3" class="text-lg font-semibold text-gray-900 dark:text-white">
                  {{ t('web.billing.cancel.title') }}
                </DialogTitle>
              </div>

              <!-- Content -->
              <div class="mt-4 space-y-4">
                <p class="text-sm text-gray-600 dark:text-gray-400">
                  {{ t('web.billing.cancel.confirmation', { plan: planName }) }}
                </p>

                <!-- What happens section -->
                <div class="rounded-lg bg-gray-50 p-4 dark:bg-gray-700/50">
                  <h4 class="text-sm font-medium text-gray-900 dark:text-white">
                    {{ t('web.billing.cancel.what_happens') }}
                  </h4>
                  <ul class="mt-2 space-y-2 text-sm text-gray-600 dark:text-gray-400">
                    <li class="flex items-start gap-2">
                      <OIcon
                        collection="heroicons"
                        name="check"
                        class="mt-0.5 size-4 shrink-0 text-green-500"
                        aria-hidden="true" />
                      <span v-if="formattedPeriodEnd">
                        {{ t('web.billing.cancel.access_until', { date: formattedPeriodEnd }) }}
                      </span>
                      <span v-else>
                        {{ t('web.billing.cancel.access_until_period_end') }}
                      </span>
                    </li>
                    <li class="flex items-start gap-2">
                      <OIcon
                        collection="heroicons"
                        name="check"
                        class="mt-0.5 size-4 shrink-0 text-green-500"
                        aria-hidden="true" />
                      {{ t('web.billing.cancel.no_future_charges') }}
                    </li>
                    <li class="flex items-start gap-2">
                      <OIcon
                        collection="heroicons"
                        name="arrow-down"
                        class="mt-0.5 size-4 shrink-0 text-amber-500"
                        aria-hidden="true" />
                      {{ t('web.billing.cancel.downgrade_to_free') }}
                    </li>
                  </ul>
                </div>

                <!-- Error message -->
                <div
                  v-if="error"
                  class="rounded-md bg-red-50 p-3 dark:bg-red-900/20"
                  role="alert">
                  <p class="text-sm text-red-700 dark:text-red-300">{{ error }}</p>
                </div>
              </div>

              <!-- Actions -->
              <div class="mt-6 flex flex-col-reverse gap-3 sm:flex-row sm:justify-end">
                <button
                  type="button"
                  @click="handleClose"
                  :disabled="isCanceling"
                  class="w-full rounded-md bg-white px-4 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-gray-700 dark:text-gray-100 dark:ring-gray-600 dark:hover:bg-gray-600 sm:w-auto">
                  {{ t('web.billing.cancel.keep_subscription') }}
                </button>
                <button
                  type="button"
                  @click="handleCancel"
                  :disabled="isCanceling"
                  class="w-full rounded-md bg-red-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-red-500 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-red-500 dark:hover:bg-red-400 sm:w-auto">
                  <span v-if="isCanceling">{{ t('web.COMMON.processing') }}</span>
                  <span v-else>{{ t('web.billing.cancel.confirm_cancel') }}</span>
                </button>
              </div>
            </DialogPanel>
          </TransitionChild>
        </div>
      </div>
    </Dialog>
  </TransitionRoot>
</template>
