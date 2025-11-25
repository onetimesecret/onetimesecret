<script setup lang="ts">
import type { IncomingRecipient } from '@/schemas/api/incoming';
import { computed, ref, watch } from 'vue';

const { t } = useI18n();

export interface Props {
  modelValue: string;
  recipients: IncomingRecipient[];
  error?: string | null;
  disabled?: boolean;
  loading?: boolean;
}

const props = withDefaults(defineProps<Props>(), {
  recipients: () => [],
  error: null,
  disabled: false,
  loading: false,
});

const emit = defineEmits<{
  (e: 'update:modelValue', value: string): void;
  (e: 'change', recipient: IncomingRecipient | null): void;
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
  const selected = props.recipients.find((r) => r.hash === newVal) ?? null;
  emit('change', selected);
});

const hasRecipients = computed(() => props.recipients.length > 0);

const selectClasses = computed(() => [
  'w-full rounded-md border px-4 py-2',
  'focus:outline-none focus:ring-2',
  'appearance-none bg-white',
  props.error
    ? 'border-red-300 focus:border-red-500 focus:ring-red-500 dark:border-red-600'
    : 'border-gray-300 focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600',
  'dark:bg-gray-700 dark:text-gray-200',
  props.disabled || props.loading ? 'cursor-not-allowed opacity-50' : 'cursor-pointer',
]);
</script>

<template>
  <div class="space-y-1">
    <label
      for="incoming-recipient"
      class="block text-sm font-medium text-gray-700 dark:text-gray-300">
      {{ t('incoming.recipient_label') }}
    </label>

    <div class="relative">
      <select
        id="incoming-recipient"
        v-model="localValue"
        :disabled="disabled || loading || !hasRecipients"
        :class="selectClasses"
        :aria-label="t('incoming.recipient_aria_label')"
        :aria-describedby="error ? 'recipient-error' : 'recipient-hint'">
        <option
          value=""
          disabled>
          {{
            loading
              ? t('incoming.loading_config')
              : hasRecipients
                ? t('incoming.recipient_placeholder')
                : t('incoming.no_recipients_available')
          }}
        </option>
        <option
          v-for="recipient in recipients"
          :key="recipient.hash"
          :value="recipient.hash">
          {{ recipient.name }}
        </option>
      </select>

      <!-- Dropdown arrow icon -->
      <div
        class="pointer-events-none absolute inset-y-0 right-0 flex items-center pr-3 text-gray-500 dark:text-gray-400">
        <svg
          class="size-5"
          xmlns="http://www.w3.org/2000/svg"
          viewBox="0 0 20 20"
          fill="currentColor"
          aria-hidden="true">
          <path
            fill-rule="evenodd"
            d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z"
            clip-rule="evenodd" />
        </svg>
      </div>
    </div>

    <p
      v-if="error"
      id="recipient-error"
      class="text-xs text-red-600 dark:text-red-400">
      {{ error }}
    </p>
    <p
      v-else
      id="recipient-hint"
      class="text-xs text-gray-500 dark:text-gray-400">
      {{ t('incoming.recipient_hint') }}
    </p>
  </div>
</template>
