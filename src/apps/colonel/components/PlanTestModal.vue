<!-- src/apps/colonel/components/PlanTestModal.vue -->

<script setup lang="ts">
import OIcon from '@/shared/components/icons/OIcon.vue';
import { useCsrfStore } from '@/shared/stores';
import { WindowService } from '@/services/window.service';
import { createApi } from '@/api';
import {
  Dialog,
  DialogPanel,
  DialogTitle,
  TransitionChild,
  TransitionRoot,
} from '@headlessui/vue';
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const csrfStore = useCsrfStore();
const $api = createApi();

defineProps<{
  isOpen: boolean;
}>();

const emit = defineEmits<{
  (e: 'close'): void;
}>();

interface Plan {
  id: string;
  name: string;
}

const availablePlans: Plan[] = [
  { id: 'free', name: 'Free' },
  { id: 'identity_v1', name: 'Identity Plus' },
  { id: 'multi_team_v1', name: 'Multi-Team' },
];

const isLoading = ref(false);
const error = ref<string | null>(null);

// Get current test plan state from window
const currentTestPlanId = computed(() => {
  try {
    return WindowService.get('entitlement_test_planid') || null;
  } catch {
    return null;
  }
});

const currentTestPlanName = computed(() => {
  try {
    return WindowService.get('entitlement_test_plan_name') || null;
  } catch {
    return null;
  }
});

const actualPlanId = computed(() =>
  // For colonels testing, we should show their actual organization plan
  // This will come from the backend in the window state
  // For now, default to 'free' as we don't have direct access to org plan here
   'free'
);

const actualPlanName = computed(() => {
  const planId = actualPlanId.value;
  const plan = availablePlans.find(p => p.id === planId);
  return plan?.name || 'Free';
});

const isTestModeActive = computed(() => !!currentTestPlanId.value);

const handleActivateTestMode = async (planId: string) => {
  isLoading.value = true;
  error.value = null;

  try {
    await $api.post(
      '/api/colonel/entitlement-test',
      { planid: planId },
      {
        headers: {
          'Content-Type': 'application/json',
          'O-Shrimp': csrfStore.shrimp,
        },
      }
    );

    // Reload page to get new window state
    window.location.reload();
  } catch (err: unknown) {
    console.error('Failed to activate test mode:', err);
    error.value = 'Failed to activate test mode. Please try again.';
    isLoading.value = false;
  }
};

const handleResetToActual = async () => {
  isLoading.value = true;
  error.value = null;

  try {
    await $api.post(
      '/api/colonel/entitlement-test',
      { planid: null },
      {
        headers: {
          'Content-Type': 'application/json',
          'O-Shrimp': csrfStore.shrimp,
        },
      }
    );

    // Reload page to get new window state
    window.location.reload();
  } catch (err: unknown) {
    console.error('Failed to reset test mode:', err);
    error.value = 'Failed to reset test mode. Please try again.';
    isLoading.value = false;
  }
};

const handleClose = () => {
  if (!isLoading.value) {
    emit('close');
  }
};
</script>

<template>
  <TransitionRoot
    as="template"
    :show="isOpen">
    <Dialog
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
        <div class="fixed inset-0 bg-gray-500/75 transition-opacity dark:bg-gray-900/75"></div>
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
              class="relative overflow-hidden rounded-lg bg-white px-4 pb-4 pt-5 text-left shadow-xl transition-all dark:bg-gray-800 sm:my-8 sm:w-full sm:max-w-lg sm:p-6">
              <div>
                <!-- Icon and Title -->
                <div class="sm:flex sm:items-start">
                  <div
                    class="mx-auto flex size-12 shrink-0 items-center justify-center rounded-full bg-amber-100 dark:bg-amber-900/30 sm:mx-0 sm:size-10">
                    <OIcon
                      collection="heroicons"
                      name="beaker"
                      class="size-6 text-amber-600 dark:text-amber-400"
                      aria-hidden="true" />
                  </div>
                  <div class="mt-3 text-center sm:ml-4 sm:mt-0 sm:text-left">
                    <DialogTitle
                      as="h3"
                      class="text-base font-semibold leading-6 text-gray-900 dark:text-white">
                      {{ t('web.colonel.testPlanMode') }}
                    </DialogTitle>
                    <div class="mt-2">
                      <p class="text-sm text-gray-500 dark:text-gray-400">
                        {{ t('web.colonel.testModeDescription') }}
                      </p>
                    </div>
                  </div>
                </div>

                <!-- Current State -->
                <div class="mt-5">
                  <div class="rounded-lg bg-gray-50 p-4 dark:bg-gray-900/50">
                    <div class="flex items-center justify-between">
                      <div>
                        <p class="text-sm font-medium text-gray-700 dark:text-gray-300">
                          {{ t('web.colonel.currentActualPlan') }}
                        </p>
                        <p class="mt-1 text-lg font-semibold text-gray-900 dark:text-white">
                          {{ actualPlanName }}
                        </p>
                      </div>
                      <div
                        v-if="isTestModeActive"
                        class="rounded-full bg-amber-100 px-3 py-1 dark:bg-amber-900/30">
                        <p class="text-xs font-medium text-amber-800 dark:text-amber-400">
                          {{ t('web.colonel.testModeActive') }}
                        </p>
                      </div>
                    </div>

                    <div
                      v-if="isTestModeActive"
                      class="mt-3 border-t border-gray-200 pt-3 dark:border-gray-700">
                      <p class="text-sm text-gray-600 dark:text-gray-400">
                        {{ t('web.colonel.testingAsPlan', { planName: currentTestPlanName }) }}
                      </p>
                    </div>
                  </div>
                </div>

                <!-- Error Message -->
                <div
                  v-if="error"
                  class="mt-4 rounded-lg bg-red-50 p-4 dark:bg-red-900/20">
                  <p class="text-sm text-red-800 dark:text-red-400">
                    {{ error }}
                  </p>
                </div>

                <!-- Available Plans -->
                <div class="mt-5">
                  <h4 class="text-sm font-medium text-gray-900 dark:text-white">
                    {{ t('web.colonel.availablePlans') }}
                  </h4>
                  <div class="mt-3 space-y-2">
                    <button
                      v-for="plan in availablePlans"
                      :key="plan.id"
                      type="button"
                      :disabled="isLoading || plan.id === currentTestPlanId"
                      :class="[
                        'w-full rounded-lg border px-4 py-3 text-left transition-colors',
                        plan.id === currentTestPlanId
                          ? 'border-amber-500 bg-amber-50 dark:border-amber-600 dark:bg-amber-900/20'
                          : 'border-gray-300 bg-white hover:bg-gray-50 dark:border-gray-600 dark:bg-gray-800 dark:hover:bg-gray-700',
                        isLoading ? 'cursor-not-allowed opacity-50' : 'cursor-pointer',
                      ]"
                      @click="handleActivateTestMode(plan.id)">
                      <div class="flex items-center justify-between">
                        <div>
                          <p
                            :class="[
                              'font-medium',
                              plan.id === currentTestPlanId
                                ? 'text-amber-900 dark:text-amber-100'
                                : 'text-gray-900 dark:text-white',
                            ]">
                            {{ plan.name }}
                          </p>
                          <p
                            v-if="plan.id === actualPlanId && !isTestModeActive"
                            class="mt-0.5 text-xs text-gray-500 dark:text-gray-400">
                            Current plan
                          </p>
                        </div>
                        <OIcon
                          v-if="plan.id === currentTestPlanId"
                          collection="heroicons"
                          name="check-circle-solid"
                          class="size-5 text-amber-600 dark:text-amber-400"
                          aria-hidden="true" />
                      </div>
                    </button>
                  </div>
                </div>
              </div>

              <!-- Actions -->
              <div class="mt-5 sm:mt-6 sm:flex sm:flex-row-reverse sm:gap-3">
                <button
                  v-if="isTestModeActive"
                  type="button"
                  :disabled="isLoading"
                  class="inline-flex w-full justify-center rounded-md bg-amber-600 px-3 py-2 text-sm font-semibold text-white shadow-sm transition-colors hover:bg-amber-500 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-amber-700 dark:hover:bg-amber-600 sm:w-auto"
                  @click="handleResetToActual">
                  <span v-if="!isLoading">{{ t('web.colonel.resetToActual') }}</span>
                  <span v-else>{{ t('web.COMMON.processing') }}</span>
                </button>
                <button
                  type="button"
                  :disabled="isLoading"
                  class="mt-3 inline-flex w-full justify-center rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 transition-colors hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-gray-700 dark:text-white dark:ring-gray-600 dark:hover:bg-gray-600 sm:mt-0 sm:w-auto"
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
