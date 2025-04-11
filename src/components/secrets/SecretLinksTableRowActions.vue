<!-- src/components/secrets/SecretLinksTableRowActions.vue -->

<script setup lang="ts">
  import MinimalDropdownMenu from '@/components/MinimalDropdownMenu.vue';
  import { MenuItem } from '@headlessui/vue';
  import { type ConcealedMessage } from '@/types/ui/concealed-message';
  import OIcon from '@/components/icons/OIcon.vue';

  interface Props {
    concealedMessage: ConcealedMessage;
  }

  defineProps<Props>();

  const emit = defineEmits<{
    (e: 'delete', concealedMessage: ConcealedMessage): void
  }>();

  const handleDelete = (concealedMessage: ConcealedMessage) => {
    emit('delete', concealedMessage);
  };
</script>

<template>
  <MinimalDropdownMenu>
    <template #menu-items>
      <div class="py-1">
        <MenuItem v-slot="{ active }">
          <router-link
            :to="`/private/${concealedMessage.metadata_key}`"
            :class="[
              active
                ? 'bg-gray-100 text-gray-900 dark:bg-gray-800 dark:text-white'
                : 'text-gray-700 dark:text-gray-200',
              'block px-4 py-2 text-sm transition-colors duration-200',
            ]">
            {{ $t('web.private.view_metadata') }}
          </router-link>
        </MenuItem>
        <MenuItem v-slot="{ active }">
          <button
            @click="handleDelete(concealedMessage)"
            :class="[
              active ? 'bg-gray-100 dark:bg-gray-800' : '',
              'flex w-full items-center px-4 py-2 text-sm text-red-600 transition-colors duration-200 hover:text-red-500 dark:text-red-400 dark:hover:text-red-300',
            ]">
            <OIcon
              collection="heroicons"
              name="trash-20-solid"
              class="mr-2 size-4"
              aria-hidden="true" />
            {{ $t('web.COMMON.burn') }}
          </button>
        </MenuItem>
      </div>
    </template>
  </MinimalDropdownMenu>
</template>
