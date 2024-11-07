<template>
  <Menu as="div"
        class="relative inline-block text-left">
    <div>
      <MenuButton
                  class="flex items-center rounded-full text-gray-400 hover:text-gray-600 dark:text-gray-400 dark:hover:text-gray-300 focus:outline-none focus:ring-2 focus:ring-indigo-500 dark:focus:ring-indigo-400 focus:ring-offset-2 focus:ring-offset-gray-100 dark:focus:ring-offset-gray-900">
        <span class="sr-only">Open options</span>
        <Icon icon="heroicons:ellipsis-vertical-20-solid"
              class="h-5 w-5"
              aria-hidden="true" />
      </MenuButton>
    </div>

    <transition enter-active-class="transition ease-out duration-100"
                enter-from-class="transform opacity-0 scale-95"
                enter-to-class="transform opacity-100 scale-100"
                leave-active-class="transition ease-in duration-75"
                leave-from-class="transform opacity-100 scale-100"
                leave-to-class="transform opacity-0 scale-95">
      <MenuItems
                 class="absolute right-0 z-50 mt-2 w-56 origin-top-right rounded-md bg-white dark:bg-gray-800 shadow-lg dark:shadow-lg dark:shadow-gray-900/50 ring-1 ring-black dark:ring-gray-700 ring-opacity-5 dark:ring-opacity-70 focus:outline-none">
        <div class="py-1">
          <slot name="menu-items"/>
        </div>
      </MenuItems>
    </transition>
  </Menu>
</template>


<script setup>
import { Menu, MenuButton, MenuItems } from '@headlessui/vue'
import { Icon } from '@iconify/vue'
</script>
