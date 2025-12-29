<!-- src/apps/workspace/components/members/MemberRoleSelector.vue -->

<script setup lang="ts">
import OIcon from '@/shared/components/icons/OIcon.vue';
import type { OrganizationRole } from '@/types/organization';
import {
  Listbox,
  ListboxButton,
  ListboxOption,
  ListboxOptions,
} from '@headlessui/vue';
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();

interface RoleOption {
  value: OrganizationRole;
  label: string;
  description: string;
}

const props = defineProps<{
  modelValue: OrganizationRole;
  disabled?: boolean;
  availableRoles?: OrganizationRole[];
}>();

const emit = defineEmits<{
  (e: 'update:modelValue', value: OrganizationRole): void;
}>();

const allRoles: RoleOption[] = [
  {
    value: 'owner',
    label: t('web.organizations.members.roles.owner'),
    description: t('web.organizations.members.role_descriptions.owner'),
  },
  {
    value: 'admin',
    label: t('web.organizations.members.roles.admin'),
    description: t('web.organizations.members.role_descriptions.admin'),
  },
  {
    value: 'member',
    label: t('web.organizations.members.roles.member'),
    description: t('web.organizations.members.role_descriptions.member'),
  },
];

const roles = computed(() => {
  if (props.availableRoles && props.availableRoles.length > 0) {
    return allRoles.filter((r) => props.availableRoles?.includes(r.value));
  }
  return allRoles.filter((r) => r.value !== 'owner');
});

const selectedRole = computed(() => allRoles.find((r) => r.value === props.modelValue) ?? allRoles[2]);

const handleSelect = (role: RoleOption) => {
  emit('update:modelValue', role.value);
};

const getRoleBadgeClasses = (role: OrganizationRole): string => {
  const baseClasses =
    'inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium';

  switch (role) {
    case 'owner':
      return `${baseClasses} bg-amber-100 text-amber-800 dark:bg-amber-900/30 dark:text-amber-400`;
    case 'admin':
      return `${baseClasses} bg-blue-100 text-blue-800 dark:bg-blue-900/30 dark:text-blue-400`;
    case 'member':
    default:
      return `${baseClasses} bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-300`;
  }
};
</script>

<template>
  <div class="relative">
    <!-- Static badge display when disabled -->
    <span
      v-if="disabled"
      :class="getRoleBadgeClasses(modelValue)">
      {{ selectedRole.label }}
    </span>

    <!-- Interactive dropdown when enabled -->
    <Listbox
      v-else
      :model-value="selectedRole"
      @update:model-value="handleSelect">
      <div class="relative">
        <ListboxButton
          class="relative w-full cursor-pointer rounded-md border border-gray-300 bg-white py-1.5 pl-3 pr-10 text-left text-sm shadow-sm focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-800 dark:focus:border-brand-400 dark:focus:ring-brand-400">
          <span :class="getRoleBadgeClasses(modelValue)">
            {{ selectedRole.label }}
          </span>
          <span
            class="pointer-events-none absolute inset-y-0 right-0 flex items-center pr-2">
            <OIcon
              collection="heroicons"
              name="chevron-up-down"
              class="size-4 text-gray-400"
              aria-hidden="true" />
          </span>
        </ListboxButton>

        <transition
          leave-active-class="transition duration-100 ease-in"
          leave-from-class="opacity-100"
          leave-to-class="opacity-0">
          <ListboxOptions
            class="absolute z-10 mt-1 max-h-60 w-full min-w-max overflow-auto rounded-md bg-white py-1 text-sm shadow-lg ring-1 ring-black/5 focus:outline-none dark:bg-gray-800 dark:ring-gray-700">
            <ListboxOption
              v-for="role in roles"
              :key="role.value"
              v-slot="{ active, selected }"
              :value="role"
              as="template">
              <li
                :class="[
                  active
                    ? 'bg-brand-50 text-brand-900 dark:bg-brand-900/20 dark:text-brand-100'
                    : 'text-gray-900 dark:text-gray-100',
                  'relative cursor-pointer select-none py-2 pl-3 pr-9',
                ]">
                <div class="flex flex-col">
                  <span
                    :class="[
                      selected ? 'font-semibold' : 'font-normal',
                      'block truncate',
                    ]">
                    <span :class="getRoleBadgeClasses(role.value)">
                      {{ role.label }}
                    </span>
                  </span>
                  <span
                    :class="[
                      active
                        ? 'text-brand-700 dark:text-brand-300'
                        : 'text-gray-500 dark:text-gray-400',
                      'mt-1 block text-xs',
                    ]">
                    {{ role.description }}
                  </span>
                </div>

                <span
                  v-if="selected"
                  :class="[
                    active ? 'text-brand-600' : 'text-brand-600',
                    'absolute inset-y-0 right-0 flex items-center pr-3',
                  ]">
                  <OIcon
                    collection="heroicons"
                    name="check"
                    class="size-5"
                    aria-hidden="true" />
                </span>
              </li>
            </ListboxOption>
          </ListboxOptions>
        </transition>
      </div>
    </Listbox>
  </div>
</template>
