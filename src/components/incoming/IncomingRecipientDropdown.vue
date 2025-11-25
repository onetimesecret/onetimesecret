<!-- src/components/incoming/IncomingRecipientDropdown.vue -->

<script setup lang="ts">
  import { ref, computed } from 'vue';
  import { IncomingRecipient } from '@/schemas/api/incoming';
  import { useClickOutside } from '@/composables/useClickOutside';
  import { useI18n } from 'vue-i18n';

  const { t } = useI18n();
  const props = withDefaults(
    defineProps<{
      modelValue: string;
      recipients: IncomingRecipient[];
      error?: string;
      disabled?: boolean;
      placeholder?: string;
    }>(),
    {
      disabled: false,
      placeholder: 'Select a recipient',
    }
  );

  const emit = defineEmits<{
    'update:modelValue': [value: string];
    blur: [];
  }>();

  const isOpen = ref(false);
  const dropdownRef = ref<HTMLElement | null>(null);

  useClickOutside(dropdownRef, () => {
    isOpen.value = false;
  });

  const selectedRecipient = computed(() => props.recipients.find((r) => r.hash === props.modelValue));

  const displayText = computed(() => selectedRecipient.value?.name || props.placeholder);

  const statusColor = computed(() => {
    if (props.error) return 'border-red-500 focus:border-red-500 focus:ring-red-500';
    return 'border-gray-200 focus:border-blue-500 focus:ring-blue-500';
  });

  const toggleDropdown = () => {
    if (!props.disabled) {
      isOpen.value = !isOpen.value;
    }
  };

  const selectRecipient = (recipientId: string) => {
    emit('update:modelValue', recipientId);
    isOpen.value = false;
    emit('blur');
  };

  const handleKeydown = (event: KeyboardEvent) => {
    if (event.key === 'Escape') {
      isOpen.value = false;
    } else if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      toggleDropdown();
    }
  };
</script>

<template>
  <div
    ref="dropdownRef"
    class="w-full">
    <label
      for="incoming-recipient"
      class="mb-2 block text-sm font-medium text-gray-700 dark:text-gray-300">
      {{ t('incoming.recipient_label') }}
      <span
        v-if="error"
        class="text-red-500">
        *
      </span>
    </label>

    <div class="relative">
      <button
        id="incoming-recipient"
        type="button"
        :disabled="disabled"
        :class="[
          statusColor,
          'flex w-full items-center justify-between rounded-lg border px-4 py-3',
          'text-left text-base transition-all duration-200',
          'disabled:bg-gray-50 disabled:text-gray-500',
          'dark:bg-slate-800 dark:text-white',
          selectedRecipient ? 'text-gray-900 dark:text-white' : 'text-gray-400 dark:text-gray-500',
        ]"
        :aria-label="t('incoming.recipient_aria_label')"
        :aria-expanded="isOpen"
        :aria-invalid="!!error"
        :aria-describedby="error ? 'recipient-error' : undefined"
        @click="toggleDropdown"
        @keydown="handleKeydown">
        <span>{{ displayText }}</span>
        <svg
          :class="[
            'size-5 transition-transform duration-200',
            isOpen ? 'rotate-180' : '',
            'text-gray-400 dark:text-gray-500',
          ]"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M19 9l-7 7-7-7" />
        </svg>
      </button>

      <!-- Dropdown Menu -->
      <div
        v-if="isOpen && recipients.length > 0"
        class="absolute z-10 mt-1 w-full rounded-lg border border-gray-200 bg-white shadow-lg dark:border-gray-700 dark:bg-slate-800">
        <ul
          class="max-h-60 overflow-auto py-1"
          role="listbox">
          <li
            v-for="recipient in recipients"
            :key="recipient.hash"
            role="option"
            :aria-selected="modelValue === recipient.hash"
            :class="[
              'cursor-pointer px-4 py-2 transition-colors duration-150',
              modelValue === recipient.hash
                ? 'bg-blue-50 text-blue-700 dark:bg-blue-900/30 dark:text-blue-300'
                : 'text-gray-900 hover:bg-gray-50 dark:text-white dark:hover:bg-slate-700',
            ]"
            @click="selectRecipient(recipient.hash)">
            <div class="flex items-center justify-between">
              <span class="font-medium">{{ recipient.name }}</span>
              <svg
                v-if="modelValue === recipient.hash"
                class="size-5 text-blue-600 dark:text-blue-400"
                fill="currentColor"
                viewBox="0 0 20 20">
                <path
                  fill-rule="evenodd"
                  d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
                  clip-rule="evenodd" />
              </svg>
            </div>
          </li>
        </ul>
      </div>

      <!-- Empty State -->
      <div
        v-else-if="isOpen && recipients.length === 0"
        class="absolute z-10 mt-1 w-full rounded-lg border border-gray-200 bg-white p-4 text-center shadow-lg dark:border-gray-700 dark:bg-slate-800">
        <p class="text-sm text-gray-500 dark:text-gray-400">
          {{ t('incoming.no_recipients_available') }}
        </p>
      </div>

      <!-- Error Message -->
      <span
        v-if="error"
        id="recipient-error"
        class="mt-1 block text-sm text-red-600 dark:text-red-400">
        {{ error }}
      </span>
    </div>

    <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
      <!-- {{ t('incoming.recipient_hint') }} -->
    </p>
  </div>
</template>
