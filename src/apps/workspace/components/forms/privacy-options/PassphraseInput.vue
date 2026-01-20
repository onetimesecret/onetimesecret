<!-- src/apps/workspace/components/forms/privacy-options/PassphraseInput.vue -->

<script setup lang="ts">
  /**
   * PassphraseInput
   *
   * A chip-style passphrase input using Headless UI Popover.
   * Provides password entry with show/hide toggle, validation,
   * and visual feedback for passphrase state.
   */
  import { computed, nextTick, ref } from 'vue';
  import { useI18n } from 'vue-i18n';
  import { Popover, PopoverButton, PopoverPanel } from '@headlessui/vue';
  import OIcon from '@/shared/components/icons/OIcon.vue';

  const { t } = useI18n();

  interface Props {
    /** Current passphrase value (v-model) */
    modelValue: string;
    /** Minimum passphrase length from config */
    minLength?: number;
    /** Disable when form is submitting */
    disabled?: boolean;
  }

  const props = withDefaults(defineProps<Props>(), {
    minLength: 0,
    disabled: false,
  });

  const emit = defineEmits<{
    (e: 'update:modelValue', value: string): void;
  }>();

  // Local state
  const passphraseVisible = ref(false);
  const inputRef = ref<HTMLInputElement | null>(null);

  // Computed state
  const hasPassphrase = computed(() => !!props.modelValue);

  const isValid = computed(() => {
    // Empty is valid (passphrase is optional)
    if (!props.modelValue) return true;
    // Check minimum length if configured
    if (props.minLength > 0) {
      return props.modelValue.length >= props.minLength;
    }
    return true;
  });

  const validationError = computed(() => {
    if (!props.modelValue || isValid.value) return '';
    return t('web.secrets.passphraseMinimumLength', {
      length: props.minLength,
    });
  });

  const errorId = computed(() =>
    validationError.value ? 'passphrase-error' : undefined
  );

  // Button chip styling based on state
  const buttonClasses = computed(() => {
    if (validationError.value) {
      // Invalid passphrase - red styling
      return [
        'bg-red-50 text-red-700 ring-red-600/20',
        'hover:bg-red-100 hover:ring-red-600/30',
        'focus:ring-red-500',
        'dark:bg-red-900/30 dark:text-red-300 dark:ring-red-400/30',
        'dark:hover:bg-red-900/50',
      ];
    }
    if (hasPassphrase.value) {
      // Has valid passphrase - brand styling
      return [
        'bg-brand-50 text-brand-700 ring-brand-600/20',
        'hover:bg-brand-100 hover:ring-brand-600/30',
        'focus:ring-brand-500',
        'dark:bg-brand-900/30 dark:text-brand-300 dark:ring-brand-400/30',
        'dark:hover:bg-brand-900/50',
      ];
    }
    // No passphrase - neutral styling
    return [
      'bg-gray-50 text-gray-600 ring-gray-500/20',
      'hover:bg-gray-100 hover:ring-gray-500/30',
      'focus:ring-brand-500',
      'dark:bg-gray-700 dark:text-gray-300 dark:ring-gray-500/30',
      'dark:hover:bg-gray-600',
    ];
  });

  // Input border styling based on validation state
  const inputBorderClasses = computed(() => {
    if (validationError.value) {
      return [
        'border-red-400 focus:border-red-500 focus:ring-red-500/20',
        'dark:border-red-500',
      ];
    }
    return [
      'border-gray-300 focus:border-brand-500 focus:ring-brand-500/20',
      'dark:border-gray-600 dark:focus:border-brand-400',
    ];
  });

  // Handlers
  const handleInput = (event: Event) => {
    const value = (event.target as HTMLInputElement).value;
    emit('update:modelValue', value);
  };

  const clearPassphrase = () => {
    emit('update:modelValue', '');
    inputRef.value?.focus();
  };

  const toggleVisibility = () => {
    passphraseVisible.value = !passphraseVisible.value;
  };

  // Focus input when panel opens
  const focusInput = async () => {
    await nextTick();
    inputRef.value?.focus();
  };
</script>

<template>
  <Popover
    v-slot="{ open }"
    class="relative">
    <PopoverButton
      :disabled="disabled"
      class="inline-flex items-center gap-1.5 rounded-md px-2.5 py-1 text-xs
        font-medium ring-1 ring-inset transition-all
        focus:outline-none focus:ring-2
        disabled:cursor-not-allowed disabled:opacity-50"
      :class="buttonClasses"
      @click="open ? null : focusInput()">
      <OIcon
        collection="mdi"
        :name="hasPassphrase ? 'key' : 'key-outline'"
        class="size-3.5"
        aria-hidden="true" />
      <span>{{ t('web.COMMON.secret_passphrase') }}</span>
      <OIcon
        v-if="validationError"
        collection="heroicons"
        name="exclamation-triangle"
        class="size-3 text-red-600 dark:text-red-400"
        aria-hidden="true" />
      <OIcon
        v-else-if="hasPassphrase && isValid"
        collection="heroicons"
        name="check"
        class="size-3 text-brand-600 dark:text-brand-400"
        aria-hidden="true" />
    </PopoverButton>

    <transition
      enter-active-class="transition ease-out duration-100"
      enter-from-class="transform opacity-0 scale-95"
      enter-to-class="transform opacity-100 scale-100"
      leave-active-class="transition ease-in duration-75"
      leave-from-class="transform opacity-100 scale-100"
      leave-to-class="transform opacity-0 scale-95">
      <PopoverPanel
        class="absolute left-0 top-full z-[60] mt-1
          w-72 max-w-[calc(100vw-2rem)]
          rounded-md bg-white p-3 shadow-lg ring-1 ring-black/5
          dark:bg-gray-800 dark:ring-gray-700"
        @vue:mounted="focusInput">
        <label
          for="passphrase-input"
          class="sr-only">
          {{ t('web.COMMON.secret_passphrase') }}
        </label>
        <div class="relative">
          <input
            id="passphrase-input"
            ref="inputRef"
            :type="passphraseVisible ? 'text' : 'password'"
            :value="modelValue"
            :disabled="disabled"
            :aria-invalid="!!validationError"
            :aria-describedby="errorId"
            autocomplete="new-password"
            class="w-full rounded-md border bg-white py-2 pl-3 pr-16
              text-sm text-gray-900 placeholder:text-gray-400
              focus:outline-none focus:ring-2
              dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-500"
            :class="inputBorderClasses"
            :placeholder="t('web.secrets.enterPassphrase')"
            @input="handleInput"
            @keydown.enter.prevent />
          <div class="absolute inset-y-0 right-0 flex items-center gap-0.5 pr-1.5">
            <button
              v-if="modelValue"
              type="button"
              class="p-1 text-gray-400 hover:text-gray-600 dark:hover:text-gray-300"
              :aria-label="t('web.COMMON.clear')"
              @click="clearPassphrase">
              <OIcon
                collection="heroicons"
                name="x-mark"
                class="size-4" />
            </button>
            <button
              type="button"
              class="p-1 text-gray-400 hover:text-gray-600 dark:hover:text-gray-300"
              :aria-label="passphraseVisible ? 'Hide passphrase' : 'Show passphrase'"
              @click="toggleVisibility">
              <OIcon
                collection="heroicons"
                :name="passphraseVisible ? 'eye-slash' : 'eye'"
                class="size-4" />
            </button>
          </div>
        </div>
        <!-- Validation error message -->
        <p
          v-if="validationError"
          :id="errorId"
          class="mt-1.5 text-xs text-red-500 dark:text-red-400"
          role="alert">
          {{ validationError }}
        </p>
        <!-- Hint when no passphrase and min length is configured -->
        <p
          v-else-if="minLength > 0 && !modelValue"
          class="mt-1.5 text-xs text-gray-500 dark:text-gray-400">
          {{ t('web.secrets.passphraseMinimumLength', { length: minLength }) }}
        </p>
      </PopoverPanel>
    </transition>
  </Popover>
</template>
