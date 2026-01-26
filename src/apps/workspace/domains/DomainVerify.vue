<!-- src/apps/workspace/domains/DomainVerify.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import DnsWidget from '@/apps/workspace/components/domains/DnsWidget.vue';
  import DomainVerificationInfo from '@/apps/workspace/components/domains/DomainVerificationInfo.vue';
  import MoreInfoText from '@/shared/components/ui/MoreInfoText.vue';
  import VerifyDomainDetails from '@/apps/workspace/components/domains/VerifyDomainDetails.vue';
  import BasicFormAlerts from '@/shared/components/forms/BasicFormAlerts.vue';
  import { useDomainsManager } from '@/shared/composables/useDomainsManager';
  import { type CustomDomainResponse } from '@/schemas/api/v3/responses';
  import { CustomDomain, CustomDomainProxy } from '@/schemas/models';
  import { computed, onMounted, ref } from 'vue';
  import { useRoute } from 'vue-router';

  const { t } = useI18n(); // auto-import
  const route = useRoute();
  const { getDomain, verifyDomain } = useDomainsManager();

  const domain = ref<CustomDomain | null>(null);
  const cluster = ref<CustomDomainProxy | null>(null);
  const allowVerifyCTA = ref(true);
  const verificationInProgress = ref(false);
  const verificationError = ref<string | null>(null);

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
  // Show widget only for approximated strategy when domain is not yet verified
  const showDnsWidget = computed(
    () =>
      domain.value &&
      !domain.value.vhost?.last_monitored_unix &&
      cluster.value?.validation_strategy === 'approximated'
  );

  // Show manual DNS instructions for non-approximated strategies
  const showManualInstructions = computed(
    () =>
      domain.value &&
      !domain.value.vhost?.last_monitored_unix &&
      cluster.value?.validation_strategy !== 'approximated'
  );

  // Target address for DNS records (IP for apex domains, hostname otherwise)
  const dnsTargetAddress = computed(() => {
    // For apex domains, use the proxy IP; otherwise use proxy_host for CNAME
    if (domain.value?.is_apex) {
      return cluster.value?.proxy_ip ?? '';
    }
    return cluster.value?.proxy_host ?? '';
  });

  // Trigger backend verification (called on mount and widget success)
  const triggerVerification = async () => {
    if (!domain.value || verificationInProgress.value) return;

    verificationInProgress.value = true;
    verificationError.value = null;
    try {
      const result = await verifyDomain(domain.value.extid);
      if (result) {
        await fetchDomain();
      }
    } catch (err: unknown) {
      verificationError.value = err instanceof Error ? err.message : String(err);
    } finally {
      verificationInProgress.value = false;
    }
  };

  const handleDnsRecordsVerified = async () => {
    console.debug('DNS records verified via widget, triggering backend verification');
    await triggerVerification();
  };

  // On mount: fetch domain then verify if showing widget
  onMounted(async () => {
    await fetchDomain();
    if (showDnsWidget.value) {
      await triggerVerification();
    }
  });
</script>

<template>
  <div>
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
      v-if="showManualInstructions"
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
              :title="cluster?.proxy_name ?? ''"
              class="bg-white px-2 dark:bg-gray-800">{{ cluster?.proxy_host }}</span>{{ t('web.domains.if_you_already_have_a_cname_record_for_that_addr') }}
            <span
              :title="cluster?.proxy_name ?? ''"
              class="bg-white px-2 dark:bg-gray-800">{{ cluster?.proxy_host }}</span>
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
        :trd="domain?.trd"
        @records-verified="handleDnsRecordsVerified" />

      <!-- Manual verification button and error display -->
      <div class="mt-6 flex items-center gap-4">
        <button
          type="button"
          :disabled="verificationInProgress"
          :aria-busy="verificationInProgress"
          class="inline-flex items-center rounded-md bg-brand-600 px-4 py-2 text-sm font-medium text-white shadow-sm hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-brand-500 dark:hover:bg-brand-600"
          @click="triggerVerification">
          <svg
            v-if="verificationInProgress"
            class="-ml-1 mr-2 h-4 w-4 animate-spin"
            aria-hidden="true"
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24">
            <circle
              class="opacity-25"
              cx="12"
              cy="12"
              r="10"
              stroke="currentColor"
              stroke-width="4" />
            <path
              class="opacity-75"
              fill="currentColor"
              d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" />
          </svg>
          {{ verificationInProgress ? t('web.COMMON.processing') : t('web.domains.verify_domain') }}
        </button>
        <BasicFormAlerts
          v-if="verificationError"
          aria-live="polite"
          :errors="[verificationError]" />
      </div>
    </div>

    <!-- Manual verification steps for non-approximated strategies -->
    <VerifyDomainDetails
      v-if="domain && !showDnsWidget"
      :domain="domain"
      :cluster="cluster"
      :with-verify-c-t-a="allowVerifyCTA"
      @domain-verify="handleDomainVerify" />
    <p
      v-if="!domain"
      class="text-gray-600 dark:text-gray-400">
      {{ t('web.domains.loading_domain_information') }}
    </p>
  </div>
</template>
