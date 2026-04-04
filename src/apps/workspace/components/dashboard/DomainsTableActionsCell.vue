<!-- src/apps/workspace/components/dashboard/DomainsTableActionsCell.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import MinimalDropdownMenu from '@/shared/components/ui/MinimalDropdownMenu.vue';
  import { CustomDomain } from '@/schemas/shapes/v3'
  import { MenuItem } from '@headlessui/vue';
  import { useDomainStatus } from '@/shared/composables/useDomainStatus';
  import { computed, toRef } from 'vue';

const { t } = useI18n();

  interface Props {
    domain: CustomDomain;
    orgid: string;
    canBrand?: boolean;
    canManageSso?: boolean;
    canEmailConfig?: boolean;
    canIncomingSecrets?: boolean;
  }

  const props = withDefaults(defineProps<Props>(), {
    canBrand: false,
    canManageSso: false,
    canEmailConfig: false,
    canIncomingSecrets: false,
  });

  // Domain verification status
  const { isActive } = useDomainStatus(toRef(() => props.domain));

  /**
   * Primary action to surface outside the kebab menu.
   * Only shown when domain is verified (no issues) — when there ARE issues,
   * the clickable status text in the domain cell already serves as the action.
   */
  const primaryAction = computed(() => {
    // Don't show button when domain has issues — status text is already clickable
    if (!isActive.value) return null;

    // When verified, surface "Manage Brand" if entitled
    if (props.canBrand) {
      return {
        label: t('web.domains.manage_brand'),
        route: { name: 'DomainBrand', params: { orgid: props.orgid, extid: props.domain.extid } },
        icon: 'paint-brush',
        style: 'default',
      };
    }
    return null;
  });

  const emit = defineEmits<{
    (e: 'delete', domain: string): void
  }>();

  const handleDelete = (domain: string) => {
    emit('delete', domain);
  };

</script>

<template>
  <div class="flex items-center justify-end gap-2">
    <!-- Primary action button (surfaced for quick access when domain is healthy) -->
    <router-link
      v-if="primaryAction"
      :to="primaryAction.route"
      class="inline-flex items-center gap-1.5 rounded-md bg-gray-100 px-2.5 py-1.5 text-xs font-medium text-gray-700 transition-colors hover:bg-gray-200 dark:bg-gray-700 dark:text-gray-300 dark:hover:bg-gray-600">
      <OIcon
        collection="heroicons"
        :name="primaryAction.icon"
        class="size-3.5"
        aria-hidden="true" />
      {{ primaryAction.label }}
    </router-link>

    <!-- Kebab menu for all actions -->
    <MinimalDropdownMenu>
    <template #menu-items>
      <div class="py-1">
        <MenuItem v-if="canBrand" v-slot="{ active }">
          <router-link
            :to="{
              name: 'DomainBrand',
              params: { orgid: props.orgid, extid: domain.extid },
            }"
            :class="[
              active
                ? 'bg-gray-100 text-gray-900 dark:bg-gray-800 dark:text-white'
                : 'text-gray-700 dark:text-gray-200',
              'block px-4 py-2 text-sm transition-colors duration-200 focus:outline-none focus:ring-2 focus:ring-inset focus:ring-brand-500',
            ]">
            {{ t('web.domains.manage_brand') }}
          </router-link>
        </MenuItem>
        <MenuItem v-slot="{ active }">
          <router-link
            :to="{
              name: 'DomainVerify',
              params: { orgid: props.orgid, extid: domain.extid },
            }"
            :class="[
              active
                ? 'bg-gray-100 text-gray-900 dark:bg-gray-800 dark:text-white'
                : 'text-gray-700 dark:text-gray-200',
              'block px-4 py-2 text-sm transition-colors duration-200 focus:outline-none focus:ring-2 focus:ring-inset focus:ring-brand-500',
            ]">
            {{ t('web.domains.verify_domain') }}
          </router-link>
        </MenuItem>
        <MenuItem v-if="canManageSso" v-slot="{ active }">
          <router-link
            :to="{
              name: 'DomainSso',
              params: { orgid: props.orgid, extid: domain.extid },
            }"
            :class="[
              active
                ? 'bg-gray-100 text-gray-900 dark:bg-gray-800 dark:text-white'
                : 'text-gray-700 dark:text-gray-200',
              'block px-4 py-2 text-sm transition-colors duration-200 focus:outline-none focus:ring-2 focus:ring-inset focus:ring-brand-500',
            ]">
            {{ t('web.domains.sso.configure_sso') }}
          </router-link>
        </MenuItem>
        <MenuItem v-if="canEmailConfig" v-slot="{ active }">
          <router-link
            :to="{
              name: 'DomainEmail',
              params: { orgid: props.orgid, extid: domain.extid },
            }"
            :class="[
              active
                ? 'bg-gray-100 text-gray-900 dark:bg-gray-800 dark:text-white'
                : 'text-gray-700 dark:text-gray-200',
              'block px-4 py-2 text-sm transition-colors duration-200 focus:outline-none focus:ring-2 focus:ring-inset focus:ring-brand-500',
            ]">
            {{ t('web.domains.email.configure_email') }}
          </router-link>
        </MenuItem>
        <MenuItem v-if="canIncomingSecrets" v-slot="{ active }">
          <router-link
            :to="{
              name: 'DomainIncoming',
              params: { orgid: props.orgid, extid: domain.extid },
            }"
            :class="[
              active
                ? 'bg-gray-100 text-gray-900 dark:bg-gray-800 dark:text-white'
                : 'text-gray-700 dark:text-gray-200',
              'block px-4 py-2 text-sm transition-colors duration-200 focus:outline-none focus:ring-2 focus:ring-inset focus:ring-brand-500',
            ]">
            {{ t('web.domains.incoming.configure_incoming') }}
          </router-link>
        </MenuItem>
        <MenuItem v-slot="{ active }">
          <button
            @click="handleDelete(domain.extid)"
            :class="[
              active ? 'bg-gray-100 dark:bg-gray-800' : '',
              'flex w-full items-center px-4 py-2 text-sm text-red-600 transition-colors duration-200 hover:text-red-500 dark:text-red-400 dark:hover:text-red-300 focus:outline-none focus:ring-2 focus:ring-inset focus:ring-red-500',
            ]">
            <OIcon
              collection="heroicons"
              name="trash-20-solid"
              class="mr-2 size-4"
              aria-hidden="true" />
            {{ t('web.COMMON.remove') }}
          </button>
        </MenuItem>
      </div>
    </template>
  </MinimalDropdownMenu>
  </div>
</template>
