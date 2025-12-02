<!-- src/components/incoming/IncomingMemoInput.vue -->

<script setup lang="ts">
  import { computed } from 'vue';
  import { useI18n } from 'vue-i18n';

  const { t } = useI18n();
  const props = withDefaults(
    defineProps<{
      modelValue: string;
      maxLength?: number;
      error?: string;
      disabled?: boolean;
      placeholder?: string;
    }>(),
    {
      maxLength: 50,
      disabled: false,
    }
  );

  const emit = defineEmits<{
    'update:modelValue': [value: string];
    blur: [];
  }>();

  const placeholderText = computed(() => props.placeholder || t('incoming.memo_placeholder'));
  const charCount = computed(() => props.modelValue.length);
  const isNearLimit = computed(() => charCount.value > props.maxLength * 0.8);
  const isAtLimit = computed(() => charCount.value >= props.maxLength);

  const statusColor = computed(() => {
    if (props.error) return 'border-red-500 focus:border-red-500 focus:ring-red-500';
    if (isAtLimit.value) return 'border-amber-500 focus:border-amber-500 focus:ring-amber-500';
    return 'border-gray-200 focus:border-blue-500 focus:ring-blue-500';
  });

  const counterColor = computed(() => {
    if (isAtLimit.value) return 'text-amber-600 dark:text-amber-400';
    if (isNearLimit.value) return 'text-gray-600 dark:text-gray-400';
    return 'text-gray-500 dark:text-gray-500';
  });

  const handleInput = (event: Event) => {
    const target = event.target as HTMLInputElement;
    emit('update:modelValue', target.value);
  };

  const handleBlur = () => {
    emit('blur');
  };
</script>

<template>
  <div class="w-full">
    <label
      for="incoming-memo"
      class="mb-2 block text-sm font-medium text-gray-700 dark:text-gray-300">
      {{ t('incoming.memo_label') }}
      <span
        v-if="error"
        class="text-red-500">
        *
      </span>
    </label>

    <div class="relative">
      <input
        id="incoming-memo"
        type="text"
        :value="modelValue"
        :maxlength="maxLength"
        :disabled="disabled"
        :placeholder="placeholderText"
        :class="[
          statusColor,
          'block w-full rounded-lg border px-4 py-3 text-base text-gray-900',
          'transition-all duration-200',
          'placeholder:text-gray-400',
          'disabled:bg-gray-50 disabled:text-gray-500',
          'dark:bg-slate-800 dark:text-white dark:placeholder:text-gray-500',
          'dark:focus:ring-blue-400',
        ]"
        :aria-label="t('incoming.memo_placeholder')"
        :aria-invalid="!!error"
        :aria-describedby="error ? 'memo-error' : 'memo-counter'"
        @input="handleInput"
        @blur="handleBlur" />

      <div
        v-if="isNearLimit || error"
        class="mt-1 flex items-center justify-between">
        <span
          v-if="error"
          id="memo-error"
          class="text-sm text-red-600 dark:text-red-400">
          {{ error }}
        </span>
        <span
          v-if="isNearLimit"
          id="memo-counter"
          :class="[counterColor, 'ml-auto text-sm']">
          {{ charCount }} / {{ maxLength }}
        </span>
      </div>
    </div>

    <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
      <!-- {{ t('incoming.memo_hint') }} -->
    </p>
  </div>
</template>
