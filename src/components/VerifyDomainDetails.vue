<!-- _onetime-challenge-domainid -> 7709715a6411631ce1d447428d8a70  -->
<!-- _onetime-challenge-domainid.status -> cd94fec5a98fd33a0d70d069acaae9  -->
<template>
  <div class="max-w-lg p-6 mx-auto text-xl text-gray-900 bg-white rounded-lg shadow-lg dark:text-white dark:bg-gray-800">
    <div v-if="domain.verified"
         class="flex items-start p-4 mb-6 text-yellow-800 bg-yellow-100 rounded-md dark:text-yellow-300 dark:bg-yellow-900">
      <svg class="flex-shrink-0 w-6 h-6 mr-2"
           fill="none"
           stroke="currentColor"
           viewBox="0 0 24 24"
           xmlns="http://www.w3.org/2000/svg">
        <path stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z">
        </path>
      </svg>
      <p class="text-base">We were unable to verify ownership of {{ domain.display_domain }}. We couldn't find the TXT record. Note
        that DNS changes can take up to 24 hours.</p>
    </div>

    <h2 class="mb-4 text-xl font-bold">Add a DNS TXT record</h2>
    <p class="mb-4">Before we can verify {{ domain.display_domain }}, you'll need to complete these steps:</p>

    <ol class="mb-6 space-y-4 list-decimal list-inside">
      <li>
        Create a TXT record in your DNS configuration for the following hostname:
        <div class="flex items-center justify-between p-2 mt-2 bg-gray-100 rounded dark:bg-gray-700">
          <span>{{ domain.txt_validation_host }}.{{ domain.base_domain }}</span>
          <button @click="copyToClipboard(domain.txt_validation_host)"
                  class="text-gray-600 hover:text-gray-900 dark:text-gray-400 dark:hover:text-white">
            <svg class="w-5 h-5"
                 fill="none"
                 stroke="currentColor"
                 viewBox="0 0 24 24"
                 xmlns="http://www.w3.org/2000/svg">
              <path stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z">
              </path>
            </svg>
          </button>
        </div>
      </li>
      <li>
        Use this code for the value of the TXT record:
        <div class="flex items-center justify-between p-2 mt-2 bg-gray-100 rounded dark:bg-gray-700">
          <span>{{ domain.txt_validation_value }}</span>
          <button @click="copyToClipboard(domain.txt_validation_value)"
                  class="text-gray-600 hover:text-gray-900 dark:text-gray-400 dark:hover:text-white">
            <svg class="w-5 h-5"
                 fill="none"
                 stroke="currentColor"
                 viewBox="0 0 24 24"
                 xmlns="http://www.w3.org/2000/svg">
              <path stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z">
              </path>
            </svg>
          </button>
        </div>
      </li>
      <li>Wait until your DNS configuration changes. This could take up to 24 hours to propagate.</li>
    </ol>

    <button @click="verify"
            class="px-4 py-2 font-bold text-white bg-green-600 rounded hover:bg-green-700 dark:bg-green-700 dark:hover:bg-green-800">
      Verify
    </button>
  </div>
</template>


<script setup lang="ts">
//import { ref } from 'vue';
import { defineProps } from 'vue';
import { CustomDomain } from '@/types/onetime';

defineProps({
  domain: { type: Object as () => CustomDomain, required: true },
})

const copyToClipboard = (text: string) => {
  navigator.clipboard.writeText(text);
  // You might want to add a toast or notification here to inform the user that the text was copied
};

const verify = () => {
  // Implement verification logic here
  console.log('Verifying DNS TXT record...');
};
</script>
