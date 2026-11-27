<!-- src/shared/components/ui/MinimalDropdownMenu.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useMenuPlacement, type ElementLike } from '@/shared/composables/useMenuPlacement';
  import { Menu, MenuButton, MenuItems } from '@headlessui/vue';
  import { ref } from 'vue';

const { t } = useI18n();

// Opens upward near the bottom so the mobile nav and footer don't cover it.
const triggerRef = ref<ElementLike>(null);
const menuRef = ref<ElementLike>(null);
const { placement } = useMenuPlacement(triggerRef, menuRef);

</script>

<template>
  <Menu
    as="div"
    class="relative inline-block text-left">
    <div>
      <MenuButton
        ref="triggerRef"
        class="flex items-center rounded-full text-gray-400 hover:text-gray-600 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 focus:ring-offset-gray-100 dark:text-gray-400 dark:hover:text-gray-300 dark:focus:ring-indigo-400 dark:focus:ring-offset-gray-900">
        <span class="sr-only">{{ t('web.COMMON.open_options') }}</span>
        <OIcon
          class="size-5"
          collection="heroicons-solid"
          name="ellipsis-vertical" />
      </MenuButton>
    </div>

    <transition
      enter-active-class="transition ease-out duration-100"
      enter-from-class="transform opacity-0 scale-95"
      enter-to-class="transform opacity-100 scale-100"
      leave-active-class="transition ease-in duration-75"
      leave-from-class="transform opacity-100 scale-100"
      leave-to-class="transform opacity-0 scale-95">
      <MenuItems
        ref="menuRef"
        :data-placement="placement"
        :class="placement === 'above' ? 'bottom-full mb-2 origin-bottom-right' : 'mt-2 origin-top-right'"
        class="absolute right-0 z-50 w-56 rounded-md bg-white shadow-lg ring-1 ring-black/5 focus:outline-none dark:bg-gray-800 dark:shadow-lg dark:shadow-gray-900/50 dark:ring-gray-700/70">
        <div class="py-1">
          <slot name="menu-items"></slot>
        </div>
      </MenuItems>
    </transition>
  </Menu>
</template>
