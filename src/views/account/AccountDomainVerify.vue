
<template>
  <main class="container mx-auto px-4 py-8">
    <h1 class="text-3xl font-bold mb-6 text-gray-900 dark:text-white">Add your domain</h1>

    <p class="text-lg mb-6 text-gray-600 dark:text-gray-300">
      Before we can activate links for
      <span class=" bg-white dark:bg-gray-800  text-brand-600 dark:text-brand-400">{{ domain?.display_domain }}</span>,
      you'll need to complete these steps.
    </p>

    <MoreInfoText textColor="text-brandcomp-800 dark:text-gray-100" bgColor="bg-white dark:bg-gray-800">
      <div class="px-6 py-6">
        <div class="max-w-xl text-base text-gray-600 dark:text-gray-300">
          <p>
            In order to connect your domain, you'll need to have a DNS A record that points
            <span class="font-bold bg-white dark:bg-gray-800 px-2 text-brand-600 dark:text-brand-400">{{ domain?.display_domain }}</span> at <span
                  :title="cluster?.cluster_name?? ''" class="bg-white dark:bg-gray-800 px-2">{{ cluster?.cluster_ip }}</span>. If you already have an A record for
            that
            address, please change it to point at <span :title="cluster?.cluster_name?? ''" class="bg-white dark:bg-gray-800 px-2">{{ cluster?.cluster_ip }}</span>
            and remove any other A, AAAA,
            or CNAME records for that exact address.
          </p>
        </div>
        <div class="mt-4 text-sm">
          <a href="#"
             class="font-medium text-brandcomp-600 hover:text-brandcomp-500 dark:text-brandcomp-400 dark:hover:text-brandcomp-300">
            <!--Learn more about DNS configuration <span aria-hidden="true">&rarr;</span>-->
          </a>
        </div>
      </div>
    </MoreInfoText>

    <DomainVerificationInfo v-if="domain?.vhost?.incoming_address" :domain="domain" />

    <VerifyDomainDetails v-if="domain && cluster" :domain="domain" :cluster="cluster" />
    <p v-else class="text-gray-600 dark:text-gray-400">Loading domain information...</p>

  </main>
</template>


<script setup lang="ts">
import MoreInfoText from "@/components/MoreInfoText.vue";
import VerifyDomainDetails from '@/components/VerifyDomainDetails.vue';
import { CustomDomain, CustomDomainApiResponse, CustomDomainCluster } from '@/types/onetime';
import { onMounted, ref } from 'vue';
import { useRoute } from 'vue-router';
import DomainVerificationInfo from '@/components/DomainVerificationInfo.vue';

//const props = defineProps<{ domain?: CustomDomain }>();

const route = useRoute();
const domain = ref<CustomDomain | null>(null);
const cluster = ref<CustomDomainCluster | null>(null);

console.log("VerifyDomain.ts", route.params.domain );

const fetchDomain = async (): Promise<void> => {
  const domainName: string = route.params.domain as string;
  try {
    const response: Response = await fetch(`/api/v1/account/domains/${domainName}`);
    if (!response.ok) {
      throw new Error('Failed to fetch domain information');
    }
    const data: CustomDomainApiResponse = await response.json();
    domain.value = data.record as CustomDomain;
    if (data.details) {
      cluster.value = data.details?.cluster;
    }

    console.debug('data', data)
  } catch (error) {
    console.error('Error fetching domain:', error);
    // Handle error (e.g., show error message to user)
  }
};

onMounted(() => {
  console.log('AccountDomainVerify component mounted');
  console.log('Domain parameter:', route.params.domain);
  fetchDomain();

});

</script>
