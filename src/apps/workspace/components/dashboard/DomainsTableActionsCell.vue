<!-- src/apps/workspace/components/dashboard/DomainsTableActionsCell.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import MinimalDropdownMenu from '@/shared/components/ui/MinimalDropdownMenu.vue';
  import { CustomDomain } from '@/schemas/models'
  import { MenuItem } from '@headlessui/vue';

const { t } = useI18n();

  interface Props {
    domain: CustomDomain;
    orgid: string;
  }

  const props = defineProps<Props>();

  const emit = defineEmits<{
    (e: 'delete', domain: string): void
  }>();

  const handleDelete = (domain: string) => {
    emit('delete', domain);
  };

</script>

<template>
  <MinimalDropdownMenu>
    <template #menu-items>
      <div class="py-1">
        <MenuItem v-slot="{ active }">
          <router-link
            :to="{
              name: 'DomainBrand',
              params: { orgid: props.orgid, extid: domain.extid },
            }"
            :class="[
              active
                ? 'bg-gray-100 text-gray-900 dark:bg-gray-800 dark:text-white'
                : 'text-gray-700 dark:text-gray-200',
              'block px-4 py-2 text-sm transition-colors duration-200',
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
              'block px-4 py-2 text-sm transition-colors duration-200',
            ]">
            {{ t('web.domains.verify_domain') }}
          </router-link>
        </MenuItem>
        <MenuItem v-slot="{ active }">
          <button
            @click="handleDelete(domain.extid)"
            :class="[
              active ? 'bg-gray-100 dark:bg-gray-800' : '',
              'flex w-full items-center px-4 py-2 text-sm text-red-600 transition-colors duration-200 hover:text-red-500 dark:text-red-400 dark:hover:text-red-300',
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
</template>
