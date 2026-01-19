<!-- src/apps/workspace/domains/DomainVerify.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import DnsWidget from '@/apps/workspace/components/domains/DnsWidget.vue';
  import DomainVerificationInfo from '@/apps/workspace/components/domains/DomainVerificationInfo.vue';
  import MoreInfoText from '@/shared/components/ui/MoreInfoText.vue';
  import VerifyDomainDetails from '@/apps/workspace/components/domains/VerifyDomainDetails.vue';
  import { useDomainsManager } from '@/shared/composables/useDomainsManager';
  import { type CustomDomainResponse } from '@/schemas/api/v3/responses';
  import { CustomDomain, CustomDomainCluster } from '@/schemas/models';
  import { computed, onMounted, ref } from 'vue';
  import { useRoute } from 'vue-router';

  const { t } = useI18n(); // auto-import
  const route = useRoute();
  const { getDomain } = useDomainsManager();

  const domain = ref<CustomDomain | null>(null);
  const cluster = ref<CustomDomainCluster | null>(null);
  const allowVerifyCTA = ref(true);

  const fetchDomain = async (): Promise<void> => {
    const extid = route.params.extid as string;
    const result = await getDomain(extid);
    if (!result) return;

    domain.value = result.domain;
    // Ensure cluster data is present before assigning
    if (result.cluster) {
      cluster.value = result.cluster;
    } else {
      console.warn('No cluster data available for extid:', extid);
      cluster.value = null;
    }
    allowVerifyCTA.value = result.canVerify;
  };

  const handleDomainVerify = async (data: CustomDomainResponse) => {
    console.debug('Domain verified: refreshing domain info', data);
    await fetchDomain();
  };

  // DNS Widget configuration
  // Show widget only when domain is not yet verified (no vhost data)
  const showDnsWidget = computed(() => domain.value && !domain.value.vhost?.last_monitored_unix && cluster.value);

  // Target address for DNS records (IP for apex domains, hostname otherwise)
  const dnsTargetAddress = computed(() => {
    // For apex domains, use the cluster IP; otherwise use cluster_host for CNAME
    if (domain.value?.is_apex) {
      return cluster.value?.cluster_ip ?? '';
    }
    return cluster.value?.cluster_host ?? '';
  });

  const handleDnsRecordsVerified = async () => {
    console.debug('DNS records verified via widget');
    // Refresh domain data to pick up verification status
    await fetchDomain();
  };

  onMounted(fetchDomain);
</script>

<template>
  <div class="">
    <h1 class="mb-6 text-3xl font-bold text-gray-900 dark:text-white">
      {{ t('web.domains.verify_your_domain') }}
    </h1>

    <DomainVerificationInfo
      v-if="domain && domain.vhost?.last_monitored_unix"
      :domain="domain"
      mode="table" />
    <p
      v-else-if="domain"
      class="mb-6 text-lg text-gray-600 dark:text-gray-300">
      {{ t('web.domains.before_we_can_activate_links_for') }}
      <span class="bg-white text-brand-600 dark:bg-gray-800 dark:text-brand-400">{{
        domain.display_domain
      }}</span>
      {{ t('web.domains.youll_need_to_complete_these_steps') }}
    </p>

    <MoreInfoText
      text-color="text-brandcomp-800 dark:text-gray-100"
      bg-color="bg-white dark:bg-gray-800">
      <div class="prose max-w-none">
        <div class="text-base text-gray-600 dark:text-gray-300">
          <p>
            {{ t('web.domains.in_order_to_connect_your_domain_youll_need_to_ha') }}
            <span
              class="bg-white px-2 font-bold text-brand-600 dark:bg-gray-800 dark:text-brand-400">{{ domain?.display_domain }}</span>
            at
            <span
              :title="cluster?.cluster_name ?? ''"
              class="bg-white px-2 dark:bg-gray-800">{{ cluster?.cluster_host }}</span>{{ t('web.domains.if_you_already_have_a_cname_record_for_that_addr') }}
            <span
              :title="cluster?.cluster_name ?? ''"
              class="bg-white px-2 dark:bg-gray-800">{{ cluster?.cluster_host }}</span>
            {{ t('web.domains.and_remove_any_other_a_aaaa_or_cname_records_for') }}
          </p>
          <p
            v-if="domain?.is_apex"
            class="border-l-4 border-yellow-500 bg-yellow-100 p-4 text-yellow-700">
            <!-- Disclaimer for apex domains -->
            <strong>{{ t('web.COMMON.important') }}:</strong> {{ t('web.domains.please_note_that_for_apex_domains') }}
            <span
              class="bg-white px-2 font-bold text-brand-600 dark:bg-gray-800 dark:text-brand-400">{{ domain?.display_domain }}</span>{{ t('web.domains.a_cname_record_is_not_allowed_instead_youll_need') }}
          </p>
        </div>
        <div class="mt-4 text-sm">
          <a
            href="#"
            class="font-medium text-brandcomp-600 hover:text-brandcomp-500 dark:text-brandcomp-400 dark:hover:text-brandcomp-300">
            <!-- {{ t('web.domains.learn_more_dns') }} <span aria-hidden="true">&rarr;</span> -->
          </a>
        </div>
      </div>
    </MoreInfoText>

    <!-- DNS Widget for automated DNS configuration -->
    <div
      v-if="showDnsWidget"
      class="my-8 rounded-lg bg-white p-6 shadow-md dark:bg-gray-800">
      <h2 class="mb-4 text-xl font-semibold text-gray-900 dark:text-white">
        {{ t('web.domains.configure_dns_records') }}
      </h2>
      <p class="mb-4 text-gray-600 dark:text-gray-400">
        {{ t('web.domains.dns_widget_description') }}
      </p>
      <DnsWidget
        :domain="domain!.display_domain"
        :target-address="dnsTargetAddress"
        :is-apex="domain?.is_apex"
        :txt-validation-host="domain?.txt_validation_host"
        :txt-validation-value="domain?.txt_validation_value"
        @records-verified="handleDnsRecordsVerified" />
    </div>

    <VerifyDomainDetails
      v-if="domain"
      :domain="domain"
      :cluster="cluster"
      :with-verify-c-t-a="allowVerifyCTA"
      @domain-verify="handleDomainVerify" />
    <p
      v-else
      class="text-gray-600 dark:text-gray-400">
      {{ t('web.domains.loading_domain_information') }}
    </p>
  </div>
</template>
