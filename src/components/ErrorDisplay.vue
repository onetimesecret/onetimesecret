<script setup lang="ts">
import type { ApplicationError } from '@/schemas/errors';
import { computed } from 'vue';
import { ZodError } from 'zod';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const props = defineProps<{
  error: ApplicationError;
}>();

const isZodError = computed(() => props.error.cause instanceof ZodError);
const friendlyMessage = computed(() => {
  if (!isZodError.value) return props.error.message;
  return t('unable-to-load-data-due-to-data-format-issues-pl');
});
</script>

<template>
  <div class="rounded-md bg-red-50 p-4 dark:bg-red-900/20">
    <div class="flex items-start">
      <svg
        class="size-5 text-red-400 dark:text-red-300"
        xmlns="http://www.w3.org/2000/svg"
        viewBox="0 0 20 20"
        fill="currentColor">
        <path
          fill-rule="evenodd"
          d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.28 7.22a.75.75 0 00-1.06 1.06L8.94 10l-1.72 1.72a.75.75 0 101.06 1.06L10 11.06l1.72 1.72a.75.75 0 101.06-1.06L11.06 10l1.72-1.72a.75.75 0 00-1.06-1.06L10 8.94 8.28 7.22z"
          clip-rule="evenodd"
        />
      </svg>
      <p class="ml-3 text-sm font-medium text-red-800 dark:text-red-200">
        {{ friendlyMessage }}
      </p>
    </div>
  </div>
</template>
