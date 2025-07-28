// src/composables/usePasswordChange.ts
import { useAccountStore } from '@/stores/accountStore';
import { computed, reactive } from 'vue';
import { AsyncHandlerOptions, useAsyncHandler } from './useAsyncHandler';

/* eslint-disable max-lines-per-function */
export function usePasswordChange(emit: (event: 'update:password') => void) {
  const formState = reactive({
    currentPassword: '',
    newPassword: '',
    confirmPassword: '',
    isSubmitting: false,
    error: '',
    success: '',
    showPassword: {
      current: false,
      new: false,
      confirm: false,
    },
  });

  const isValid = computed(
    () =>
      formState.newPassword &&
      formState.currentPassword &&
      formState.newPassword === formState.confirmPassword
  );

  const accountStore = useAccountStore();

  const defaultAsyncHandlerOptions: AsyncHandlerOptions = {
    notify: (message, severity) => {
      if (severity === 'error') {
        formState.error = message;
      } else {
        formState.success = message;
      }
    },
    setLoading: (loading) => (formState.isSubmitting = loading),
    onError: () => (formState.success = ''),
  };

  // Composable async handler
  const { wrap } = useAsyncHandler(defaultAsyncHandlerOptions);

  async function handleSubmit() {
    if (!isValid.value) {
      formState.error = 'Please check your password entries';
      return;
    }

    formState.error = '';
    formState.success = '';
    formState.isSubmitting = true;

    wrap(async () => {
      await accountStore.changePassword(
        formState.currentPassword,
        formState.newPassword,
        formState.confirmPassword
      );

      formState.success = 'Password updated successfully';
      emit('update:password');

      // Reset form
      Object.assign(formState, {
        currentPassword: '',
        newPassword: '',
        confirmPassword: '',
        error: '',
        isSubmitting: false,
      });
    });
  }

  const togglePassword = (field: keyof typeof formState.showPassword) => {
    formState.showPassword[field] = !formState.showPassword[field];
  };

  return {
    formState,
    isValid,
    handleSubmit,
    togglePassword,
  };
}
