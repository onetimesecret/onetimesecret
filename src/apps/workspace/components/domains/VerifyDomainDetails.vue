<!-- src/apps/workspace/components/domains/VerifyDomainDetails.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
import OIcon from '@/shared/components/icons/OIcon.vue';
import { useDomainDnsRecord } from '@/shared/composables/useDomainDnsRecord';
import { useDomainsManager } from '@/shared/composables/useDomainsManager';
import { CustomDomainProxy, type CustomDomainResponse } from '@/schemas/api/v3/responses/domains';
import { type CustomDomain } from '@/schemas/shapes/v3/custom-domain';
import { computed, ref } from 'vue';

import BasicFormAlerts from '@/shared/components/forms/BasicFormAlerts.vue';
import DetailField from '@/shared/components/ui/DetailField.vue';

interface Props {
  domain: CustomDomain;
  cluster?: CustomDomainProxy | null;
  withVerifyCTA?: boolean;
}

const props = withDefaults(defineProps<Props>(), {
  domain: () => ({} as CustomDomain),
  cluster: null,
  withVerifyCTA: false,
});

// Define the emit function with the type
const emit = defineEmits<{
  (e: 'domainVerify', data: CustomDomainResponse): void;
}>();

const { verifyDomain, isLoading, error } = useDomainsManager();
const { t } = useI18n();

// Step 2: the address record. The TXT record in step 1 is the same under every
// strategy that checks ownership; where the domain points is not (Approximated's
// proxy, or this install's own host). See useDomainDnsRecord.
const { kind, recordType, recordHost, recordHostAppendix, recordTarget } = useDomainDnsRecord(
  () => props.domain,
  () => props.cluster
);

const addressRecordHeading = computed(() => {
  if (kind.value === 'a') return t('web.domains.2_create_the_a_record');
  if (kind.value === 'alias') return t('web.domains.2_create_the_alias_record');
  return t('web.domains.2_create_the_cname_record');
});

const success = ref<string | undefined>(undefined);
const buttonDisabledDelay = ref(false);
const isButtonDisabled = computed(() => isLoading.value || buttonDisabledDelay.value);
const buttonText = computed(() => isLoading.value ? t('web.COMMON.processing') : t('web.domains.verify_domain'));

const verify = async () => {
  console.info('Refreshing DNS verification details...');

  try {
    const result = await verifyDomain(props.domain.extid);
    if (result) {
      success.value = t('web.domains.domain_verification_initiated_successfully')
      emit('domainVerify', result);

      buttonDisabledDelay.value = true;
    }

    setTimeout(() => {
      buttonDisabledDelay.value = false;
    }, 3000);
  } catch (err) {
    console.error('Verification failed:', err);
  }
};
</script>

<template>
  <div class="mx-auto max-w-2xl rounded-xl bg-white p-6 shadow-lg dark:bg-gray-800">
    <h2 class="mb-4 text-2xl font-bold text-gray-800 dark:text-white">
      {{ t('web.domains.domain_verification_steps') }}
    </h2>
    <p class="mb-6 text-lg text-gray-600 dark:text-gray-300">
      {{ t('web.domains.follow_these_steps_to_verify_domain_ownership_an') }}
    </p>

    <BasicFormAlerts
      :success="success"
      :errors="error ? [error.message] : []" />

    <div class="mb-4 flex justify-end">
      <button
        v-if="withVerifyCTA"
        type="button"
        data-testid="verify-domain-details-button"
        :aria-busy="isLoading"
        @click="verify"
        :disabled="isButtonDisabled"
        class="flex items-center gap-2 rounded-lg bg-brand-500 px-6 py-3
          text-lg font-semibold
          text-white transition
          duration-100
          ease-in-out hover:bg-brand-600 disabled:cursor-not-allowed disabled:bg-gray-400">
        <span>{{ buttonText }}</span>
        <OIcon
          collection="mdi"
          :name="isLoading ? 'loading' : 'check-circle'"
          class="size-5"
          :class="{ 'animate-spin motion-reduce:animate-none': isLoading }"
          aria-hidden="true" />
      </button>
    </div>

    <ol class="mb-8 space-y-6">
      <li class="rounded-lg bg-gray-50 p-4 dark:bg-gray-700">
        <h3 class="mb-2 text-lg font-semibold text-gray-800 dark:text-white">
          {{ t('web.domains.1_create_a_txt_record') }}
        </h3>
        <p class="mb-2 text-gray-600 dark:text-gray-300">
          {{ t('web.domains.add_this_hostname_to_your_dns_configuration') }}
        </p>

        <div class="divide-y divide-gray-200 rounded-lg border border-gray-200 bg-white dark:divide-gray-700 dark:border-gray-700 dark:bg-gray-600">
          <DetailField
            :label="t('web.COMMON.type')"
            value="TXT" />
          <DetailField
            :label="t('web.COMMON.host')"
            :value="domain.txt_validation_host"
            :appendix="`.${domain.base_domain}`" />
          <DetailField
            :label="t('web.COMMON.value')"
            :value="domain.txt_validation_value" />
        </div>
      </li>
      <li
        data-testid="verify-address-record"
        class="rounded-lg bg-gray-50 p-4 dark:bg-gray-700">
        <h3 class="mb-2 text-lg font-semibold text-gray-800 dark:text-white">
          {{ addressRecordHeading }}
        </h3>

        <div class="divide-y divide-gray-200 rounded-lg border border-gray-200 bg-white dark:divide-gray-700 dark:border-gray-700 dark:bg-gray-600">
          <DetailField
            :label="t('web.COMMON.type')"
            :value="recordType" />
          <DetailField
            :label="t('web.COMMON.host')"
            :value="recordHost"
            :appendix="recordHostAppendix" />
          <DetailField
            :label="t('web.COMMON.value')"
            :value="recordTarget" />
        </div>

        <!-- Apex domains cannot use a CNAME at the zone root. -->
        <p
          v-if="kind === 'alias'"
          class="mt-4 border-l-4 border-yellow-500 bg-yellow-100 p-4 text-sm text-yellow-700 dark:bg-yellow-900/20 dark:text-yellow-300">
          <strong>{{ t('web.COMMON.important') }}:</strong> {{ t('web.domains.dns.apex_notice') }}
        </p>
      </li>
      <li class="rounded-lg bg-gray-50 p-4 dark:bg-gray-700">
        <h3 class="mb-2 text-lg font-semibold text-gray-800 dark:text-white">
          {{ t('web.domains.3_wait_for_propagation') }}
        </h3>
        <p class="text-gray-600 dark:text-gray-300">
          {{ t('web.domains.dns_changes_can_take_as_little_as_60_seconds_or_') }}
        </p>
      </li>
    </ol>

    <div class="mt-5 flex items-start rounded-md bg-white p-4 dark:bg-gray-800">
      <OIcon
        collection="mdi"
        name="information-outline"
        class="mr-2 mt-0.5 size-5 shrink-0 text-brandcomp-700"
        aria-hidden="true" />
      <p class="text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.domains.it_may_take_a_few_minutes_for_your_ssl_certifica') }}
      </p>
    </div>
  </div>
</template>
