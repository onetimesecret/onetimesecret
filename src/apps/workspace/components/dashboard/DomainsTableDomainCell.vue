<!-- src/apps/workspace/components/dashboard/DomainsTableDomainCell.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import DomainVerificationInfo from '@/apps/workspace/components/domains/DomainVerificationInfo.vue';
  import type { CustomDomain } from '@/schemas/shapes/v3/custom-domain';
  import { useDomainStatus } from '@/shared/composables/useDomainStatus';
  import { formatDistanceToNow } from 'date-fns';
  import { computed, toRef } from 'vue';

const { t } = useI18n();

  interface Props {
    domain: CustomDomain;
    orgid: string;
    canBrand?: boolean;
    canEmailConfig?: boolean;
  }

  const props = withDefaults(defineProps<Props>(), {
    canBrand: false,
    canEmailConfig: false,
  });

  // Domain verification status
  const { isWarning, isError, displayStatus } = useDomainStatus(toRef(() => props.domain));

  /**
   * Route to verify the domain (shown when DNS issues exist).
   */
  const verifyRoute = computed(() => `/org/${props.orgid}/domains/${props.domain.extid}/verify`);

  /**
   * Email config status for the domain row badge.
   *
   * Four states:
   *  1. "not_configured" — no email config exists (null/undefined). Default sender in use.
   *  2. "pending"        — config exists but validation_status != 'verified'. Default sender.
   *  3. "verified"       — config exists, verified, and enabled. Custom sender active.
   *  4. "disabled"       — config exists but enabled === false. Default sender.
   */
  const emailConfig = computed(() => props.domain.email_config ?? null);

  type EmailState = 'not_configured' | 'pending' | 'verified' | 'disabled';

  const emailState = computed((): EmailState => {
    const config = emailConfig.value;
    if (!config) return 'not_configured';
    if (config.enabled === false) return 'disabled';
    if (config.validation_status === 'verified') return 'verified';
    return 'pending';
  });

  const emailStatusIcon = computed(() => {
    switch (emailState.value) {
      case 'verified': return 'check-circle';
      case 'pending': return 'clock';
      case 'disabled': return 'minus-circle';
      case 'not_configured': return 'envelope';
      default: return 'envelope';
    }
  });

  const emailStatusColorClass = computed(() => {
    switch (emailState.value) {
      case 'verified': return 'text-emerald-600 dark:text-emerald-400';
      case 'pending': return 'text-amber-500 dark:text-amber-400';
      case 'disabled': return 'text-gray-400 dark:text-gray-500';
      case 'not_configured': return 'text-gray-400 dark:text-gray-500';
      default: return 'text-gray-400 dark:text-gray-500';
    }
  });

  const emailStatusTooltip = computed(() => {
    switch (emailState.value) {
      case 'verified': return t('web.domains.email.status_verified');
      case 'pending': return t('web.domains.email.status_pending');
      case 'disabled': return t('web.domains.email.tooltip_disabled');
      case 'not_configured': return t('web.domains.email.tooltip_not_configured');
      default: return t('web.domains.email.configure_email');
    }
  });
</script>

<template>
  <div class="flex flex-col space-y-2">
    <div class="flex items-center space-x-2">
      <router-link
        :to="{ name: canBrand ? 'DomainBrand' : 'DomainVerify', params: { orgid: props.orgid, extid: domain.extid } }"
        class="font-brand text-lg text-brandcomp-600 hover:text-brandcomp-700 dark:text-brandcomp-400 dark:hover:text-brandcomp-300">
        {{ domain.display_domain }}
      </router-link>

      <!-- heroicons/outline/external-link -->
      <a
        :href="`https://${domain.display_domain}`"
        target="_blank"
        rel="noopener noreferrer"
        class="inline-flex items-center text-gray-400 hover:text-gray-600 dark:text-gray-500 dark:hover:text-gray-300"
        :aria-label="t('web.domains.open_domain_in_new_tab')">
        <svg
          xmlns="http://www.w3.org/2000/svg"
          class="size-4"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
          aria-hidden="true">
          <path d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" />
        </svg>
      </a>
    </div>

    <div class="flex items-center gap-2">
      <!-- When DNS issues exist: show only clickable status text (no icons) -->
      <template v-if="isWarning || isError">
        <router-link
          :to="verifyRoute"
          class="inline-flex items-center gap-1.5 text-xs font-medium text-amber-600 hover:text-amber-700 dark:text-amber-400 dark:hover:text-amber-300">
          <OIcon
            collection="mdi"
            name="alert-circle"
            class="size-4"
            aria-hidden="true" />
          {{ displayStatus }}
        </router-link>
      </template>

      <!-- When OK: show status icons + age -->
      <template v-else>
        <!-- Domain verification status icon -->
        <DomainVerificationInfo
          mode="icon"
          :domain="domain"
          :orgid="props.orgid"
          class="shrink-0" />

        <!-- Email config status badge -->
        <router-link
          v-if="canEmailConfig"
          :to="{ name: 'DomainEmail', params: { orgid: props.orgid, extid: domain.extid } }"
          class="tooltip inline-flex shrink-0 items-center"
          :data-tooltip="emailStatusTooltip">
          <OIcon
            collection="heroicons"
            :name="emailStatusIcon"
            class="size-4 opacity-75 transition-opacity hover:opacity-100"
            :class="emailStatusColorClass"
            aria-hidden="true" />
        </router-link>

        <span class="text-xs text-gray-500 dark:text-gray-400">
          {{
            t('web.domains.added_formatdistancetonow_domain_created_addsuffix_true', [
              formatDistanceToNow(domain.created, { addSuffix: true }),
            ])
          }}
        </span>
      </template>
    </div>
  </div>
</template>
