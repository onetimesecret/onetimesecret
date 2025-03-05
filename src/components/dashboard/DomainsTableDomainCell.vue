<!-- src/components/dashboard/DomainsTableDomainCell.vue -->

<script setup lang="ts">
  import { formatDistanceToNow } from 'date-fns';
  import type { CustomDomain } from '@/schemas/models/domain';
  import DomainVerificationInfo from '@/components/DomainVerificationInfo.vue';
  import { useDomainStatus } from '@/composables/useDomainStatus';

  interface Props {
    domain: CustomDomain;
  }

  const props = defineProps<Props>();

  const status = useDomainStatus(props.domain);
</script>

<template>
  <div class="flex flex-col space-y-2">
    <div class="flex items-center space-x-2">
      <router-link
        v-if="status.isActive.value"
        :to="{ name: 'DomainBrand', params: { domain: domain.display_domain } }"
        class="font-brand text-lg text-brandcomp-600 hover:text-brandcomp-700 dark:text-brandcomp-400 dark:hover:text-brandcomp-300">
        {{ domain.display_domain }}
      </router-link>
      <router-link
        v-else
        :to="{ name: 'DomainVerify', params: { domain: domain.display_domain } }"
        class="font-brand text-lg text-brandcomp-600 hover:text-brandcomp-700 dark:text-brandcomp-400 dark:hover:text-brandcomp-300">
        {{ domain.display_domain }}
      </router-link>

      <!-- heroicons/outline/external-link -->
      <a
        :href="`https://${domain.display_domain}`"
        target="_blank"
        rel="noopener noreferrer"
        class="inline-flex items-center text-gray-400 hover:text-gray-600 dark:text-gray-500 dark:hover:text-gray-300"
        title="$t('open-domain-in-new-tab')">
        <svg
          xmlns="http://www.w3.org/2000/svg"
          class="h-4 w-4"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round">
          <path d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" />
        </svg>
      </a>
    </div>

    <div class="flex items-start space-x-2">
      <DomainVerificationInfo
        mode="icon"
        :domain="domain"
        class="flex-shrink-0 -mt-0.5" />

      <span class="text-xs text-gray-500 dark:text-gray-400">
        {{
          $t('added-formatdistancetonow-domain-created-addsuffix-true', [
            formatDistanceToNow(domain.created, { addSuffix: true }),
          ])
        }}
      </span>
    </div>
  </div>
</template>
