<!-- src/components/dashboard/DomainsTableRowActionDropdown.vue -->

<script setup lang="ts">
  import MinimalDropdownMenu from '@/components/MinimalDropdownMenu.vue';
  import { MenuItem } from '@headlessui/vue';
  import { CustomDomain } from '@/schemas/models'
  import OIcon from '@/components/icons/OIcon.vue';

  interface Props {
    domain: CustomDomain;
  }

  defineProps<Props>();

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
              params: { domain: domain.display_domain },
            }"
            :class="[
              active
                ? 'bg-gray-100 text-gray-900 dark:bg-gray-800 dark:text-white'
                : 'text-gray-700 dark:text-gray-200',
              'block px-4 py-2 text-sm transition-colors duration-200',
            ]">
            {{ $t('manage-brand') }}
          </router-link>
        </MenuItem>
        <MenuItem v-slot="{ active }">
          <router-link
            :to="{
              name: 'DomainVerify',
              params: { domain: domain.display_domain },
            }"
            :class="[
              active
                ? 'bg-gray-100 text-gray-900 dark:bg-gray-800 dark:text-white'
                : 'text-gray-700 dark:text-gray-200',
              'block px-4 py-2 text-sm transition-colors duration-200',
            ]">
            {{ $t('verify-domain') }}
          </router-link>
        </MenuItem>
        <MenuItem v-slot="{ active }">
          <button
            @click="handleDelete(domain.display_domain)"
            :class="[
              active ? 'bg-gray-100 dark:bg-gray-800' : '',
              'flex w-full items-center px-4 py-2 text-sm text-red-600 transition-colors duration-200 hover:text-red-500 dark:text-red-400 dark:hover:text-red-300',
            ]">
            <OIcon
              collection="heroicons"
              name="trash-20-solid"
              class="mr-2 size-4"
              aria-hidden="true" />
            {{ $t('remove') }}
          </button>
        </MenuItem>
      </div>
    </template>
  </MinimalDropdownMenu>
</template>
