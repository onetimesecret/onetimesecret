<script setup lang="ts">
import { useDomainsManager } from '@/composables/useDomainsManager';
import { CustomDomainResponse } from '@/schemas/api/responses';
import { CustomDomain, CustomDomainCluster } from '@/schemas/models/domain';
import OIcon from '@/components/icons/OIcon.vue';
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import BasicFormAlerts from './BasicFormAlerts.vue';
import DetailField from './DetailField.vue';

interface Props {
  domain: CustomDomain;
  cluster?: CustomDomainCluster | null;
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

const success = ref<string | undefined>(undefined);
const buttonDisabledDelay = ref(false);
const isButtonDisabled = computed(() => isLoading.value || buttonDisabledDelay.value);
const buttonText = computed(() => isLoading.value ? t('web.COMMON.processing') : t('verify-domain'));

const verify = async () => {
  console.info('Refreshing DNS verification details...');

  try {
    const result = await verifyDomain(props.domain.display_domain);
    if (result) {
      success.value = t('domain-verification-initiated-successfully')
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
      {{ $t('domain-verification-steps') }}
    </h2>
    <p class="mb-6 text-lg text-gray-600 dark:text-gray-300">
      {{ $t('follow-these-steps-to-verify-domain-ownership-an') }}
    </p>

    <BasicFormAlerts
      :success="success"
      :errors="error ? [error.message] : []"
    />

    <div class="mb-4 flex justify-end">
      <button
        v-if="withVerifyCTA"
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
          :class="{ 'animate-spin': isLoading }"
          aria-hidden="true"
        />
      </button>
    </div>

    <ol class="mb-8 space-y-6">
      <li class="rounded-lg bg-gray-50 p-4 dark:bg-gray-700">
        <h3 class="mb-2 text-lg font-semibold text-gray-800 dark:text-white">
          {{ $t('1-create-a-txt-record') }}
        </h3>
        <p class="mb-2 text-gray-600 dark:text-gray-300">
          {{ $t('add-this-hostname-to-your-dns-configuration') }}
        </p>

        <div class="rounded-lg border border-gray-200 divide-y divide-gray-200 bg-white dark:bg-gray-600 dark:border-gray-700 dark:divide-gray-700">
          <DetailField
            :label="$t('type')"
            value="TXT"
          />
          <DetailField
            :label="$t('host')"
            :value="domain.txt_validation_host"
            :appendix="`.${domain.base_domain}`"
          />
          <DetailField
            :label="$t('value')"
            :value="domain.txt_validation_value"
          />
        </div>
      </li>
      <li
        v-if="domain?.is_apex"
        class="rounded-lg bg-gray-50 p-4 dark:bg-gray-700">
        <h3 class="mb-2 text-lg font-semibold text-gray-800 dark:text-white">
          {{ $t('2-create-the-a-record') }}
        </h3>

        <div class="rounded-lg border border-gray-200 divide-y divide-gray-200 bg-white dark:bg-gray-600 dark:border-gray-700 dark:divide-gray-700">
          <DetailField
            :label="$t('type-0')"
            value="A"
          />
          <DetailField
            :label="$t('host')"
            :value="domain?.trd ? domain.trd : '@'"
            :appendix="domain?.base_domain"
          />
          <DetailField
            :label="$t('value')"
            :value="cluster?.cluster_ip ?? ''"
          />
        </div>
      </li>
      <li
        v-else
        class="rounded-lg bg-gray-50 p-4 dark:bg-gray-700">
        <h3 class="mb-2 text-lg font-semibold text-gray-800 dark:text-white">
          {{ $t('2-create-the-cname-record') }}
        </h3>

        <div class="rounded-lg border border-gray-200 divide-y divide-gray-200 bg-white dark:bg-gray-600 dark:border-gray-700 dark:divide-gray-700">
          <DetailField
            v-if="domain?.is_apex"
            :label="$t('type')"
            value="A"
          />
          <DetailField
            v-else
            :label="$t('type')"
            value="CNAME"
          />
          <DetailField
            :label="$t('host')"
            :value="domain?.trd ? domain.trd : '@'"
            :appendix="`.${domain?.base_domain}`"
          />
          <DetailField
            v-if="domain?.is_apex"
            :label="$t('value')"
            :value="cluster?.cluster_ip ?? ''"
          />
          <DetailField
            v-else
            :label="$t('value')"
            :value="cluster?.cluster_host ?? ''"
          />
        </div>
      </li>
      <li class="rounded-lg bg-gray-50 p-4 dark:bg-gray-700">
        <h3 class="mb-2 text-lg font-semibold text-gray-800 dark:text-white">
          {{ $t('3-wait-for-propagation') }}
        </h3>
        <p class="text-gray-600 dark:text-gray-300">
          {{ $t('dns-changes-can-take-as-little-as-60-seconds-or-') }}
        </p>
      </li>
    </ol>

    <div class="mt-5 flex items-start rounded-md bg-white p-4 dark:bg-gray-800">
      <OIcon
        collection="mdi"
        name="information-outline"
        class="mr-2 mt-0.5 size-5 shrink-0 text-brandcomp-700"
        aria-hidden="true"
      />
      <p class="text-sm text-gray-500 dark:text-gray-400">
        {{ $t('it-may-take-a-few-minutes-for-your-ssl-certifica') }}
      </p>
    </div>
  </div>
</template>
