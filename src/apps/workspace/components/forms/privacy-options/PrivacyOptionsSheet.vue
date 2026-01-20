<!-- src/apps/workspace/components/forms/privacy-options/PrivacyOptionsSheet.vue -->

<script setup lang="ts">
  /**
   * Privacy Options Bottom Sheet
   *
   * Mobile-optimized bottom sheet for privacy controls (TTL and passphrase).
   * Uses Headless UI Dialog for accessibility and focus management.
   * Slides up from bottom with iOS safe area support.
   */
  import { computed, ref } from 'vue';
  import { useI18n } from 'vue-i18n';
  import {
    Dialog,
    DialogPanel,
    DialogTitle,
    TransitionChild,
    TransitionRoot,
  } from '@headlessui/vue';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { usePrivacyOptions } from '@/shared/composables/usePrivacyOptions';
  import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
  import { storeToRefs } from 'pinia';

  const { t } = useI18n();

  interface Props {
    /** v-model for open state */
    modelValue: boolean;
    /** Current TTL value in seconds */
    currentTtl: number;
    /** Current passphrase value */
    currentPassphrase: string;
    /** Disable controls when submitting */
    disabled?: boolean;
  }

  const props = withDefaults(defineProps<Props>(), {
    disabled: false,
  });

  const emit = defineEmits<{
    (e: 'update:modelValue', value: boolean): void;
    (e: 'update:ttl', value: number): void;
    (e: 'update:passphrase', value: string): void;
  }>();

  const { lifetimeOptions } = usePrivacyOptions();

  // Get passphrase config for validation hints
  const bootstrapStore = useBootstrapStore();
  const { secret_options } = storeToRefs(bootstrapStore);
  const passphraseConfig = computed(() => secret_options.value?.passphrase);

  // Passphrase visibility toggle
  const passphraseVisible = ref(false);

  // Passphrase validation
  const minPassphraseLength = computed(
    () => passphraseConfig.value?.minimum_length || 0
  );

  const isPassphraseValid = computed(() => {
    if (!props.currentPassphrase) return true;
    if (minPassphraseLength.value > 0) {
      return props.currentPassphrase.length >= minPassphraseLength.value;
    }
    return true;
  });

  const passphraseValidationError = computed(() => {
    if (!props.currentPassphrase || isPassphraseValid.value) return '';
    return t('web.secrets.passphraseMinimumLength', {
      length: minPassphraseLength.value,
    });
  });

  // Handlers
  const closeSheet = () => {
    emit('update:modelValue', false);
  };

  const handleTtlChange = (event: Event) => {
    const value = Number((event.target as HTMLSelectElement).value);
    emit('update:ttl', value);
  };

  const handlePassphraseInput = (event: Event) => {
    const value = (event.target as HTMLInputElement).value;
    emit('update:passphrase', value);
  };

  const togglePassphraseVisibility = () => {
    passphraseVisible.value = !passphraseVisible.value;
  };

  const clearPassphrase = () => {
    emit('update:passphrase', '');
  };
</script>

<template>
  <TransitionRoot
    :show="modelValue"
    as="template">
    <Dialog
      @close="closeSheet"
      class="relative z-50">
      <!-- Backdrop -->
      <TransitionChild
        as="template"
        enter="motion-safe:ease-out motion-safe:duration-300"
        enter-from="opacity-0"
        enter-to="opacity-100"
        leave="motion-safe:ease-in motion-safe:duration-200"
        leave-from="opacity-100"
        leave-to="opacity-0">
        <div
          class="fixed inset-0 bg-black/50"
          aria-hidden="true" ></div>
      </TransitionChild>

      <!-- Panel container - fixed to bottom -->
      <div class="fixed inset-x-0 bottom-0">
        <TransitionChild
          as="template"
          enter="motion-safe:ease-out motion-safe:duration-300"
          enter-from="translate-y-full"
          enter-to="translate-y-0"
          leave="motion-safe:ease-in motion-safe:duration-200"
          leave-from="translate-y-0"
          leave-to="translate-y-full">
          <DialogPanel
            class="rounded-t-2xl bg-white p-6 pb-safe dark:bg-gray-800">
            <!-- Drag handle indicator -->
            <div class="mb-4 flex justify-center">
              <div
                class="h-1 w-10 rounded-full bg-gray-300 dark:bg-gray-600"
                aria-hidden="true" ></div>
            </div>

            <!-- Header -->
            <div class="mb-6 flex items-center gap-3">
              <div
                class="flex size-10 items-center justify-center rounded-full
                  bg-brand-100 dark:bg-brand-900/30">
                <OIcon
                  collection="material-symbols"
                  name="shield-outline"
                  class="size-5 text-brand-600 dark:text-brand-400"
                  aria-hidden="true" />
              </div>
              <DialogTitle
                as="h2"
                class="text-lg font-semibold text-gray-900 dark:text-gray-100">
                {{ t('web.COMMON.secret_privacy_options') }}
              </DialogTitle>
            </div>

            <!-- TTL Section -->
            <div class="mb-5">
              <label
                for="sheet-ttl-select"
                class="mb-2 block text-sm font-medium text-gray-700 dark:text-gray-300">
                {{ t('web.LABELS.secret_ttl') }}
              </label>
              <select
                id="sheet-ttl-select"
                :value="currentTtl"
                :disabled="disabled"
                @change="handleTtlChange"
                class="w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-base
                  text-gray-900 transition-colors
                  focus:border-brand-500 focus:outline-none focus:ring-2 focus:ring-brand-500/20
                  disabled:cursor-not-allowed disabled:opacity-50
                  dark:border-gray-600 dark:bg-gray-700 dark:text-white
                  dark:focus:border-brand-400">
                <option
                  v-for="opt in lifetimeOptions"
                  :key="opt.value"
                  :value="opt.value">
                  {{ t('web.secrets.expiresIn', { duration: opt.label }) }}
                </option>
              </select>
            </div>

            <!-- Passphrase Section -->
            <div class="mb-6">
              <label
                for="sheet-passphrase-input"
                class="mb-2 block text-sm font-medium text-gray-700 dark:text-gray-300">
                {{ t('web.COMMON.secret_passphrase') }}
              </label>
              <div class="relative">
                <input
                  id="sheet-passphrase-input"
                  :type="passphraseVisible ? 'text' : 'password'"
                  :value="currentPassphrase"
                  :disabled="disabled"
                  autocomplete="new-password"
                  :placeholder="t('web.secrets.enterPassphrase')"
                  @input="handlePassphraseInput"
                  class="w-full rounded-lg border bg-white px-4 py-3 pr-20 text-base
                    text-gray-900 placeholder:text-gray-400 transition-colors
                    focus:outline-none focus:ring-2
                    disabled:cursor-not-allowed disabled:opacity-50
                    dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-500"
                  :class="
                    passphraseValidationError
                      ? 'border-red-400 focus:border-red-500 focus:ring-red-500/20 dark:border-red-500'
                      : 'border-gray-300 focus:border-brand-500 focus:ring-brand-500/20 dark:border-gray-600 dark:focus:border-brand-400'
                  " />
                <div class="absolute inset-y-0 right-0 flex items-center gap-1 pr-2">
                  <button
                    v-if="currentPassphrase"
                    type="button"
                    :disabled="disabled"
                    @click="clearPassphrase"
                    class="rounded p-1.5 text-gray-400 transition-colors
                      hover:text-gray-600
                      focus:outline-none focus:ring-2 focus:ring-brand-500
                      disabled:cursor-not-allowed disabled:opacity-50
                      dark:hover:text-gray-300"
                    :aria-label="t('web.COMMON.clear')">
                    <OIcon
                      collection="heroicons"
                      name="x-mark"
                      class="size-5" />
                  </button>
                  <button
                    type="button"
                    :disabled="disabled"
                    @click="togglePassphraseVisibility"
                    class="rounded p-1.5 text-gray-400 transition-colors
                      hover:text-gray-600
                      focus:outline-none focus:ring-2 focus:ring-brand-500
                      disabled:cursor-not-allowed disabled:opacity-50
                      dark:hover:text-gray-300"
                    :aria-label="
                      passphraseVisible
                        ? t('web.LABELS.hide_passphrase')
                        : t('web.LABELS.show_passphrase')
                    ">
                    <OIcon
                      collection="heroicons"
                      :name="passphraseVisible ? 'outline-eye-off' : 'solid-eye'"
                      class="size-5" />
                  </button>
                </div>
              </div>
              <!-- Validation feedback -->
              <p
                v-if="passphraseValidationError"
                class="mt-2 text-sm text-red-500 dark:text-red-400"
                role="alert">
                {{ passphraseValidationError }}
              </p>
              <p
                v-else-if="minPassphraseLength > 0 && !currentPassphrase"
                class="mt-2 text-sm text-gray-500 dark:text-gray-400">
                {{ t('web.secrets.passphraseMinimumLength', { length: minPassphraseLength }) }}
              </p>
            </div>

            <!-- Done button -->
            <button
              type="button"
              @click="closeSheet"
              class="w-full rounded-lg bg-brand-600 px-4 py-3 text-base font-medium text-white
                transition-colors
                hover:bg-brand-700
                focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2
                dark:bg-brand-500 dark:hover:bg-brand-600
                dark:focus:ring-offset-gray-800">
              {{ t('web.COMMON.done') }}
            </button>
          </DialogPanel>
        </TransitionChild>
      </div>
    </Dialog>
  </TransitionRoot>
</template>
