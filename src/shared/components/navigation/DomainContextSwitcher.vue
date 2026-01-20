<!-- src/shared/components/navigation/DomainContextSwitcher.vue -->

<!--
  Domain Context Switcher Component

  Allows consultants to switch between their custom domains in the workspace header.
  Only visible when user has multiple domains configured.

  Key behaviors:
  - Shows current domain context with visual indicator
  - Dropdown menu with all available domains
  - Persists selection via useDomainContext composable
  - Compact header-friendly design

  Uses HeadlessUI Menu for accessible keyboard navigation and focus management.
-->

<script setup lang="ts">
import OIcon from '@/shared/components/icons/OIcon.vue';
import { useDomainContext } from '@/shared/composables/useDomainContext';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import type { ScopesAvailable } from '@/types/router';
import { Menu, MenuButton, MenuItem, MenuItems } from '@headlessui/vue';
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';

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
const route = useRoute();
const router = useRouter();
const organizationStore = useOrganizationStore();

// Get current organization extid for org-qualified routes
const currentOrgExtid = computed(() => organizationStore.currentOrganization?.extid);

/**
 * Get the onDomainSwitch navigation target from route meta
 */
const onDomainSwitch = computed<string | undefined>(() => {
  const scopesAvailable = route.meta?.scopesAvailable as ScopesAvailable | undefined;
  return scopesAvailable?.onDomainSwitch;
});

const {
  currentContext,
  availableDomains,
  isContextActive,
  setContext,
  getDomainDisplayName,
  getExtidByDomain,
} = useDomainContext();

/**
 * Check if a domain is the currently selected context
 */
const isCurrentContext = (domain: string): boolean => domain === currentContext.value.domain;

/**
 * Check if a domain option should be disabled.
 * Canonical domain is disabled when onDomainSwitch requires navigation
 * (since canonical has no extid and no settings page).
 */
const isOptionDisabled = (domain: string): boolean => {
  const extid = getExtidByDomain(domain);
  if (!extid && onDomainSwitch.value) {
    // Canonical domain can't navigate when onDomainSwitch requires :extid
    return onDomainSwitch.value === 'same' || onDomainSwitch.value.includes(':extid');
  }
  return false;
};

/**
 * Handle domain selection with optional navigation
 */
const selectDomain = (domain: string): void => {
  // Don't allow selection of disabled options
  if (isOptionDisabled(domain)) {
    return;
  }

  setContext(domain);

  // Handle route-aware navigation based on onDomainSwitch meta
  const switchTarget = onDomainSwitch.value;
  if (!switchTarget) {
    // No navigation configured, just update store (current behavior)
    return;
  }

  const extid = getExtidByDomain(domain);

  if (switchTarget === 'same') {
    // Stay on current route pattern, replace :extid with new domain's extid
    if (!extid) {
      console.warn('[DomainContextSwitcher] Cannot navigate: domain missing extid', domain);
      return;
    }
    const matchedRoute = route.matched[route.matched.length - 1];
    if (matchedRoute?.path) {
      const newPath = matchedRoute.path.replace(':extid', extid);
      router.push(newPath);
    }
  } else if (switchTarget.includes(':extid')) {
    // Path with :extid placeholder - replace and navigate
    if (!extid) {
      console.warn('[DomainContextSwitcher] Cannot navigate: domain missing extid', domain);
      return;
    }
    const newPath = switchTarget.replace(':extid', extid);
    router.push(newPath);
  } else {
    // Path without :extid - navigate directly
    router.push(switchTarget);
  }
};

/**
 * Should component be visible
 */
const shouldShow = computed(() => isContextActive.value);

/**
 * Navigate to domains management page (org-qualified)
 */
const navigateToManageDomains = (): void => {
  if (currentOrgExtid.value) {
    router.push(`/org/${currentOrgExtid.value}`);
  } else {
    router.push('/dashboard');
  }
};

/**
 * Navigate to edit a specific domain (uses org-qualified routes)
 */
const navigateToDomainSettings = (domain: string, event: MouseEvent): void => {
  event.stopPropagation(); // Prevent row selection when clicking gear
  const extid = getExtidByDomain(domain);
  if (extid && currentOrgExtid.value) {
    router.push(`/org/${currentOrgExtid.value}/domains/${extid}/brand`);
  }
  // Canonical domain has no extid and no settings page
};
</script>

<template>
  <Menu
    v-if="shouldShow"
    as="div"
    class="relative inline-flex"
    data-testid="domain-context-switcher"
    v-slot="{ open }">
    <!-- Trigger Button -->
    <MenuButton
      class="group inline-flex h-10 items-center gap-2 rounded-lg bg-gray-100 px-3 text-sm font-medium text-gray-700 transition-colors duration-150 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:bg-gray-800 dark:text-gray-300 dark:focus:ring-offset-gray-900"
      :class="[
        props.locked
          ? 'cursor-default opacity-75'
          : 'hover:bg-gray-200 hover:text-gray-900 dark:hover:bg-gray-700 dark:hover:text-white',
      ]"
      :disabled="props.locked"
      :title="props.locked ? t('web.domains.switcher_locked') : undefined"
      :aria-label="t('web.domains.scope_switch_label')"
      :aria-disabled="props.locked ? 'true' : undefined"
      data-testid="domain-context-switcher-trigger">
      <!-- Domain Icon -->
      <OIcon
        collection="heroicons"
        name="globe-alt"
        class="size-4 text-gray-500 group-hover:text-brand-500 dark:text-gray-400 dark:group-hover:text-brand-400"
        aria-hidden="true" />

      <!-- Current Domain Display (truncated at all sizes, tighter on mobile) -->
      <span
        class="max-w-[100px] truncate sm:max-w-[120px] md:max-w-[160px] lg:max-w-[200px]"
        :title="currentContext.domain">
        {{ currentContext.displayName }}
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
        class="absolute left-0 top-full z-50 mt-1 max-h-60 w-max min-w-[220px] max-w-xs overflow-auto rounded-lg bg-white py-1 text-sm shadow-lg ring-1 ring-black/5 focus:outline-none dark:bg-gray-800 dark:ring-gray-700"
        data-testid="domain-context-switcher-dropdown">
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
          :disabled="isOptionDisabled(domain)"
          @click="selectDomain(domain)">
          <button
            type="button"
            class="group/row relative w-full select-none py-2 pl-3 pr-9 text-left transition-colors duration-150"
            :class="[
              isOptionDisabled(domain)
                ? 'cursor-not-allowed text-gray-400 opacity-60 dark:text-gray-600'
                : 'cursor-pointer text-gray-700 dark:text-gray-200',
              !isOptionDisabled(domain) && active ? 'bg-gray-100 dark:bg-gray-700' : '',
              isCurrentContext(domain) && !isOptionDisabled(domain)
                ? 'bg-brand-50 dark:bg-brand-900/20'
                : '',
            ]"
            :title="
              isOptionDisabled(domain)
                ? t('web.domains.canonical_no_settings')
                : undefined
            "
            :aria-disabled="isOptionDisabled(domain) ? 'true' : undefined">
            <span class="flex items-center gap-2">
              <!-- Domain-specific icon -->
              <OIcon
                collection="heroicons"
                :name="isCurrentContext(domain) && currentContext.isCanonical ? 'home' : 'globe-alt'"
                class="size-4"
                :class="
                  isOptionDisabled(domain)
                    ? 'text-gray-300 dark:text-gray-600'
                    : 'text-gray-400 dark:text-gray-500'
                "
                aria-hidden="true" />

              <!-- Domain Name -->
              <span
                class="block truncate"
                :class="{ 'font-semibold': isCurrentContext(domain) && !isOptionDisabled(domain) }">
                {{ getDomainDisplayName(domain) }}
              </span>
            </span>

            <!-- Right action area: checkmark (active domain) / gear icon (on hover) -->
            <span class="absolute inset-y-0 right-0 flex items-center pr-3">
              <!-- Checkmark: visible for active domain -->
              <!-- For custom domains: hidden on row hover to show gear -->
              <!-- For canonical domain: always visible (no settings page) -->
              <OIcon
                v-if="isCurrentContext(domain)"
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

        <!-- Manage Domains Link -->
        <MenuItem v-slot="{ active }" @click="navigateToManageDomains">
          <button
            type="button"
            class="mx-2 w-[calc(100%-1rem)] cursor-pointer select-none rounded-md px-2 py-2 text-left transition-colors duration-150"
            :class="active ? 'bg-gray-100 dark:bg-gray-700' : ''"
            data-testid="domain-context-manage-link">
            <span class="flex items-center gap-2">
              <OIcon
                collection="heroicons"
                name="cog-6-tooth"
                class="size-4 text-gray-500 dark:text-gray-400"
                aria-hidden="true" />
              <span class="text-sm text-gray-700 dark:text-gray-300">
                {{ t('web.domains.manage_domains') }}
              </span>
            </span>
          </button>
        </MenuItem>
      </MenuItems>
    </transition>
  </Menu>
</template>
