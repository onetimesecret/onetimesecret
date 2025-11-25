<script setup lang="ts">
import { computed, ref, watch } from 'vue';

const { t } = useI18n();

export interface Props {
  modelValue: string;
  maxLength?: number;
  error?: string | null;
  disabled?: boolean;
}

const props = withDefaults(defineProps<Props>(), {
  maxLength: 50,
  error: null,
  disabled: false,
});

const emit = defineEmits<{
  (e: 'update:modelValue', value: string): void;
}>();

const localValue = ref(props.modelValue);

// Watch for external changes
watch(
  () => props.modelValue,
  (newVal) => {
    localValue.value = newVal;
  }
);

// Update parent on local changes
watch(localValue, (newVal) => {
  emit('update:modelValue', newVal);
});

const charCount = computed(() => localValue.value.length);
const isNearLimit = computed(() => charCount.value >= props.maxLength * 0.8);
const isOverLimit = computed(() => charCount.value > props.maxLength);

const inputClasses = computed(() => [
  'w-full rounded-md border px-4 py-2',
  'focus:outline-none focus:ring-2',
  props.error || isOverLimit.value
    ? 'border-red-300 focus:border-red-500 focus:ring-red-500 dark:border-red-600'
    : 'border-gray-300 focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600',
  'dark:bg-gray-700 dark:text-gray-200',
  props.disabled ? 'cursor-not-allowed opacity-50' : '',
]);
</script>

<template>
  <div class="space-y-1">
    <label
      for="incoming-memo"
      class="block text-sm font-medium text-gray-700 dark:text-gray-300">
      {{ t('incoming.memo_label') }}
    </label>

    <input
      id="incoming-memo"
      v-model="localValue"
      type="text"
      :maxlength="maxLength + 10"
      :disabled="disabled"
      :class="inputClasses"
      :placeholder="t('incoming.memo_placeholder')"
      :aria-describedby="error ? 'memo-error' : 'memo-hint'" />

    <div class="flex items-center justify-between">
      <p
        v-if="error"
        id="memo-error"
        class="text-xs text-red-600 dark:text-red-400">
        {{ error }}
      </p>
      <p
        v-else
        id="memo-hint"
        class="text-xs text-gray-500 dark:text-gray-400">
        {{ t('incoming.memo_hint') }}
      </p>

      <span
        :class="[
          'text-xs',
          isOverLimit
            ? 'text-red-600 dark:text-red-400'
            : isNearLimit
              ? 'text-yellow-600 dark:text-yellow-400'
              : 'text-gray-500 dark:text-gray-400',
        ]">
        {{ charCount }}/{{ maxLength }}
      </span>
    </div>
  </div>
</template>
