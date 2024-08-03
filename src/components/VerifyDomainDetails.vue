<!-- _onetime-challenge-domainid -> 7709715a6411631ce1d447428d8a70  -->
<!-- _onetime-challenge-domainid.status -> cd94fec5a98fd33a0d70d069acaae9  -->
<template>
  <div class="max-w-2xl mx-auto p-6 bg-white dark:bg-gray-800 rounded-xl shadow-lg">
    <div v-if="domain.verified" class="mb-6 p-4 bg-yellow-100 dark:bg-yellow-900 rounded-lg">
      <div class="flex items-start">
        <svg class="w-6 h-6 text-yellow-600 dark:text-yellow-400 mr-3 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg" width="24" height="24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"></path>
        </svg>
        <p class="text-yellow-800 dark:text-yellow-200">We were unable to verify ownership of {{ domain.display_domain }}. We couldn't find the TXT record. Note that DNS changes can take up to 24 hours.</p>
      </div>
    </div>

    <h2 class="text-2xl font-bold mb-4 text-gray-800 dark:text-white">Add a DNS TXT record</h2>
    <p class="text-lg mb-6 text-gray-600 dark:text-gray-300">Before we can verify {{ domain.display_domain }}, you'll need to complete these steps:</p>

    <ol class="space-y-6 mb-8">
      <li class="bg-gray-50 dark:bg-gray-700 p-4 rounded-lg">
        <h3 class="font-semibold text-lg mb-2 text-gray-800 dark:text-white">1. Create a TXT record</h3>
        <p class="mb-2 text-gray-600 dark:text-gray-300">Add this hostname to your DNS configuration:</p>
        <div class="flex items-center justify-between p-3 bg-white dark:bg-gray-600 rounded-md">
          <span ref="hostSpan" class="text-gray-800 dark:text-gray-200">{{ domain.txt_validation_host }}<span class="text-gray-400">.{{ domain.base_domain }}</span></span>
          <CopyButton :text="domain.txt_validation_host" />
        </div>
      </li>
      <li class="bg-gray-50 dark:bg-gray-700 p-4 rounded-lg">
        <h3 class="font-semibold text-lg mb-2 text-gray-800 dark:text-white">2. Set the TXT record value</h3>
        <p class="mb-2 text-gray-600 dark:text-gray-300">Use this code for the value of the TXT record:</p>
        <div class="flex items-center justify-between p-3 bg-white dark:bg-gray-600 rounded-md">
          <span ref="valueSpan" class="text-gray-800 dark:text-gray-200">{{ domain.txt_validation_value }}</span>
          <CopyButton :text="domain.txt_validation_value" />
        </div>
      </li>
      <li class="bg-gray-50 dark:bg-gray-700 p-4 rounded-lg">
        <h3 class="font-semibold text-lg mb-2 text-gray-800 dark:text-white">3. Wait for propagation</h3>
        <p class="text-gray-600 dark:text-gray-300">DNS changes can take up to 24 hours to propagate.</p>
      </li>
    </ol>

    <button @click="verify" class="w-full sm:w-auto px-6 py-3 text-lg font-semibold text-white bg-brand-500 hover:bg-brand-600 rounded-lg transition duration-300 ease-in-out">
      Verify Domain
    </button>
  </div>
</template>



<script setup lang="ts">
import { ref } from 'vue';
import { CustomDomain } from '@/types/onetime';
import CopyButton from '@/components/CopyButton.vue';

defineProps({
  domain: { type: Object as () => CustomDomain, required: true },
})


const hostSpan = ref<HTMLSpanElement | null>(null);
const valueSpan = ref<HTMLSpanElement | null>(null);

const verify = () => {
  // Implement verification logic here
  console.log('Verifying DNS TXT record...');
};
</script>
