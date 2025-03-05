<!-- src/components/MinimalDropdownMenu.vue -->

<script setup lang="ts">
  import { Menu, MenuButton, MenuItems } from '@headlessui/vue';
  import OIcon from '@/components/icons/OIcon.vue';
</script>

<template>
  <Menu as="div"
        class="relative inline-block text-left">
    <div>
      <MenuButton
                  class="flex items-center rounded-full text-gray-400 hover:text-gray-600 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 focus:ring-offset-gray-100 dark:text-gray-400 dark:hover:text-gray-300 dark:focus:ring-indigo-400 dark:focus:ring-offset-gray-900">
        <span class="sr-only">{{ $t('open-options') }}</span>
        <OIcon class="size-5"
               collection="heroicons-solid"
               name="ellipsis-vertical" />
      </MenuButton>
    </div>

    <transition enter-active-class="transition ease-out duration-100"
                enter-from-class="transform opacity-0 scale-95"
                enter-to-class="transform opacity-100 scale-100"
                leave-active-class="transition ease-in duration-75"
                leave-from-class="transform opacity-100 scale-100"
                leave-to-class="transform opacity-0 scale-95">
      <MenuItems
                 class="absolute right-0 z-50 mt-2 w-56 origin-top-right rounded-md bg-white shadow-lg ring-1 ring-black ring-opacity-5 focus:outline-none dark:bg-gray-800 dark:shadow-lg dark:shadow-gray-900/50 dark:ring-gray-700 dark:ring-opacity-70">
        <div class="py-1">
          <slot name="menu-items"></slot>
        </div>
      </MenuItems>
    </transition>
  </Menu>
</template>
