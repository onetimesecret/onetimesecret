<!-- src/apps/secret/components/SecretLinksTableRowActions.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import MinimalDropdownMenu from '@/shared/components/ui/MinimalDropdownMenu.vue';
  import { type ConcealedMessage } from '@/types/ui/concealed-message';
  import { MenuItem } from '@headlessui/vue';

  const { t } = useI18n();

  interface Props {
    concealedMessage: ConcealedMessage;
  }

  defineProps<Props>();
</script>

<template>
  <MinimalDropdownMenu>
    <template #trigger>
      <button
        type="button"
        class="inline-flex items-center justify-center rounded-md bg-white p-1.5 text-gray-500 shadow-sm transition-all hover:text-gray-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 dark:bg-gray-800 dark:text-gray-300 dark:hover:text-gray-100 dark:focus:ring-blue-400"
        title="Actions">
        <OIcon
          collection="heroicons"
          name="ellipsis-vertical-20-solid"
          class="size-5" />
      </button>
    </template>
    <template #menu-items>
      <div class="divide-y divide-gray-100 py-1 dark:divide-gray-700">
        <div class="py-1">
          <MenuItem v-slot="{ active }">
            <router-link
              :to="`/receipt/${concealedMessage.metadata_identifier}`"
              :class="[
                active
                  ? 'bg-gray-100 text-gray-900 dark:bg-gray-800 dark:text-white'
                  : 'text-gray-700 dark:text-gray-200',
                'flex items-center px-4 py-2 text-sm transition-colors duration-200',
              ]">
              <OIcon
                collection="heroicons"
                name="document-text-solid"
                class="mr-2 size-4 text-blue-500 dark:text-blue-400"
                aria-hidden="true" />
              {{ t('web.private.view_receipt') }}
            </router-link>
          </MenuItem>
          <MenuItem v-slot="{ active }">
            <router-link
              :to="`/secret/${concealedMessage.secret_identifier}`"
              target="_blank"
              :class="[
                active
                  ? 'bg-gray-100 text-gray-900 dark:bg-gray-800 dark:text-white'
                  : 'text-gray-700 dark:text-gray-200',
                'flex items-center px-4 py-2 text-sm transition-colors duration-200',
              ]">
              <OIcon
                collection="heroicons"
                name="link-20-solid"
                class="mr-2 size-4 text-emerald-500 dark:text-emerald-400"
                aria-hidden="true" />
              {{ t('web.private.open_link') }}
            </router-link>
          </MenuItem>
        </div>
        <div class="py-1">
          <MenuItem v-slot="{ active }">
            <router-link
              :to="`/receipt/${concealedMessage.metadata_identifier}/burn`"
              :class="[
                active ? 'bg-gray-100 dark:bg-gray-800' : '',
                'flex w-full items-center px-4 py-2 text-sm text-red-600 transition-colors duration-200 hover:text-red-500 dark:text-red-400 dark:hover:text-red-300',
              ]">
              <OIcon
                collection="heroicons"
                name="trash-20-solid"
                class="mr-2 size-4"
                aria-hidden="true" />
              {{ t('web.COMMON.burn') }}
            </router-link>
          </MenuItem>
        </div>
      </div>
    </template>
  </MinimalDropdownMenu>
</template>
