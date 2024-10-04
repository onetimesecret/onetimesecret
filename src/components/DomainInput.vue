<template>
  <div>
    <label for="domain" class="hidden text-xl font-medium leading-6 text-gray-900 dark:text-gray-100 bg-inherit" aria-hidden="false">
      Domain name
    </label>
    <div class="relative mt-2 rounded-md shadow-sm">
      <input
        type="text"
        name="domain"
        id="domain"
        :value="domain"
        :placeholder="placeholder"
        :aria-invalid="!isValid"
        aria-describedby="domain-error"
        class="block w-full rounded-md border-0 py-3 pl-5 pr-10 text-xl text-gray-900 ring-1 ring-inset ring-gray-300 placeholder:text-gray-400 focus:ring-2 focus:ring-inset focus:ring-brandcomp-600 shadow-sm dark:bg-gray-700 dark:text-white dark:ring-gray-600 dark:placeholder:text-gray-400 dark:focus:ring-brandcomp-500"
      />
      <div class="pointer-events-none absolute inset-y-0 right-0 flex items-center pr-3">
        <Icon
          v-if="!isValid"
          icon="heroicons:exclamation-circle"
          class="h-6 w-6 text-red-500"
          aria-hidden="true"
        />
      </div>
    </div>
    <p v-if="!isValid" class="mt-2 text-sm text-red-600 dark:text-red-400" id="domain-error">
      Not a valid domain address.
    </p>
  </div>
</template>

<script setup lang="ts">
import { Icon } from '@iconify/vue';

defineProps<{
  domain: string;
  placeholder: string;
  isValid: boolean;
}>();
</script>
