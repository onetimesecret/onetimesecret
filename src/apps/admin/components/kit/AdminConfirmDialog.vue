<!-- src/apps/admin/components/kit/AdminConfirmDialog.vue -->

<script setup lang="ts">
  import {
    Dialog,
    DialogPanel,
    DialogTitle,
    TransitionChild,
    TransitionRoot,
  } from '@headlessui/vue';
  import { computed, nextTick, ref, watch } from 'vue';
  import { useI18n } from 'vue-i18n';

  import OIcon from '@/shared/components/icons/OIcon.vue';

  /**
   * The D4 destructive-action gate for the admin console (ticket #11, CONTRACT 4).
   *
   * Generalises the `PasswordConfirmModal` pattern (headlessui `Dialog` + input +
   * loading/error/danger styling) into a TYPED-CONFIRMATION dialog: when a
   * `confirmToken` is supplied, the confirm button stays disabled until the typed
   * input EXACTLY equals that token (e.g. retype the customer's email or id before
   * a delete). When `confirmToken` is omitted it degrades to a simple confirm for
   * low-risk actions.
   *
   * The prop/slot API here is FROZEN — it is the shared gate reused by tickets
   * 22/30/40/41/42/43/44. The seven contract props are:
   *   { open, title, description, confirmToken, variant, loading, error }
   * The optional `confirmText` / `cancelText` / `initialFocus` props are purely
   * presentational conveniences and default sensibly.
   */
  interface Props {
    /** Whether the dialog is shown (use with `v-model:open`). */
    open: boolean;
    /** Dialog heading (already translated). */
    title: string;
    /** Optional supporting copy under the title. */
    description?: string;
    /**
     * The exact string the operator must retype to enable confirm. When empty /
     * undefined the dialog is a SIMPLE confirm (no typed gate).
     */
    confirmToken?: string;
    /** Visual + semantic weight. `danger` uses red accents for destructive ops. */
    variant?: 'default' | 'danger';
    /** True while the confirmed action is in flight (disables all controls). */
    loading?: boolean;
    /** Server/action error to surface, or null. */
    error?: string | null;
    /** Confirm button label (translated). Defaults to the common "Confirm". */
    confirmText?: string;
    /** Cancel button label (translated). Defaults to the common "Cancel". */
    cancelText?: string;
    /** Which control receives focus when the dialog opens. */
    initialFocus?: 'input' | 'cancel';
  }

  const props = withDefaults(defineProps<Props>(), {
    description: undefined,
    confirmToken: undefined,
    variant: 'default',
    loading: false,
    error: null,
    confirmText: undefined,
    cancelText: undefined,
    initialFocus: 'input',
  });

  const emit = defineEmits<{
    'update:open': [value: boolean];
    confirm: [];
    cancel: [];
  }>();

  const { t } = useI18n();

  const typed = ref('');
  const inputEl = ref<HTMLInputElement | null>(null);
  const cancelEl = ref<HTMLButtonElement | null>(null);

  /** Typed-confirmation mode is active only when a non-empty token is supplied. */
  const requiresTyped = computed(
    () => typeof props.confirmToken === 'string' && props.confirmToken.length > 0
  );

  /** The gate: exact match (no trimming) between the typed input and the token. */
  const tokenMatches = computed(
    () => requiresTyped.value && typed.value === props.confirmToken
  );

  /**
   * Confirm is disabled while loading, or — in typed mode — until the token
   * matches exactly. In simple mode it is enabled (unless loading).
   */
  const confirmDisabled = computed(() => {
    if (props.loading) return true;
    if (requiresTyped.value) return !tokenMatches.value;
    return false;
  });

  const showMismatchHint = computed(
    () => requiresTyped.value && typed.value.length > 0 && !tokenMatches.value
  );

  const resolvedConfirmText = computed(
    () => props.confirmText ?? t('web.COMMON.word_confirm')
  );
  const resolvedCancelText = computed(
    () => props.cancelText ?? t('web.COMMON.word_cancel')
  );
  const buttonText = computed(() =>
    props.loading ? t('web.COMMON.processing') : resolvedConfirmText.value
  );

  const confirmButtonClasses = computed(() => {
    const base =
      'inline-flex w-full justify-center rounded-md px-4 py-2 text-sm font-semibold shadow-sm transition-colors focus:outline-none focus:ring-2 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 sm:ml-3 sm:w-auto';
    if (props.variant === 'danger') {
      return `${base} bg-red-600 text-white hover:bg-red-700 focus:ring-red-500 dark:bg-red-700 dark:hover:bg-red-800`;
    }
    return `${base} bg-brand-600 text-white hover:bg-brand-700 focus:ring-brand-500 dark:bg-brand-500 dark:hover:bg-brand-600`;
  });

  function handleSubmit(): void {
    if (confirmDisabled.value) return;
    emit('confirm');
  }

  function handleCancel(): void {
    emit('cancel');
    emit('update:open', false);
  }

  // Clear the typed value when closed; focus the requested control when opened.
  watch(
    () => props.open,
    (isOpen) => {
      if (!isOpen) {
        typed.value = '';
        return;
      }
      nextTick(() => {
        // Focus the typed input only when explicitly requested AND the dialog is
        // in typed-confirmation mode; otherwise fall back to the cancel button.
        const focusInput = props.initialFocus === 'input' && requiresTyped.value;
        const target = focusInput ? inputEl.value : cancelEl.value;
        target?.focus();
      });
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
          aria-hidden="true"></div>
      </TransitionChild>

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
              data-testid="admin-confirm-dialog"
              class="relative w-full max-w-md overflow-hidden rounded-lg bg-white px-4 pb-4 pt-5 text-left shadow-xl transition-all dark:bg-gray-800 sm:my-8 sm:p-6">
              <form @submit.prevent="handleSubmit">
                <!-- Header with icon -->
                <div class="sm:flex sm:items-start">
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
                        :name="variant === 'danger' ? 'exclamation-triangle' : 'question-mark-circle'"
                        class="size-6"
                        :class="
                          variant === 'danger'
                            ? 'text-red-600 dark:text-red-400'
                            : 'text-brand-600 dark:text-brand-400'
                        "
                        aria-hidden="true" />
                    </slot>
                  </div>

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

                <!-- Typed-confirmation input (only in typed mode) -->
                <div
                  v-if="requiresTyped"
                  class="mt-4">
                  <label
                    for="admin-confirm-input"
                    class="block text-sm text-gray-600 dark:text-gray-400">
                    <slot
                      name="prompt"
                      :token="confirmToken">
                      <!-- i18n interpolation renders the token inside the prompt. -->
                      {{ t('web.admin.kit.confirmDialog.typePrompt', { token: confirmToken }) }}
                    </slot>
                  </label>
                  <input
                    id="admin-confirm-input"
                    ref="inputEl"
                    v-model="typed"
                    type="text"
                    autocomplete="off"
                    autocapitalize="off"
                    autocorrect="off"
                    spellcheck="false"
                    :disabled="loading"
                    :aria-label="t('web.admin.kit.confirmDialog.inputLabel')"
                    :aria-invalid="showMismatchHint ? 'true' : undefined"
                    :aria-describedby="showMismatchHint ? 'admin-confirm-hint' : undefined"
                    :placeholder="confirmToken"
                    class="mt-2 block w-full appearance-none rounded-md border border-gray-300 px-3 py-2 font-mono text-base placeholder:text-gray-400 focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-500 dark:focus:border-brand-400 dark:focus:ring-brand-400" />
                  <p
                    v-if="showMismatchHint"
                    id="admin-confirm-hint"
                    class="mt-1.5 text-xs text-gray-500 dark:text-gray-400">
                    {{ t('web.admin.kit.confirmDialog.mismatchHint') }}
                  </p>
                </div>

                <!-- Error -->
                <div
                  v-if="error"
                  class="mt-3 rounded-md bg-red-50 p-3 dark:bg-red-900/20"
                  role="alert"
                  aria-live="assertive">
                  <p class="text-sm text-red-800 dark:text-red-200">{{ error }}</p>
                </div>

                <!-- Actions -->
                <div class="mt-5 sm:mt-4 sm:flex sm:flex-row-reverse">
                  <button
                    type="submit"
                    data-testid="admin-confirm-submit"
                    :disabled="confirmDisabled"
                    :class="confirmButtonClasses">
                    <OIcon
                      v-if="loading"
                      collection="heroicons"
                      name="arrow-path"
                      class="-ml-1 mr-2 size-4 animate-spin motion-reduce:animate-none"
                      aria-hidden="true" />
                    {{ buttonText }}
                  </button>
                  <button
                    ref="cancelEl"
                    type="button"
                    data-testid="admin-confirm-cancel"
                    :disabled="loading"
                    class="mt-3 inline-flex w-full justify-center rounded-md bg-white px-4 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 transition-colors hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-gray-400 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-gray-700 dark:text-gray-300 dark:ring-gray-600 dark:hover:bg-gray-600 sm:mt-0 sm:w-auto"
                    @click="handleCancel">
                    {{ resolvedCancelText }}
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
