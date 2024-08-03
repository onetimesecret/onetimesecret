<!-- _onetime-challenge-domainid -> 7709715a6411631ce1d447428d8a70  -->
<!-- _onetime-challenge-domainid.status -> cd94fec5a98fd33a0d70d069acaae9  -->
<template>
  <div class="max-w-2xl mx-auto p-6 bg-white dark:bg-gray-800 rounded-xl shadow-lg">

    <!--<h2 class="text-2xl font-bold mb-4 text-gray-800 dark:text-white"></h2>-->
    <!--<p class="text-lg mb-6 text-gray-600 dark:text-gray-300"></p>-->

    <ol class="space-y-6 mb-8">
      <li class="bg-gray-50 dark:bg-gray-700 p-4 rounded-lg">
        <h3 class="font-semibold text-lg mb-2 text-gray-800 dark:text-white">1. Create a TXT record</h3>
        <p class="mb-2 text-gray-600 dark:text-gray-300">Add this hostname to your DNS configuration:</p>

        <div class="space-y-2">
          <DetailField label="Type" value="TXT" />
          <DetailField
            label="Host"
            :value="domain.txt_validation_host"
            :appendix="`.${domain.base_domain}`"
          />
          <DetailField label="Value" :value="domain.txt_validation_value" />
        </div>

      </li>
      <li class="bg-gray-50 dark:bg-gray-700 p-4 rounded-lg">
        <h3 class="font-semibold text-lg mb-2 text-gray-800 dark:text-white">2. Create the A record</h3>

        <div class="space-y-2">
          <DetailField label="Type" value="A" />
          <DetailField
            label="Host"
            :value="domain?.trd ? domain.trd : '@'"
            :appendix="`.${domain?.base_domain}`"
          />
          <DetailField label="Value" :value="cluster?.cluster_ip" />
        </div>

      </li>
      <li class="bg-gray-50 dark:bg-gray-700 p-4 rounded-lg">
        <h3 class="font-semibold text-lg mb-2 text-gray-800 dark:text-white">3. Wait for propagation</h3>
        <p class="text-gray-600 dark:text-gray-300">DNS changes can take as little as 60 seconds -- or up to 24 hours -- to take effect.</p>
      </li>
    </ol>

    <button @click="verify" class="w-full sm:w-auto px-6 py-3 text-lg font-semibold text-white bg-brand-500 hover:bg-brand-600 rounded-lg transition duration-300 ease-in-out">
      Verify Domain
    </button>

    <div class="mt-5 flex items-start bg-white dark:bg-gray-800 p-4 rounded-md">
      <Icon icon="mdi:information-outline"
            class="h-5 w-5 text-brandcomp-700 mr-2 mt-0.5 flex-shrink-0"
            aria-hidden="true" />
      <p class="text-sm text-gray-500 dark:text-gray-400">
        It may take a few minutes for your SSL certificate to take effect once you've pointed your DNS A record.
      </p>
    </div>
  </div>

</template>

<script setup lang="ts">
import { CustomDomain, CustomDomainCluster } from '@/types/onetime';
import DetailField from './DetailField.vue';
import { Icon } from '@iconify/vue';

defineProps({
  domain: { type: Object as () => CustomDomain, required: true },
  cluster: { type: Object as () => CustomDomainCluster, required: true },
})

const verify = () => {
  // Implement verification logic here
  console.info('Verifying DNS TXT record...');
};
</script>
