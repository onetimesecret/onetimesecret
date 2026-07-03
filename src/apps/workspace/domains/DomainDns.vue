<!-- src/apps/workspace/domains/DomainDns.vue -->

<script setup lang="ts">
  /**
   * Domain DNS Setup Page
   *
   * Simple CNAME-instructions screen for installs that do NOT use Approximated
   * validation (self-hosted / custom installs managing their own DNS and TLS).
   * It shows the single CNAME record the operator needs to point at the
   * install's canonical domain — no Approximated proxy hosts, no vhost status,
   * no verification polling. See isApproximatedDomainValidation() for why the
   * Approximated verification screen is bypassed here.
   */
  import DomainHeader from '@/apps/workspace/components/dashboard/DomainHeader.vue';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import DetailField from '@/shared/components/ui/DetailField.vue';
  import { useDomain } from '@/shared/composables/useDomain';
  import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
  import { storeToRefs } from 'pinia';
  import { computed, onMounted } from 'vue';
  import { useI18n } from 'vue-i18n';
  import { useRouter } from 'vue-router';

  const { t } = useI18n();
  const router = useRouter();

  const props = defineProps<{
    extid: string;
    orgid: string;
  }>();

  const { domain, initialize: initializeDomain } = useDomain(props.extid);

  const bootstrapStore = useBootstrapStore();
  const { canonical_domain, site_host } = storeToRefs(bootstrapStore);

  // The canonical host the CNAME should point at. Prefer the middleware-derived
  // canonical domain, falling back to the configured site host.
  const cnameTarget = computed(() => canonical_domain.value || site_host.value || '');

  // Host label mirrors VerifyDomainDetails: the subdomain (trd) for a normal
  // custom domain, or '@' for an apex domain.
  const cnameHost = computed(() => domain.value?.trd || '@');
  const cnameHostAppendix = computed(() =>
    domain.value?.base_domain ? `.${domain.value.base_domain}` : ''
  );

  const handleBack = () => {
    router.push(`/org/${props.orgid}/domains/${props.extid}`);
  };

  onMounted(() => {
    initializeDomain();
  });
</script>

<template>
  <div class="min-h-screen bg-gray-50 dark:bg-gray-900">
    <!-- Back button -->
    <div class="mx-auto max-w-7xl px-4 pt-4 sm:px-6 lg:px-8">
      <div class="mb-4">
        <button
          type="button"
          class="inline-flex items-center gap-2 text-sm text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200"
          @click="handleBack">
          <OIcon
            collection="heroicons"
            name="arrow-left"
            class="size-5"
            aria-hidden="true" />
          {{ t('web.COMMON.back') }}
        </button>
      </div>
    </div>

    <!-- Header Section -->
    <div class="sticky top-0 z-30">
      <DomainHeader
        :domain="domain"
        :has-unsaved-changes="false"
        :orgid="props.orgid"
        external-path="/" />
    </div>

    <div class="mx-auto max-w-4xl px-4 py-8 sm:px-6 lg:px-8">
      <h2 class="mb-6 text-xl font-bold text-gray-900 dark:text-white">
        {{ t('web.domains.dns.title') }}
      </h2>

      <p
        v-if="domain"
        class="mb-6 text-lg text-gray-600 dark:text-gray-300">
        {{ t('web.domains.dns.point_domain_intro') }}
        <span class="bg-white px-1 font-bold text-brand-600 dark:bg-gray-800 dark:text-brand-400">{{
          domain.display_domain
        }}</span>
        {{ t('web.domains.dns.point_domain_outro') }}
      </p>

      <div
        v-if="domain"
        class="mx-auto max-w-2xl rounded-xl bg-white p-6 shadow-lg dark:bg-gray-800">
        <h3 class="mb-2 text-lg font-semibold text-gray-800 dark:text-white">
          {{ t('web.domains.dns.cname_heading') }}
        </h3>
        <p class="mb-4 text-gray-600 dark:text-gray-300">
          {{ t('web.domains.add_this_hostname_to_your_dns_configuration') }}
        </p>

        <div class="divide-y divide-gray-200 rounded-lg border border-gray-200 bg-white dark:divide-gray-700 dark:border-gray-700 dark:bg-gray-600">
          <DetailField
            :label="t('web.COMMON.type')"
            value="CNAME" />
          <DetailField
            :label="t('web.COMMON.host')"
            :value="cnameHost"
            :appendix="cnameHostAppendix" />
          <DetailField
            :label="t('web.COMMON.value')"
            :value="cnameTarget" />
        </div>

        <!-- Apex domains cannot use a CNAME at the zone root. -->
        <p
          v-if="domain.is_apex"
          class="mt-4 border-l-4 border-yellow-500 bg-yellow-100 p-4 text-sm text-yellow-700 dark:bg-yellow-900/20 dark:text-yellow-300">
          <strong>{{ t('web.COMMON.important') }}:</strong> {{ t('web.domains.dns.apex_notice') }}
        </p>

        <div class="mt-5 flex items-start rounded-md bg-white p-4 dark:bg-gray-800">
          <OIcon
            collection="mdi"
            name="information-outline"
            class="mt-0.5 mr-2 size-5 shrink-0 text-brandcomp-700"
            aria-hidden="true" />
          <p class="text-sm text-gray-500 dark:text-gray-400">
            {{ t('web.domains.dns_changes_can_take_as_little_as_60_seconds_or_') }}
          </p>
        </div>
      </div>

      <p
        v-else
        class="text-gray-600 dark:text-gray-400">
        {{ t('web.domains.loading_domain_information') }}
      </p>
    </div>
  </div>
</template>
