<!-- src/apps/workspace/components/domains/DomainVerificationInfo.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useDomainStatus } from '@/shared/composables/useDomainStatus';
  import { CustomDomain } from '@/schemas/shapes/v3';
  import { formatDistanceToNow } from 'date-fns';
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

  const { statusIcon, statusColor, isActive, isWarning, isAwaitingCertificate, isStale } =
    useDomainStatus(() => props.domain);

  /**
   * Tooltip text that explains the actual status, not just "view status".
   * Same precedence as useDomainStatus#displayStatus. `isActive` already
   * requires `verified`, so a domain whose status blob still reads active
   * after its TXT check stopped passing falls through to "not verified".
   */
  const statusTooltip = computed(() => {
    if (isStale.value) return t('web.domains.status_tooltip_unverified');
    if (isActive.value) return t('web.domains.status_tooltip_active');
    if (isWarning.value) return t('web.domains.status_tooltip_dns_incorrect');
    if (isAwaitingCertificate.value) return t('web.domains.status_tooltip_pending_ssl');
    return t('web.domains.status_tooltip_not_verified');
  });

  /**
   * SSL row. `vhost.has_ssl` is three-valued on the wire: true, false, or
   * absent when the check could not tell (the caddy_on_demand probe could not
   * reach port 443, or the stored certificate dates have lapsed). Absent is
   * "unknown", not "inactive".
   */
  const sslStatus = computed(() => {
    const hasSsl = props.domain?.vhost?.has_ssl;
    if (hasSsl === true) {
      return { label: t('web.COMMON.active'), color: 'text-emerald-600 dark:text-emerald-400' };
    }
    if (hasSsl === false) {
      return { label: t('web.COMMON.inactive'), color: 'text-rose-600 dark:text-rose-500' };
    }
    return { label: t('web.COMMON.unknown'), color: 'text-gray-500 dark:text-gray-400' };
  });

  /**
   * Humanized "verification check failed N ago" for the staleness row.
   * Empty string when the last fetch did not fail. See issue #3080.
   */
  const fetchFailedHumanized = computed(() => {
    const failedAt = props.domain?.vhost_fetch_failed_at;
    if (failedAt == null) return '';
    return formatDistanceToNow(Number(failedAt) * 1000, { addSuffix: true });
  });

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
      :data-tooltip="statusTooltip">
      <OIcon
        collection="mdi"
        :name="statusIcon"
        class="size-4 shrink-0 opacity-75 transition-opacity hover:opacity-80"
        :class="statusColor" />
    </RouterLink>
    <div
      v-else
      class="my-8 rounded-lg border border-gray-200/60 bg-white/60 p-6 shadow-sm backdrop-blur-sm dark:border-gray-700/60 dark:bg-gray-800/60">
      <h2 class="mb-4 text-lg font-medium text-gray-900 dark:text-white">
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
              data-testid="vhost-ssl-status"
              class="text-base"
              :class="sslStatus.color">
              {{ sslStatus.label }}
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

          <div
            v-if="domain?.vhost_fetch_failed_at"
            class="flex flex-col">
            <span class="text-sm font-medium text-gray-500 dark:text-gray-400">{{
              t('web.domains.last_check_failed')
            }}</span>
            <span class="text-base text-amber-600 dark:text-amber-400">{{
              fetchFailedHumanized
            }}</span>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
