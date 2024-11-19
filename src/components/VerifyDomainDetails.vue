<template>
  <div class="max-w-2xl mx-auto p-6 bg-white dark:bg-gray-800 rounded-xl shadow-lg">

    <h2 class="text-2xl font-bold mb-4 text-gray-800 dark:text-white">Domain Verification Steps</h2>
    <p class="text-lg mb-6 text-gray-600 dark:text-gray-300">Follow these steps to verify domain ownership and elevate
      your online presence:</p>

    <BasicFormAlerts :success="success"
                     :error="error" />

    <div class="flex justify-end mb-4">
      <button v-if="withVerifyCTA"
              @click="verify"
              :disabled="isButtonDisabled"
              class="flex items-center gap-2 px-6 py-3 text-lg font-semibold
          text-white bg-brand-500
          disabled:bg-gray-400 disabled:cursor-not-allowed
          hover:bg-brand-600
          rounded-lg transition duration-100 ease-in-out">
        <span>{{ isSubmitting ? 'Verifying...' : 'Verify Domain' }}</span>
        <Icon :icon="isSubmitting ? 'mdi:loading' : 'mdi:check-circle'"
              class="h-5 w-5"
              :class="{ 'animate-spin': isSubmitting }"
              aria-hidden="true" />
      </button>
    </div>


    <ol class="space-y-6 mb-8">
      <li class="bg-gray-50 dark:bg-gray-700 p-4 rounded-lg">
        <h3 class="font-semibold text-lg mb-2 text-gray-800 dark:text-white">1. Create a TXT record</h3>
        <p class="mb-2 text-gray-600 dark:text-gray-300">Add this hostname to your DNS configuration:</p>

        <div class="space-y-2">
          <DetailField label="Type"
                       value="TXT" />
          <DetailField label="Host"
                       :value="domain.txt_validation_host"
                       :appendix="`.${domain.base_domain}`" />
          <DetailField label="Value"
                       :value="domain.txt_validation_value" />
        </div>

      </li>
      <li v-if="domain?.is_apex"
          class="bg-gray-50 dark:bg-gray-700 p-4 rounded-lg">
        <h3 class="font-semibold text-lg mb-2 text-gray-800 dark:text-white">2. Create the A record</h3>

        <div class="space-y-2">
          <DetailField label="Type"
                       value="A" />
          <DetailField label="Host"
                       :value="domain?.trd ? domain.trd : '@'"
                       :appendix="`.${domain?.base_domain}`" />
          <DetailField label="Value"
                       :value="cluster?.cluster_ip" />
        </div>
      </li>
      <li v-else
          class="bg-gray-50 dark:bg-gray-700 p-4 rounded-lg">
        <h3 class="font-semibold text-lg mb-2 text-gray-800 dark:text-white">2. Create the CNAME record</h3>

        <div class="space-y-2">
          <DetailField v-if="domain?.is_apex"
                       label="Type"
                       value="A" />
          <DetailField v-else
                       label="Type"
                       value="CNAME" />

          <DetailField label="Host"
                       :value="domain?.trd ? domain.trd : '@'"
                       :appendix="`.${domain?.base_domain}`" />
          <DetailField v-if="domain?.is_apex"
                       label="Value"
                       :value="cluster?.cluster_ip" />
          <DetailField v-else
                       label="Value"
                       :value="cluster?.cluster_host" />
        </div>
      </li>
      <li class="bg-gray-50 dark:bg-gray-700 p-4 rounded-lg">
        <h3 class="font-semibold text-lg mb-2 text-gray-800 dark:text-white">3. Wait for propagation</h3>
        <p class="text-gray-600 dark:text-gray-300">DNS changes can take as little as 60 seconds -- or up to 24 hours --
          to take effect.</p>
      </li>
    </ol>

    <div class="mt-5 flex items-start bg-white dark:bg-gray-800 p-4 rounded-md">
      <Icon icon="mdi:information-outline"
            class="h-5 w-5 text-brandcomp-700 mr-2 mt-0.5 flex-shrink-0"
            aria-hidden="true" />
      <p class="text-sm text-gray-500 dark:text-gray-400">
        It may take a few minutes for your SSL certificate to take effect.
      </p>
    </div>
  </div>

</template>

<script setup lang="ts">
import { CustomDomain, CustomDomainApiResponse, CustomDomainCluster } from '@/types/onetime';
import { useFormSubmission } from '@/composables/useFormSubmission';
import { Icon } from '@iconify/vue';
import { computed, ref } from 'vue';
import BasicFormAlerts from './BasicFormAlerts.vue';
import DetailField from './DetailField.vue';


interface Props {
  domain: CustomDomain;
  cluster: CustomDomainCluster;
  withVerifyCTA?: boolean;
}

const props = withDefaults(defineProps<Props>(), {
  domain: () => ({} as CustomDomain),
  cluster: () => ({} as CustomDomainCluster),
  withVerifyCTA: false,
});

// Define the emit function with the type
const emit = defineEmits<{
  (e: 'domainVerify', data: CustomDomainApiResponse): void;
}>();

const { isSubmitting, error, success, submitForm } = useFormSubmission({
  url: `/api/v2/account/domains/${props.domain.display_domain}/verify`,
  successMessage: 'Domain verification initiated successfully.',
  getFormData: () => new URLSearchParams({
    domain: props.domain.display_domain,
  }),
  onSuccess: (data) => {
    console.log('Verification initiated:', data);
    emit('domainVerify', data);
  },
  onError: (data) => {
    console.error('Verification failed:', data);
  },
});

const buttonDisabledDelay = ref(false);
const isButtonDisabled = computed(() => isSubmitting.value || buttonDisabledDelay.value);

const verify = () => {
  // Implement verification logic here
  console.info('Refreshing DNS verification details...');

  submitForm().finally(() => {

    buttonDisabledDelay.value = true;
    setTimeout(() => {
      buttonDisabledDelay.value = false;
    }, 10000); // 4 seconds
  });
};
</script>
