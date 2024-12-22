<script setup lang="ts">
import DashboardTabNav from '@/components/dashboard/DashboardTabNav.vue';
import DomainVerificationInfo from '@/components/DomainVerificationInfo.vue';
import MoreInfoText from "@/components/MoreInfoText.vue";
import VerifyDomainDetails from '@/components/VerifyDomainDetails.vue';
import { type CustomDomainApiResponse, customDomainResponseSchema } from '@/schemas/api/responses';
import { onMounted, ref } from 'vue';
import { useRoute } from 'vue-router';


const route = useRoute();
const domain = ref<CustomDomain | null>(null);
const cluster = ref<{ cluster_host: string; cluster_name: string } | null>(null);

console.debug("VerifyDomain.ts", route.params.domain);

const allowVerifyCTA = ref(false);

const fetchDomain = async (): Promise<void> => {
  const domainName: string = route.params.domain as string;
  try {
    const response: Response = await fetch(`/api/v2/account/domains/${domainName}`);
    if (!response.ok) {
      throw new Error('Failed to fetch domain information');
    }

    const rawData = await response.json();
    const json = customDomainResponseSchema.parse(rawData);
    console.debug('json', json);

    domain.value = json.record;

    if (json.details?.cluster) {
      cluster.value = json.details.cluster as { cluster_host: string; cluster_name: string };
    }

    const currentTime = Math.floor(Date.now() / 1000);
    const last_monitored_unix = (domain.value?.updated || currentTime) as number;

    if (last_monitored_unix) {
      const timeDifference = currentTime - last_monitored_unix;

      // If it's been at least N minutes since the most recent monitor
      // check for this domain, let's make sure the verify button is
      // enabled and ready for action.
      if (timeDifference >= 30) {
        console.debug("It has been at least 30 seconds since the last monitored time.", timeDifference);
        allowVerifyCTA.value = true;
      } else {
        console.debug('It has not been 30 seconds yet since the last monitored time.', timeDifference);
        allowVerifyCTA.value = false;
      }
    }
  } catch (error) {
    console.error('Error fetching domain:', error);
  }
};

const handleDomainVerify = async (data: CustomDomainApiResponse) => {
  console.debug('Domain verified: refreshing domain info', data);
  await fetchDomain();
};

onMounted(() => {
  console.debug('AccountDomainVerify component mounted');
  console.debug('Domain parameter:', route.params.domain);
  fetchDomain();
});
</script>

<template>
  <div class="">
    <DashboardTabNav />

    <h1 class="mb-6 text-3xl font-bold text-gray-900 dark:text-white">
      Verify your domain
    </h1>

    <DomainVerificationInfo
      v-if="domain?.vhost?.last_monitored_unix"
      :domain="domain"
      mode="table"
    />
    <p
      v-else
      class="mb-6 text-lg text-gray-600 dark:text-gray-300">
      Before we can activate links for
      <span class=" bg-white text-brand-600  dark:bg-gray-800 dark:text-brand-400">{{ domain?.display_domain }}</span>,
      you'll need to complete these steps.
    </p>

    <MoreInfoText
      textColor="text-brandcomp-800 dark:text-gray-100"
      bgColor="bg-white dark:bg-gray-800">
      <div class="prose p-6">
        <div class="max-w-xl text-base text-gray-600 dark:text-gray-300">
          <p>
            In order to connect your domain, you'll need to have a CNAME record in your DNS that points
            <span
              class="bg-white px-2 font-bold text-brand-600 dark:bg-gray-800 dark:text-brand-400">{{ domain?.display_domain }}</span>
            at <span
              :title="cluster?.cluster_name ?? ''"
              class="bg-white px-2 dark:bg-gray-800">{{ cluster?.cluster_host }}</span>. If you already have
            a CNAME record for that address, please change it to point at
            <span
              :title="cluster?.cluster_name ?? ''"
              class="bg-white px-2 dark:bg-gray-800">{{ cluster?.cluster_host }}</span>
            and remove any other A, AAAA,
            or CNAME records for that exact address.
          </p>
          <p
            v-if="domain?.is_apex"
            class="border-l-4 border-yellow-500 bg-yellow-100 p-4 text-yellow-700">
            <!-- Disclaimer for apex domains -->
            <strong>Important:</strong> Please note that for apex domains (e.g., <span
              class="bg-white px-2 font-bold text-brand-600 dark:bg-gray-800 dark:text-brand-400">{{ domain?.display_domain }}</span>),
            a CNAME record is not allowed.
            Instead, you'll need to create an A record. Details on how to do this are provided further down the page.
          </p>
        </div>
        <div class="mt-4 text-sm">
          <a
            href="#"
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
      @domain-verify="handleDomainVerify"
    />
    <p
      v-else
      class="text-gray-600 dark:text-gray-400">
      Loading domain information...
    </p>
  </div>
</template>
