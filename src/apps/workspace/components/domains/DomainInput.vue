<!-- src/apps/workspace/components/domains/DomainInput.vue -->

<script setup lang="ts">
import OIcon from '@/shared/components/icons/OIcon.vue';

// Define the props expected from the parent. The visible <label> now lives in
// the parent (DomainForm) so there is exactly one label bound to #domain; the
// describing help/error element id is passed in via `describedby`.
defineProps<{
  modelValue: string;
  placeholder: string;
  isValid: boolean | null;
  /** id of the element(s) that describe this input (help/error text). */
  describedby?: string;
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
    <div class="relative mt-2 rounded-md shadow-sm">
      <input
        type="text"
        name="domain"
        id="domain"
        :placeholder="placeholder"
        :aria-invalid="isValid === false"
        :aria-describedby="describedby"
        :value="modelValue"
        @input="onInput"
        class="block w-full rounded-md border-0 py-3 pr-10 pl-5
          text-xl text-gray-900 shadow-sm ring-1 ring-gray-300 ring-inset
          placeholder:text-gray-400 focus:ring-2 focus:ring-brandcomp-600 focus:ring-inset
          dark:bg-gray-700 dark:text-white dark:ring-gray-600 dark:placeholder:text-gray-400 dark:focus:ring-brandcomp-500" />
      <div class="pointer-events-none absolute inset-y-0 right-0 flex items-center pr-3">
        <OIcon
          v-if="isValid === false"
          collection="heroicons"
          name="exclamation-circle"
          class="size-6 text-red-500"
          aria-hidden="true" />
      </div>
    </div>
  </div>
</template>
