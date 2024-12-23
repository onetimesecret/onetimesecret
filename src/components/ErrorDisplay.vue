<script setup lang="ts">
import type { ApiError } from '@/schemas/api/errors';
import { computed } from 'vue';
import { ZodError } from 'zod';

const props = defineProps<{
  error: ApiError;
}>();

const isZodError = computed(() => props.error.cause instanceof ZodError);
const friendlyMessage = computed(() => {
  if (!isZodError.value) return props.error.message;
  return "Unable to load the list due to data format issues. Please try again later.";
});
</script>

<template>
  <div class="my-4 rounded-md bg-red-50 p-4">
    <div class="flex">
      <div class="shrink-0">
        <svg
          class="size-5 text-red-400"
          xmlns="http://www.w3.org/2000/svg"
          viewBox="0 0 20 20"
          fill="currentColor">
          <path
            fill-rule="evenodd"
            d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.28 7.22a.75.75 0 00-1.06 1.06L8.94 10l-1.72 1.72a.75.75 0 101.06 1.06L10 11.06l1.72 1.72a.75.75 0 101.06-1.06L11.06 10l1.72-1.72a.75.75 0 00-1.06-1.06L10 8.94 8.28 7.22z"
            clip-rule="evenodd"
          />
        </svg>
      </div>
      <div class="ml-3">
        <h3 class="text-sm font-medium text-red-800">
          {{ friendlyMessage }}
        </h3>
      </div>
    </div>
  </div>
</template>
