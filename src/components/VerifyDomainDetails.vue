<!-- _onetime-challenge-domainid -> 7709715a6411631ce1d447428d8a70  -->
<!-- _onetime-challenge-domainid.status -> cd94fec5a98fd33a0d70d069acaae9  -->
<template>
  <div class="max-w-2xl mx-auto p-6 bg-white dark:bg-gray-800 rounded-xl shadow-lg">

    <!--<h2 class="text-2xl font-bold mb-4 text-gray-800 dark:text-white">Card Title</h2>
    <p class="text-lg mb-6 text-gray-600 dark:text-gray-300">Intro text for this card</p>-->

    <BasicFormAlerts :success="success" :error="error" />

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

    <button @click="verify"
          :disabled="isButtonDisabled"
          class="w-full sm:w-auto px-6 py-3 text-lg font-semibold
            text-white bg-brand-500
            disabled:bg-gray-400 disabled:cursor-not-allowed
            hover:bg-brand-600
            rounded-lg transition duration-100 ease-in-out">
      {{ isSubmitting ? 'Verifying...' : 'Verify Domain' }}
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
import { useFormSubmission } from '@/utils/formSubmission';
import { Icon } from '@iconify/vue';
import { ref, computed } from 'vue';
import DetailField from './DetailField.vue';
import BasicFormAlerts from './BasicFormAlerts.vue';
const shrimp = ref(window.shrimp);

interface Props {
  domain: CustomDomain;
  cluster: CustomDomainCluster;
}

const props = withDefaults(defineProps<Props>(), {
  domain: () => ({} as CustomDomain),
  cluster: () => ({} as CustomDomainCluster),
});

const handleShrimp = (freshShrimp: string) => {
  shrimp.value = freshShrimp;
}

const { isSubmitting, error, success, submitForm } = useFormSubmission({
  url: `/api/v1/account/domains/${props.domain.display_domain}/verify`,
  successMessage: 'Domain verification initiated successfully.',
  getFormData: () => new URLSearchParams({
    domain: props.domain.display_domain,
    shrimp: shrimp.value,
  }),
  onSuccess: (data) => {
    console.log('Verification initiated:', data);
  },
  onError: (data) => {
    console.error('Verification failed:', data);
  },
  handleShrimp: handleShrimp,
});

const buttonDisabledDelay = ref(false);
const isButtonDisabled = computed(() => isSubmitting.value || buttonDisabledDelay.value);

const verify = () => {
  // Implement verification logic here
  console.info('Verifying DNS TXT record...');
  submitForm().finally(() => {
    buttonDisabledDelay.value = true;
    setTimeout(() => {
      buttonDisabledDelay.value = false;
    }, 10000); // 4 seconds
  });
};
</script>
