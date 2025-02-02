<script setup lang="ts">
  import DashboardTabNav from '@/components/dashboard/DashboardTabNav.vue';
  import DomainVerificationInfo from '@/components/DomainVerificationInfo.vue';
  import MoreInfoText from '@/components/MoreInfoText.vue';
  import VerifyDomainDetails from '@/components/VerifyDomainDetails.vue';
  import { type CustomDomainResponse } from '@/schemas/api/responses';
  import { useDomainsManager } from '@/composables/useDomainsManager';
  import { CustomDomain, CustomDomainCluster } from '@/schemas/models';
  import { onMounted, ref } from 'vue';
  import { useRoute } from 'vue-router';

  const route = useRoute();
  const { getDomain } = useDomainsManager();

  const domain = ref<CustomDomain | null>(null);
  const cluster = ref<CustomDomainCluster | null>(null);
  const allowVerifyCTA = ref(true);

  const fetchDomain = async (): Promise<void> => {
    const domainName = route.params.domain as string;
    const result = await getDomain(domainName);
    if (!result) return;

    domain.value = result.domain;
    // Ensure cluster data is present before assigning
    if (result.cluster) {
      cluster.value = result.cluster;
    } else {
      console.warn('No cluster data available for domain:', domainName);
      cluster.value = null;
    }
    allowVerifyCTA.value = result.canVerify;
  };

  const handleDomainVerify = async (data: CustomDomainResponse) => {
    console.debug('Domain verified: refreshing domain info', data);
    await fetchDomain();
  };

  onMounted(fetchDomain);
</script>

<template>
  <div class="">
    <DashboardTabNav />

    <h1 class="mb-6 text-3xl font-bold text-gray-900 dark:text-white">
      {{ $t('verify-your-domain') }}
    </h1>

    <DomainVerificationInfo v-if="domain && domain.vhost?.last_monitored_unix"
                            :domain="domain"
                            mode="table" />
    <p v-else-if="domain"
       class="mb-6 text-lg text-gray-600 dark:text-gray-300">
      {{ $t('before-we-can-activate-links-for') }}
      <span class="bg-white text-brand-600 dark:bg-gray-800 dark:text-brand-400">{{
        domain.display_domain
      }}</span>{{ $t('youll-need-to-complete-these-steps') }}
    </p>

    <MoreInfoText text-color="text-brandcomp-800 dark:text-gray-100"
                  bg-color="bg-white dark:bg-gray-800">
      <div class="prose p-6">
        <div class="max-w-xl text-base text-gray-600 dark:text-gray-300">
          <p>
            {{ $t('in-order-to-connect-your-domain-youll-need-to-ha-0') }}
            <span
                  class="bg-white px-2 font-bold text-brand-600 dark:bg-gray-800 dark:text-brand-400">{{ domain?.display_domain }}</span>
            at
            <span :title="cluster?.cluster_name ?? ''"
                  class="bg-white px-2 dark:bg-gray-800">{{ cluster?.cluster_host }}</span>{{ $t('if-you-already-have-a-cname-record-for-that-addr-0') }}
            <span :title="cluster?.cluster_name ?? ''"
                  class="bg-white px-2 dark:bg-gray-800">{{ cluster?.cluster_host }}</span>
            {{ $t('and-remove-any-other-a-aaaa-or-cname-records-for') }}
          </p>
          <p v-if="domain?.is_apex"
             class="border-l-4 border-yellow-500 bg-yellow-100 p-4 text-yellow-700">
            <!-- Disclaimer for apex domains -->
            <strong>{{ $t('important') }}:</strong> {{ $t('please-note-that-for-apex-domains') }}
            <span
                  class="bg-white px-2 font-bold text-brand-600 dark:bg-gray-800 dark:text-brand-400">{{ domain?.display_domain }}</span>{{ $t('a-cname-record-is-not-allowed-instead-youll-need-1') }}
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

    <VerifyDomainDetails v-if="domain"
                         :domain="domain"
                         :cluster="cluster"
                         :withVerifyCTA="allowVerifyCTA"
                         @domain-verify="handleDomainVerify" />
    <p v-else
       class="text-gray-600 dark:text-gray-400">
      {{ $t('loading-domain-information') }}
    </p>
  </div>
</template>
