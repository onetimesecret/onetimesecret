<script setup lang="ts">
import OIcon from '@/components/icons/OIcon.vue';
import { defineEmits } from 'vue';

// Define the props expected from the parent
defineProps<{
  modelValue: string;
  placeholder: string;
  isValid: boolean | null;
}>();

// Define the emits to notify the parent of updates
const emit = defineEmits<{
  (e: 'update:modelValue', value: string): void;
}>();

// Handle the input event and emit the updated value
const onInput = (event: Event) => {
  const target = event.target as HTMLInputElement;
  emit('update:modelValue', target.value);
};
</script>

<template>
  <div>
    <label
      for="domain"
      class="hidden bg-inherit text-xl font-medium leading-6 text-gray-900 dark:text-gray-100"
      aria-hidden="false">
      {{ $t('domain-name') }}
    </label>
    <div class="relative mt-2 rounded-md shadow-sm">
      <input
        type="text"
        name="domain"
        id="domain"
        :placeholder="placeholder"
        :aria-invalid="isValid === false"
        aria-describedby="domain-error"
        :value="modelValue"
        @input="onInput"
        class="block w-full rounded-md border-0 py-3 pl-5 pr-10
          text-xl text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300
          placeholder:text-gray-400 focus:ring-2 focus:ring-inset focus:ring-brandcomp-600
          dark:bg-gray-700 dark:text-white dark:ring-gray-600 dark:placeholder:text-gray-400 dark:focus:ring-brandcomp-500"
      />
      <div class="pointer-events-none absolute inset-y-0 right-0 flex items-center pr-3">
        <OIcon
          v-if="isValid === false"
          collection="heroicons"
          name="exclamation-circle"
          class="size-6 text-red-500"
          aria-hidden="true"
        />
      </div>
    </div>
  </div>
</template>
