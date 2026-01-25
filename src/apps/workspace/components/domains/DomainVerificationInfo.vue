<!-- src/apps/workspace/components/domains/DomainVerificationInfo.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useDomainStatus } from '@/shared/composables/useDomainStatus';
  import { CustomDomain } from '@/schemas/models';
  import { computed } from 'vue';
  const { t } = useI18n();

  interface Props {
    domain: CustomDomain;
    mode?: string;
    orgid?: string;
  }

  const props = defineProps<Props>();

  // Build org-qualified verify route
  const verifyRoute = computed(() => {
    if (props.orgid && props.domain?.extid) {
      return `/org/${props.orgid}/domains/${props.domain.extid}/verify`;
    }
    // Fallback to dashboard if org context is missing
    return '/dashboard';
  });

  const { statusIcon, statusColor, isActive, isWarning, isError } = useDomainStatus(
    props.domain
  );

  // const formatDate = (dateString: string): string => {
  //   const date = new Date(dateString);
  //   /**
  //    * About Intl.DateTimeFormat:
  //    *
  //    *  - It automatically respects the user's locale settings.
  //    *  - It handles internationalization correctly, using the appropriate
  //    *      date format for the user's locale.
  //    *  - It's more efficient than toLocaleDateString for repeated use, as
  //    *      you can reuse the formatter.
  //    */
  //   return new Intl.DateTimeFormat(undefined, {
  //     year: 'numeric',
  //     month: 'long',
  //     day: 'numeric'
  //   }).format(date);
  // };
</script>

<template>
  <div class="m-0 p-0 leading-none">
    <RouterLink
      v-if="mode === 'icon'"
      :to="verifyRoute"
      class="tooltip inline-flex items-center gap-1.5"
      :data-tooltip="t('web.domains.view_domain_verification_status')">
      <OIcon
        collection="mdi"
        :name="statusIcon"
        class="shrink-0 opacity-75"
        :class="[
          'size-4 transition-opacity hover:opacity-80',
          {
            'text-emerald-600 dark:text-emerald-400': isActive,
            'text-amber-500 dark:text-amber-400': isWarning,
            'text-rose-600 dark:text-rose-500': isError,
          },
        ]" />
    </RouterLink>
    <div
      v-else
      class="my-8 rounded-lg bg-white p-6 shadow-md dark:bg-gray-800">
      <h2 class="mb-4 text-2xl font-bold text-gray-900 dark:text-white">
        {{ t('web.domains.domain_status') }}
      </h2>
      <div class="flex flex-col">
        <div
          v-if="domain?.vhost"
          class="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <div class="flex flex-col">
            <span class="text-sm font-medium text-gray-500 dark:text-gray-400">{{
              t('web.domains.domain')
            }}</span>
            <span class="text-base text-gray-900 dark:text-white">{{
              domain?.vhost?.incoming_address
            }}</span>
          </div>

          <div class="flex flex-col">
            <span class="text-sm font-medium text-gray-500 dark:text-gray-400">{{
              t('web.COMMON.status')
            }}</span>
            <span
              :class="statusColor"
              class="text-base">{{ domain?.vhost?.status_message }}</span>
          </div>

          <div class="flex flex-col">
            <span class="text-sm font-medium text-gray-500 dark:text-gray-400">{{
              t('web.domains.target_address')
            }}</span>
            <span class="text-base text-gray-900 dark:text-white">{{
              domain?.vhost?.target_address
            }}</span>
          </div>

          <div class="flex flex-col">
            <span class="text-sm font-medium text-gray-500 dark:text-gray-400">{{
              t('web.domains.dns_record')
            }}</span>
            <span class="text-base text-gray-900 dark:text-white">{{
              domain?.vhost?.dns_pointed_at
            }}</span>
          </div>

          <div class="flex flex-col">
            <span class="text-sm font-medium text-gray-500 dark:text-gray-400">{{
              t('web.domains.ssl_renews')
            }}</span>
            <span class="text-base text-gray-900 dark:text-white"><span v-if="domain?.vhost.ssl_active_until">{{
              domain?.vhost.ssl_active_until
            }}</span></span>
          </div>

          <div class="flex flex-col">
            <span class="text-sm font-medium text-gray-500 dark:text-gray-400">{{
              t('web.domains.ssl_status')
            }}</span>
            <span
              class="text-base"
              :class="domain?.vhost?.has_ssl ? 'text-green-600' : 'text-red-600'">
              {{ domain?.vhost?.has_ssl ? t('web.COMMON.active') : t('web.COMMON.inactive') }}
            </span>
          </div>

          <div class="flex flex-col">
            <span class="text-sm font-medium text-gray-500 dark:text-gray-400">{{
              t('web.domains.last_monitored')
            }}</span>
            <span class="text-base text-gray-900 dark:text-white">{{
              domain?.vhost?.last_monitored_humanized
            }}</span>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
