
<template>
  <div class="">

    <DashboardTabNav />

    <h1 class="text-3xl font-bold mb-6 text-gray-900 dark:text-white">Verify your domain</h1>

    <DomainVerificationInfo
      v-if="domain?.vhost?.last_monitored_unix"
      :domain="domain"
      mode="table"
    />
    <p v-else class="text-lg mb-6 text-gray-600 dark:text-gray-300">
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

    <VerifyDomainDetails
      v-if="domain && cluster"
      :domain="domain"
      :cluster="cluster"
      :withVerifyCTA="allowVerifyCTA"
      @domainVerify="handleDomainVerify"
    />
    <p v-else class="text-gray-600 dark:text-gray-400">Loading domain information...</p>

  </div>
</template>

<script setup lang="ts">
import MoreInfoText from "@/components/MoreInfoText.vue";
import VerifyDomainDetails from '@/components/VerifyDomainDetails.vue';
import { CustomDomain, CustomDomainApiResponse, CustomDomainCluster } from '@/types/onetime';
import { onMounted, ref } from 'vue';
import { useRoute } from 'vue-router';
import DomainVerificationInfo from '@/components/DomainVerificationInfo.vue';
import DashboardTabNav from '@/components/dashboard/DashboardTabNav.vue';



const route = useRoute();
const domain = ref<CustomDomain | null>(null);
const cluster = ref<CustomDomainCluster | null>(null);

console.log("VerifyDomain.ts", route.params.domain );

const fetchDomain = async (): Promise<void> => {
  const domainName: string = route.params.domain as string;
  try {
    const response: Response = await fetch(`/api/v2/account/domains/${domainName}`);
    if (!response.ok) {
      throw new Error('Failed to fetch domain information');
    }

    const json: CustomDomainApiResponse = await response.json();
    console.debug('json', json);

    domain.value = json.record as CustomDomain;

    if (json.details) {
      cluster.value = json.details?.cluster;
    }
    const currentTime = Math.floor(Date.now() / 1000); // Current time in Unix time (seconds)

    const last_monitored_unix = (domain.value?.updated || currentTime) as number;

    if (last_monitored_unix) {

      const timeDifference = currentTime - last_monitored_unix;

      // If it's been at least N minutes since the most recent monitor
      // check for this domain, let's make sure the verify button is
      // enabled and ready for action.
      if (timeDifference >= 30) {
        console.debug("It has been at least 30 second since the last monitored time.", timeDifference);
        allowVerifyCTA.value = true;

      } else {
        console.debug('It has not been 30 seconds yet since the last monitored time.', timeDifference);
        allowVerifyCTA.value = false;
      }
    }
  } catch (error) {
    console.error('Error fetching domain:', error);
    // Handle error (e.g., show error message to user)
  }
};

const allowVerifyCTA = ref(false);

const handleDomainVerify = async (data: CustomDomainApiResponse) => {
  console.log('Domain verified: refreshing domain info', data);

  await fetchDomain();
};


onMounted(() => {
  console.log('AccountDomainVerify component mounted');
  console.log('Domain parameter:', route.params.domain);
  fetchDomain();

});

</script>
