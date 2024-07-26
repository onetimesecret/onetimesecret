
  <!-- We were unable to verify ownership of quantified.guru. We couldn't find the TXT record. Note that DNS changes can take up to 24 hours. -->
<template>
  <div>
    <h3 for="domain"
            class="text-ba2se block font-medium leading-6 text-gray-900">Add a domain</h3>
    <div class="relative mt-2 rounded-md shadow-lg">
      <input type="text"
              name="domain"
              id="domain"
              class="ring-1 ring-inset ring-brandcomp-300 placeholder:text-gray-300 focus:ring-2 focus:ring-inset focus:ring-brandcomp-500 sm:leading-9 text-brandcomp-900 block w-full py-3 pl-5 pr-10 text-xl border-0 rounded-md"
              :placeholder="placeholder"
              :value="domain"
              :aria-invalid="!isValid"
              aria-describedby="domain-error" />

      <div class="absolute inset-y-0 right-0 flex items-center pr-3 pointer-events-none">
        <Icon icon="heroicons:exclamation-circle"
              class="hidden w-6 h-6 text-gray-500"
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
