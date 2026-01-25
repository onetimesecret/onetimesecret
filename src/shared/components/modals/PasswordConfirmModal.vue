<!-- src/shared/components/modals/PasswordConfirmModal.vue -->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import OIcon from '@/shared/components/icons/OIcon.vue';
import {
  Dialog,
  DialogPanel,
  DialogTitle,
  TransitionChild,
  TransitionRoot,
} from '@headlessui/vue';
import { ref, watch, computed, nextTick } from 'vue';

const { t } = useI18n();

export interface Props {
  open: boolean;
  title: string;
  description?: string;
  confirmText?: string;
  cancelText?: string;
  variant?: 'default' | 'danger';
  loading?: boolean;
  error?: string | null;
  initialFocus?: 'password' | 'cancel';
}

const props = withDefaults(defineProps<Props>(), {
  description: undefined,
  confirmText: 'web.COMMON.word_confirm',
  cancelText: 'web.COMMON.word_cancel',
  variant: 'default',
  loading: false,
  error: null,
  initialFocus: 'password',
});

const emit = defineEmits<{
  'update:open': [value: boolean];
  confirm: [password: string];
  cancel: [];
}>();

const password = ref('');
const showPassword = ref(false);
const passwordInput = ref<HTMLInputElement | null>(null);
const cancelButton = ref<HTMLButtonElement | null>(null);

// Computed for button styling based on variant
const confirmButtonClasses = computed(() => {
  const base =
    'inline-flex w-full justify-center rounded-md px-4 py-2 text-sm font-semibold shadow-sm transition-colors focus:outline-none focus:ring-2 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 sm:ml-3 sm:w-auto';
  if (props.variant === 'danger') {
    return `${base} bg-red-600 text-white hover:bg-red-700 focus:ring-red-500 dark:bg-red-700 dark:hover:bg-red-800`;
  }
  return `${base} bg-brand-600 text-white hover:bg-brand-700 focus:ring-brand-500 dark:bg-brand-500 dark:hover:bg-brand-600`;
});

// Computed for loading text
const buttonText = computed(() => {
  if (props.loading) {
    return t('web.COMMON.processing');
  }
  return t(props.confirmText);
});

// Toggle password visibility
const togglePasswordVisibility = () => {
  showPassword.value = !showPassword.value;
};

// Handle form submission
const handleSubmit = () => {
  if (password.value && !props.loading) {
    emit('confirm', password.value);
  }
};

// Handle cancel action
const handleCancel = () => {
  emit('cancel');
  closeModal();
};

// Close modal and reset state
const closeModal = () => {
  emit('update:open', false);
};

// Get initial focus element
const getInitialFocusElement = () => {
  if (props.initialFocus === 'cancel') {
    return cancelButton.value;
  }
  return passwordInput.value;
};

// Clear password when modal closes
watch(
  () => props.open,
  (isOpen) => {
    if (!isOpen) {
      password.value = '';
      showPassword.value = false;
    } else {
      // Focus the appropriate element when modal opens
      nextTick(() => {
        const focusElement = getInitialFocusElement();
        focusElement?.focus();
      });
    }
  }
);
</script>

<template>
  <TransitionRoot
    as="template"
    :show="open">
    <Dialog
      class="relative z-50"
      @close="handleCancel">
      <!-- Backdrop -->
      <TransitionChild
        as="template"
        enter="ease-out duration-300"
        enter-from="opacity-0"
        enter-to="opacity-100"
        leave="ease-in duration-200"
        leave-from="opacity-100"
        leave-to="opacity-0">
        <div
          class="fixed inset-0 bg-gray-500/75 transition-opacity dark:bg-gray-900/80"
          aria-hidden="true" ></div>
      </TransitionChild>

      <!-- Modal container -->
      <div class="fixed inset-0 z-10 w-screen overflow-y-auto">
        <div
          class="flex min-h-full items-end justify-center p-4 text-center sm:items-center sm:p-0">
          <TransitionChild
            as="template"
            enter="ease-out duration-300"
            enter-from="opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"
            enter-to="opacity-100 translate-y-0 sm:scale-100"
            leave="ease-in duration-200"
            leave-from="opacity-100 translate-y-0 sm:scale-100"
            leave-to="opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95">
            <DialogPanel
              class="relative w-full max-w-md overflow-hidden rounded-lg bg-white px-4 pb-4 pt-5 text-left shadow-xl transition-all dark:bg-gray-800 sm:my-8 sm:p-6">
              <form @submit.prevent="handleSubmit">
                <!-- Header with icon -->
                <div class="sm:flex sm:items-start">
                  <!-- Icon slot with default lock icon -->
                  <div
                    class="mx-auto flex size-12 shrink-0 items-center justify-center rounded-full sm:mx-0 sm:size-10"
                    :class="
                      variant === 'danger'
                        ? 'bg-red-100 dark:bg-red-900/30'
                        : 'bg-brand-100 dark:bg-brand-900/30'
                    ">
                    <slot name="icon">
                      <OIcon
                        collection="heroicons"
                        name="lock-closed"
                        class="size-6"
                        :class="
                          variant === 'danger'
                            ? 'text-red-600 dark:text-red-400'
                            : 'text-brand-600 dark:text-brand-400'
                        "
                        aria-hidden="true" />
                    </slot>
                  </div>

                  <!-- Title and description -->
                  <div class="mt-3 text-center sm:ml-4 sm:mt-0 sm:text-left">
                    <DialogTitle
                      as="h3"
                      class="text-base font-semibold leading-6 text-gray-900 dark:text-white">
                      {{ title }}
                    </DialogTitle>
                    <div class="mt-2">
                      <slot name="description">
                        <p
                          v-if="description"
                          class="text-sm text-gray-500 dark:text-gray-400">
                          {{ description }}
                        </p>
                      </slot>
                    </div>
                  </div>
                </div>

                <!-- Password input -->
                <div class="mt-4">
                  <label
                    for="password-confirm-input"
                    class="sr-only">
                    {{ t('web.COMMON.field_password') }}
                  </label>
                  <div class="relative">
                    <input
                      id="password-confirm-input"
                      ref="passwordInput"
                      v-model="password"
                      :type="showPassword ? 'text' : 'password'"
                      autocomplete="current-password"
                      :disabled="loading"
                      :aria-invalid="error ? 'true' : undefined"
                      :aria-describedby="error ? 'password-confirm-error' : undefined"
                      :placeholder="t('web.COMMON.password_placeholder')"
                      class="block w-full appearance-none rounded-md border border-gray-300 px-3 py-2 pr-10 text-base placeholder:text-gray-400 focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-500 dark:focus:border-brand-400 dark:focus:ring-brand-400" />
                    <button
                      type="button"
                      :disabled="loading"
                      :aria-label="
                        showPassword
                          ? t('web.COMMON.hide_password')
                          : t('web.COMMON.show_password')
                      "
                      class="absolute inset-y-0 right-0 z-10 flex items-center pr-3 text-sm leading-5 disabled:opacity-50"
                      @click="togglePasswordVisibility">
                      <OIcon
                        collection="heroicons"
                        :name="showPassword ? 'solid-eye' : 'outline-eye-off'"
                        size="5"
                        class="text-gray-400 dark:text-gray-500"
                        aria-hidden="true" />
                    </button>
                  </div>
                </div>

                <!-- Error message -->
                <div
                  v-if="error"
                  id="password-confirm-error"
                  class="mt-3 rounded-md bg-red-50 p-3 dark:bg-red-900/20"
                  role="alert"
                  aria-live="assertive">
                  <p class="text-sm text-red-800 dark:text-red-200">
                    {{ error }}
                  </p>
                </div>

                <!-- Action buttons -->
                <div class="mt-5 sm:mt-4 sm:flex sm:flex-row-reverse">
                  <button
                    type="submit"
                    :disabled="loading || !password"
                    :class="confirmButtonClasses">
                    <OIcon
                      v-if="loading"
                      collection="heroicons"
                      name="arrow-path"
                      class="-ml-1 mr-2 size-4 animate-spin"
                      aria-hidden="true" />
                    {{ buttonText }}
                  </button>
                  <button
                    ref="cancelButton"
                    type="button"
                    :disabled="loading"
                    class="mt-3 inline-flex w-full justify-center rounded-md bg-white px-4 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 transition-colors hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-gray-400 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-gray-700 dark:text-gray-300 dark:ring-gray-600 dark:hover:bg-gray-600 sm:mt-0 sm:w-auto"
                    @click="handleCancel">
                    {{ t(cancelText) }}
                  </button>
                </div>
              </form>
            </DialogPanel>
          </TransitionChild>
        </div>
      </div>
    </Dialog>
  </TransitionRoot>
</template>
