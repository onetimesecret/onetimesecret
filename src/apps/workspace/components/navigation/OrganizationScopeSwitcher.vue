<!-- src/apps/workspace/components/navigation/OrganizationScopeSwitcher.vue -->

<!--
  Organization Scope Switcher Component

  Allows users to switch between their organizations in the workspace header.
  Shows for any authenticated user with organizations (including default).

  Key behaviors:
  - Shows current organization with visual indicator
  - Dropdown menu with all available organizations
  - Links to organization management pages
  - "Create Organization" option for discoverability
  - Compact header-friendly design

  Uses HeadlessUI Menu for accessible keyboard navigation and focus management.
-->

<script setup lang="ts">
import OIcon from '@/shared/components/icons/OIcon.vue';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import type { Organization } from '@/types/organization';
import { Menu, MenuButton, MenuItem, MenuItems } from '@headlessui/vue';
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';

const { t } = useI18n();
const router = useRouter();
const organizationStore = useOrganizationStore();

// Note: Organizations are fetched by OrganizationContextBar parent component

/**
 * All organizations available for display (including default)
 */
const visibleOrganizations = computed<Organization[]>(() => organizationStore.organizations);

/**
 * Current selected organization (selected one, or first available)
 */
const currentOrganization = computed<Organization | null>(() => {
  if (organizationStore.currentOrganization) {
    return organizationStore.currentOrganization;
  }
  return visibleOrganizations.value[0] || null;
});

/**
 * Should component be visible - when user has any organizations
 */
const shouldShow = computed(() => organizationStore.hasOrganizations);

/**
 * Check if an organization is the default (personal) organization
 */
const isDefaultOrg = (org: Organization | null): boolean => org?.is_default ?? false;

/**
 * Check if current organization is the default
 */
const isCurrentOrgDefault = computed(() => isDefaultOrg(currentOrganization.value));

/**
 * Get initials for organization avatar (first letter)
 */
const getOrganizationInitial = (org: Organization): string =>
  (org.display_name || org.id || 'O').charAt(0).toUpperCase();

/**
 * Get display name for organization
 */
const getOrganizationDisplayName = (org: Organization): string =>
  org.display_name || org.id || t('web.organizations.organization');

/**
 * Check if an organization is the currently selected one
 */
const isCurrentOrganization = (org: Organization): boolean =>
  currentOrganization.value?.id === org.id;

/**
 * Handle organization selection
 */
const selectOrganization = (org: Organization): void => {
  organizationStore.setCurrentOrganization(org);
};

/**
 * Navigate to organization management page
 */
const navigateToManageOrganization = (org: Organization): void => {
  router.push(`/org/${org.extid || org.id}`);
};

/**
 * Navigate to create organization page
 */
const navigateToCreateOrganization = (): void => {
  router.push('/org');
};
</script>

<template>
  <Menu
    v-if="shouldShow"
    as="div"
    class="relative inline-flex"
    v-slot="{ open }">
    <!-- Trigger Button -->
    <MenuButton
      class="group inline-flex items-center gap-2 rounded-lg bg-gray-100 px-3 py-1.5 text-sm font-medium text-gray-700 transition-colors duration-150 hover:bg-gray-200 hover:text-gray-900 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:bg-gray-800 dark:text-gray-300 dark:hover:bg-gray-700 dark:hover:text-white dark:focus:ring-offset-gray-900"
      :aria-label="t('web.organizations.select_organization')">
      <!-- Organization Avatar -->
      <span
        v-if="currentOrganization"
        class="flex size-5 items-center justify-center rounded text-xs font-bold"
        :class="
          isCurrentOrgDefault
            ? 'bg-gray-200 dark:bg-gray-700'
            : 'bg-brand-600 text-white dark:bg-brand-500'
        "
        aria-hidden="true">
        <OIcon
          v-if="isCurrentOrgDefault"
          collection="heroicons"
          name="building-office"
          class="size-3.5 text-gray-600 dark:text-gray-300" />
        <template v-else>{{ getOrganizationInitial(currentOrganization) }}</template>
      </span>

      <!-- Current Organization Display -->
      <span class="max-w-[150px] truncate">
        {{
          currentOrganization
            ? getOrganizationDisplayName(currentOrganization)
            : t('web.organizations.select_organization')
        }}
      </span>

      <!-- Chevron -->
      <OIcon
        collection="heroicons"
        :name="open ? 'chevron-up-solid' : 'chevron-down-solid'"
        class="size-4 text-gray-400 transition-transform"
        aria-hidden="true" />
    </MenuButton>

    <!-- Dropdown Menu -->
    <transition
      enter-active-class="transition ease-out duration-100"
      enter-from-class="transform opacity-0 scale-95"
      enter-to-class="transform opacity-100 scale-100"
      leave-active-class="transition ease-in duration-75"
      leave-from-class="transform opacity-100 scale-100"
      leave-to-class="transform opacity-0 scale-95">
      <MenuItems
        class="absolute left-0 top-full z-50 mt-1 max-h-60 w-max min-w-[220px] max-w-xs overflow-auto rounded-lg bg-white py-1 text-sm shadow-lg ring-1 ring-black/5 focus:outline-none dark:bg-gray-800 dark:ring-gray-700">
        <!-- Header -->
        <div
          class="px-3 py-2 font-brand text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">
          {{ t('web.organizations.my_organizations') }}
        </div>

        <!-- Organization Options -->
        <MenuItem
          v-for="org in visibleOrganizations"
          :key="org.id"
          v-slot="{ active }"
          @click="selectOrganization(org)">
          <button
            type="button"
            class="relative w-full cursor-pointer select-none py-2 pl-3 pr-9 text-left text-gray-700 transition-colors duration-150 dark:text-gray-200"
            :class="[
              active ? 'bg-gray-100 dark:bg-gray-700' : '',
              isCurrentOrganization(org) ? 'bg-brand-50 dark:bg-brand-900/20' : '',
            ]">
            <span class="flex items-center gap-2">
              <!-- Organization Avatar -->
              <span
                class="flex size-5 items-center justify-center rounded text-xs font-bold"
                :class="[
                  isDefaultOrg(org)
                    ? 'bg-gray-200 dark:bg-gray-700'
                    : isCurrentOrganization(org)
                      ? 'bg-brand-600 text-white dark:bg-brand-500'
                      : 'bg-gray-300 text-gray-700 dark:bg-gray-600 dark:text-gray-200',
                ]"
                aria-hidden="true">
                <OIcon
                  v-if="isDefaultOrg(org)"
                  collection="heroicons"
                  name="building-office"
                  class="size-3.5 text-gray-600 dark:text-gray-300" />
                <template v-else>{{ getOrganizationInitial(org) }}</template>
              </span>

              <!-- Organization Name -->
              <span
                class="block truncate"
                :class="{ 'font-semibold': isCurrentOrganization(org) }">
                {{ getOrganizationDisplayName(org) }}
              </span>
            </span>

            <!-- Selected Checkmark -->
            <span
              v-if="isCurrentOrganization(org)"
              class="absolute inset-y-0 right-0 flex items-center pr-3">
              <OIcon
                collection="heroicons"
                name="check-20-solid"
                class="size-5 text-brand-600 dark:text-brand-400"
                aria-hidden="true" />
            </span>
          </button>
        </MenuItem>

        <!-- Divider -->
        <div
          class="my-1 border-t border-gray-200 dark:border-gray-700"
          role="separator"
          aria-hidden="true" ></div>

        <!-- Manage Current Organization Link -->
        <MenuItem
          v-if="currentOrganization"
          v-slot="{ active }"
          @click="navigateToManageOrganization(currentOrganization)">
          <button
            type="button"
            class="mx-2 w-[calc(100%-1rem)] cursor-pointer select-none rounded-md px-2 py-2 text-left text-gray-600 transition-colors duration-150 dark:text-gray-300"
            :class="active ? 'bg-gray-100 dark:bg-gray-700' : ''">
            <span class="flex items-center gap-2">
              <OIcon
                collection="heroicons"
                name="cog-6-tooth"
                class="size-4 text-gray-400 dark:text-gray-500"
                aria-hidden="true" />
              <span class="text-sm">{{ t('web.organizations.organization_settings') }}</span>
            </span>
          </button>
        </MenuItem>

        <!-- Create Organization Link -->
        <MenuItem v-slot="{ active }" @click="navigateToCreateOrganization">
          <button
            type="button"
            class="mx-2 w-[calc(100%-1rem)] cursor-pointer select-none rounded-md px-2 py-2 text-left transition-colors duration-150"
            :class="active ? 'bg-gray-100 dark:bg-gray-700' : ''">
            <span class="flex items-center gap-2">
              <OIcon
                collection="heroicons"
                name="plus"
                class="size-4 text-brand-500 dark:text-brand-400"
                aria-hidden="true" />
              <span class="text-sm text-brand-600 dark:text-brand-400">
                {{ t('web.organizations.create_organization') }}
              </span>
            </span>
          </button>
        </MenuItem>
      </MenuItems>
    </transition>
  </Menu>
</template>
