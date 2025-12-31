<!-- src/shared/components/navigation/DomainScopeSwitcher.vue -->

<!--
  Domain Scope Switcher Component

  Allows consultants to switch between their custom domains in the workspace header.
  Only visible when user has multiple domains configured.

  Key behaviors:
  - Shows current domain scope with visual indicator
  - Dropdown menu with all available domains
  - Persists selection via useDomainScope composable
  - Compact header-friendly design

  Uses HeadlessUI Menu for accessible keyboard navigation and focus management.
-->

<script setup lang="ts">
import OIcon from '@/shared/components/icons/OIcon.vue';
import { useDomainScope } from '@/shared/composables/useDomainScope';
import { Menu, MenuButton, MenuItem, MenuItems } from '@headlessui/vue';
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';

/**
 * Props for controlling switcher behavior from parent
 */
interface Props {
  /** When true, switcher shows current domain but dropdown is disabled */
  locked?: boolean;
}

const props = withDefaults(defineProps<Props>(), {
  locked: false,
});

const { t } = useI18n();
const router = useRouter();

const {
  currentScope,
  availableDomains,
  isScopeActive,
  setScope,
  getDomainDisplayName,
  getExtidByDomain,
} = useDomainScope();

/**
 * Check if a domain is the currently selected scope
 */
const isCurrentScope = (domain: string): boolean => domain === currentScope.value.domain;

/**
 * Handle domain selection
 */
const selectDomain = (domain: string): void => {
  setScope(domain);
};

/**
 * Should component be visible
 */
const shouldShow = computed(() => isScopeActive.value);

/**
 * Navigate to domains management page to add a new domain
 */
const navigateToAddDomain = (): void => {
  router.push('/domains');
};

/**
 * Navigate to edit a specific domain (uses extid for API routes)
 */
const navigateToDomainSettings = (domain: string, event: MouseEvent): void => {
  event.stopPropagation(); // Prevent row selection when clicking gear
  const extid = getExtidByDomain(domain);
  if (extid) {
    router.push(`/domains/${extid}/brand`);
  }
  // Canonical domain has no extid and no settings page
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
      class="group inline-flex items-center gap-2 rounded-lg bg-gray-100 px-3 py-1.5 text-sm font-medium text-gray-700 transition-colors duration-150 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:bg-gray-800 dark:text-gray-300 dark:focus:ring-offset-gray-900"
      :class="[
        props.locked
          ? 'cursor-default opacity-75'
          : 'hover:bg-gray-200 hover:text-gray-900 dark:hover:bg-gray-700 dark:hover:text-white',
      ]"
      :disabled="props.locked"
      :title="props.locked ? t('web.domains.switcher_locked') : undefined"
      :aria-label="t('web.domains.scope_switch_label')">
      <!-- Domain Icon -->
      <OIcon
        collection="heroicons"
        name="globe-alt"
        class="size-4 text-gray-500 group-hover:text-brand-500 dark:text-gray-400 dark:group-hover:text-brand-400"
        aria-hidden="true" />

      <!-- Current Domain Display -->
      <span class="max-w-[150px] truncate">
        {{ currentScope.displayName }}
      </span>

      <!-- Chevron or Lock icon -->
      <OIcon
        v-if="props.locked"
        collection="heroicons"
        name="lock-closed"
        class="size-4 text-gray-400"
        aria-hidden="true" />
      <OIcon
        v-else
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
          {{ t('web.domains.scope_header') }}
        </div>

        <!-- Domain Options -->
        <MenuItem
          v-for="domain in availableDomains"
          :key="domain"
          v-slot="{ active }"
          @click="selectDomain(domain)">
          <button
            type="button"
            class="group/row relative w-full cursor-pointer select-none py-2 pl-3 pr-9 text-left text-gray-700 transition-colors duration-150 dark:text-gray-200"
            :class="[
              active ? 'bg-gray-100 dark:bg-gray-700' : '',
              isCurrentScope(domain) ? 'bg-brand-50 dark:bg-brand-900/20' : '',
            ]">
            <span class="flex items-center gap-2">
              <!-- Domain-specific icon -->
              <OIcon
                collection="heroicons"
                :name="isCurrentScope(domain) && currentScope.isCanonical ? 'home' : 'globe-alt'"
                class="size-4 text-gray-400 dark:text-gray-500"
                aria-hidden="true" />

              <!-- Domain Name -->
              <span
                class="block truncate"
                :class="{ 'font-semibold': isCurrentScope(domain) }">
                {{ getDomainDisplayName(domain) }}
              </span>
            </span>

            <!-- Right action area: checkmark (active domain) / gear icon (on hover) -->
            <span class="absolute inset-y-0 right-0 flex items-center pr-3">
              <!-- Checkmark: visible for active domain -->
              <!-- For custom domains: hidden on row hover to show gear -->
              <!-- For canonical domain: always visible (no settings page) -->
              <OIcon
                v-if="isCurrentScope(domain)"
                collection="heroicons"
                name="check-20-solid"
                class="size-5 text-brand-600 dark:text-brand-400"
                :class="{ 'group-hover/row:hidden': getExtidByDomain(domain) }"
                aria-hidden="true" />

              <!-- Gear icon: visible on row hover for custom domains only (not canonical) -->
              <button
                v-if="getExtidByDomain(domain)"
                type="button"
                class="hidden rounded p-0.5 text-gray-400 transition-colors hover:bg-gray-200 hover:text-gray-600 group-hover/row:block dark:text-gray-500 dark:hover:bg-gray-600 dark:hover:text-gray-300"
                :aria-label="t('web.domains.domain_settings')"
                @click="navigateToDomainSettings(domain, $event)">
                <OIcon
                  collection="heroicons"
                  name="cog"
                  class="size-4"
                  aria-hidden="true" />
              </button>
            </span>
          </button>
        </MenuItem>

        <!-- Divider -->
        <div
          class="my-1 border-t border-gray-200 dark:border-gray-700"
          role="separator"
          aria-hidden="true" ></div>

        <!-- Add Domain Link -->
        <MenuItem v-slot="{ active }" @click="navigateToAddDomain">
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
                {{ t('web.domains.add_domain') }}
              </span>
            </span>
          </button>
        </MenuItem>
      </MenuItems>
    </transition>
  </Menu>
</template>
