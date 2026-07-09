<!-- src/apps/workspace/components/domains/DomainInput.vue -->

<script setup lang="ts">
import OIcon from '@/shared/components/icons/OIcon.vue';
import { computed, onMounted, ref } from 'vue';

// Define the props expected from the parent. The visible <label> now lives in
// the parent (DomainForm) so there is exactly one label bound to #domain; the
// describing help/error element id is passed in via `describedby`.
const props = defineProps<{
  modelValue: string;
  placeholder: string;
  isValid: boolean | null;
  /** id of the element(s) that describe this input (help/error text). */
  describedby?: string;
  /** Focus the input on mount. Applied to the real <input>, not the wrapper. */
  autofocus?: boolean;
}>();

// Define the emits to notify the parent of updates
const emit = defineEmits<{
  (e: 'update:modelValue', value: string): void;
}>();

// A template ref so `autofocus` reliably lands on the input in an SPA — the
// native attribute only fires on a full page load, not on component mount.
const inputEl = ref<HTMLInputElement | null>(null);
onMounted(() => {
  if (props.autofocus) inputEl.value?.focus();
});

// Ring color reflects state: brand (blue) to match the rest of the form and the
// app-wide input convention, red when the parent flags the value invalid. The
// structural ring utilities (width/inset) stay static on the input itself.
const ringClasses = computed(() =>
  props.isValid === false
    ? 'ring-red-500 focus:ring-red-500 dark:ring-red-500 dark:focus:ring-red-400'
    : 'ring-gray-300 focus:ring-brand-500 dark:ring-gray-600 dark:focus:ring-brand-400'
);

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
        ref="inputEl"
        type="text"
        name="domain"
        id="domain"
        :placeholder="placeholder"
        :aria-invalid="isValid === false"
        :aria-describedby="describedby"
        :value="modelValue"
        @input="onInput"
        :class="ringClasses"
        class="block w-full rounded-md border-0 py-3 pr-10 pl-5
          text-xl text-gray-900 shadow-sm ring-1 ring-inset
          placeholder:text-gray-400 focus:ring-2 focus:ring-inset
          dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-400" />
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
