
  <!-- We were unable to verify ownership of quantified.guru. We couldn't find the TXT record. Note that DNS changes can take up to 24 hours. -->
<template>
  <div>
    <label for="domain"
            class="block text-base font-medium leading-6 text-gray-900">Your Domain</label>
    <div class="relative mt-2 rounded-md shadow-lg">
      <input type="text"
              name="domain"
              id="domain"
              class="block w-full rounded-md border-0
              py-3 pr-10 text-red-900 ring-1 ring-inset ring-red-300 placeholder:text-red-300
              focus:ring-2 focus:ring-inset focus:ring-red-500 sm:leading-9 text-xl"
              :placeholder="placeholder"
              :value="domain"
              :aria-invalid="!isValid"
              aria-describedby="domain-error" />

      <div class="pointer-events-none absolute inset-y-0 right-0 flex items-center pr-3">
        <Icon icon="heroicons:exclamation-circle"
              class="h-6 w-6 text-red-500"
              aria-hidden="true" />
      </div>
    </div>
    <!--<p class="mt-2 text-base text-red-600"
        id="domain-error">Not a valid domain address.</p>-->
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
