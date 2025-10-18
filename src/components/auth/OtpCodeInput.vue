<script setup lang="ts">
import { ref, nextTick, watch } from 'vue';

interface Props {
  disabled?: boolean;
  autoFocus?: boolean;
}

const props = withDefaults(defineProps<Props>(), {
  disabled: false,
  autoFocus: true,
});

const emit = defineEmits<{
  complete: [code: string];
  input: [code: string];
}>();

// Individual digit refs
const digit1 = ref('');
const digit2 = ref('');
const digit3 = ref('');
const digit4 = ref('');
const digit5 = ref('');
const digit6 = ref('');

// Input element refs
const input1 = ref<HTMLInputElement | null>(null);
const input2 = ref<HTMLInputElement | null>(null);
const input3 = ref<HTMLInputElement | null>(null);
const input4 = ref<HTMLInputElement | null>(null);
const input5 = ref<HTMLInputElement | null>(null);
const input6 = ref<HTMLInputElement | null>(null);

const inputRefs = [input1, input2, input3, input4, input5, input6];
const digitValues = [digit1, digit2, digit3, digit4, digit5, digit6];

// Focus first input on mount
if (props.autoFocus) {
  nextTick(() => {
    input1.value?.focus();
  });
}

// Handle input for each digit
const handleInput = (index: number, event: Event) => {
  const input = event.target as HTMLInputElement;
  const value = input.value;

  // Only allow single digit
  if (value.length > 1) {
    digitValues[index].value = value.charAt(0);
    return;
  }

  // Only allow numbers
  if (value && !/^\d$/.test(value)) {
    digitValues[index].value = '';
    return;
  }

  // Move to next input if value entered
  if (value && index < 5) {
    nextTick(() => {
      inputRefs[index + 1].value?.focus();
    });
  }

  // Check if all digits filled
  checkComplete();
};

// Handle backspace/delete
const handleKeydown = (index: number, event: KeyboardEvent) => {
  if (event.key === 'Backspace' && !digitValues[index].value && index > 0) {
    // Move to previous input on backspace if current is empty
    nextTick(() => {
      inputRefs[index - 1].value?.focus();
    });
  }
};

// Handle paste
const handlePaste = (event: ClipboardEvent) => {
  event.preventDefault();
  const pastedData = event.clipboardData?.getData('text') || '';
  const digits = pastedData.replace(/\D/g, '').split('').slice(0, 6);

  digits.forEach((digit, index) => {
    if (index < 6) {
      digitValues[index].value = digit;
    }
  });

  // Focus last filled input or first empty one
  const lastIndex = Math.min(digits.length, 5);
  nextTick(() => {
    inputRefs[lastIndex].value?.focus();
  });

  checkComplete();
};

// Check if all 6 digits are filled
const checkComplete = () => {
  const code = digitValues.map((d) => d.value).join('');
  emit('input', code);

  if (code.length === 6) {
    emit('complete', code);
  }
};

// Watch for external code clearing
watch(
  () => props.disabled,
  (newVal) => {
    if (newVal) {
      // Clear all digits when disabled
      digitValues.forEach((d) => {
        d.value = '';
      });
    }
  }
);

// Public method to clear the input
const clear = () => {
  digitValues.forEach((d) => {
    d.value = '';
  });
  input1.value?.focus();
};

// Public method to focus
const focus = () => {
  input1.value?.focus();
};

defineExpose({ clear, focus });
</script>

<template>
  <div class="flex items-center justify-center gap-2">
    <input
      ref="input1"
      v-model="digit1"
      type="text"
      inputmode="numeric"
      maxlength="1"
      :disabled="disabled"
      @input="handleInput(0, $event)"
      @keydown="handleKeydown(0, $event)"
      @paste="handlePaste"
      class="h-12 w-12 rounded-lg border-2 border-gray-300 text-center text-2xl font-semibold focus:border-brand-500 focus:outline-none focus:ring-2 focus:ring-brand-500 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:focus:border-brand-500"
      aria-label="Digit 1"
    />
    <input
      ref="input2"
      v-model="digit2"
      type="text"
      inputmode="numeric"
      maxlength="1"
      :disabled="disabled"
      @input="handleInput(1, $event)"
      @keydown="handleKeydown(1, $event)"
      @paste="handlePaste"
      class="h-12 w-12 rounded-lg border-2 border-gray-300 text-center text-2xl font-semibold focus:border-brand-500 focus:outline-none focus:ring-2 focus:ring-brand-500 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:focus:border-brand-500"
      aria-label="Digit 2"
    />
    <input
      ref="input3"
      v-model="digit3"
      type="text"
      inputmode="numeric"
      maxlength="1"
      :disabled="disabled"
      @input="handleInput(2, $event)"
      @keydown="handleKeydown(2, $event)"
      @paste="handlePaste"
      class="h-12 w-12 rounded-lg border-2 border-gray-300 text-center text-2xl font-semibold focus:border-brand-500 focus:outline-none focus:ring-2 focus:ring-brand-500 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:focus:border-brand-500"
      aria-label="Digit 3"
    />

    <span class="text-2xl text-gray-400">-</span>

    <input
      ref="input4"
      v-model="digit4"
      type="text"
      inputmode="numeric"
      maxlength="1"
      :disabled="disabled"
      @input="handleInput(3, $event)"
      @keydown="handleKeydown(3, $event)"
      @paste="handlePaste"
      class="h-12 w-12 rounded-lg border-2 border-gray-300 text-center text-2xl font-semibold focus:border-brand-500 focus:outline-none focus:ring-2 focus:ring-brand-500 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:focus:border-brand-500"
      aria-label="Digit 4"
    />
    <input
      ref="input5"
      v-model="digit5"
      type="text"
      inputmode="numeric"
      maxlength="1"
      :disabled="disabled"
      @input="handleInput(4, $event)"
      @keydown="handleKeydown(4, $event)"
      @paste="handlePaste"
      class="h-12 w-12 rounded-lg border-2 border-gray-300 text-center text-2xl font-semibold focus:border-brand-500 focus:outline-none focus:ring-2 focus:ring-brand-500 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:focus:border-brand-500"
      aria-label="Digit 5"
    />
    <input
      ref="input6"
      v-model="digit6"
      type="text"
      inputmode="numeric"
      maxlength="1"
      :disabled="disabled"
      @input="handleInput(5, $event)"
      @keydown="handleKeydown(5, $event)"
      @paste="handlePaste"
      class="h-12 w-12 rounded-lg border-2 border-gray-300 text-center text-2xl font-semibold focus:border-brand-500 focus:outline-none focus:ring-2 focus:ring-brand-500 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:focus:border-brand-500"
      aria-label="Digit 6"
    />
  </div>
</template>
