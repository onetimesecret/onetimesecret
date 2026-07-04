<!-- src/shared/components/navigation/DomainContextSwitcher.vue -->

<!--
  Domain Context Switcher Component (Production)

  User-facing dropdown for switching between custom domains in the workspace header.
  Only visible when user has multiple domains configured.

  Key behaviors:
  - Shows current domain context with visual indicator
  - Dropdown menu with all available domains
  - Persists selection via useDomainContext composable
  - Route-aware navigation (updates URL when switching domains)
  - Compact header-friendly design

  Uses HeadlessUI Menu for accessible keyboard navigation and focus management.

  Related component:
    src/apps/colonel/components/DomainContextSwitcher.vue
    - Admin tool for simulating arbitrary domains (not limited to user's domains)
    - Used for testing branding without DNS setup
    - Both share the same sessionStorage key ('domainContext')
-->

<script setup lang="ts">
import OIcon from '@/shared/components/icons/OIcon.vue';
import { useDomainContext } from '@/shared/composables/useDomainContext';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import { ENTITLEMENTS } from '@/types/organization';
import type { ScopesAvailable } from '@/types/router';
import { Menu, MenuButton, MenuItem, MenuItems } from '@headlessui/vue';
import { computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { isOwnerOrAdminOf } from '@/utils/features';

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
const bootstrapStore = useBootstrapStore();

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
  setContextByExtid,
  initialized,
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
      // Replace :extid (domain param) with new domain's extid.
      // Also replace :orgid (org param) with current org extid so the literal
      // route pattern placeholder doesn't appear in the navigated URL.
      let newPath = matchedRoute.path.replace(':extid', extid);
      if (currentOrgExtid.value) {
        newPath = newPath.replace(':orgid', currentOrgExtid.value);
      }
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
 * Whether the current user can manage domains (owner or admin of current org).
 * Standalone (billing disabled): owner/admin role alone is sufficient.
 * Billing enabled: owner/admin + manage_org entitlement required.
 */
const canManageDomains = computed(() => {
  const org = organizationStore.currentOrganization;
  if (!isOwnerOrAdminOf({ organization: org })) return false;

  if (!bootstrapStore.billing_enabled) return true;

  const ents = org?.entitlements;
  if (!ents) return true;
  return ents.includes(ENTITLEMENTS.MANAGE_ORG);
});

/**
 * Number of custom (non-canonical) domains in the current org context.
 * Custom domains always carry an extid; the canonical domain never does.
 */
const customDomainCount = computed(
  () => availableDomains.value.filter((domain) => getExtidByDomain(domain)).length
);

/**
 * Whether the current org context has at least one custom domain.
 *
 * Drives the add/manage call-to-action for owners and admins:
 * - No custom domains  → prominent "Add Domain" link (nothing to manage yet).
 * - Has custom domains → compact [+] icon in the dropdown header (add another),
 *   with the existing "Manage Domains" link retained below.
 */
const hasCustomDomains = computed(() => customDomainCount.value > 0);

/**
 * Should component be visible
 */
const shouldShow = computed(() => isContextActive.value);

// Sync domain context when route :extid param changes (e.g., navigating to a domain detail page)
watch(
  () => route.params.extid as string | undefined,
  async (extid) => {
    if (extid && shouldShow.value) {
      await initialized;
      setContextByExtid(extid);
    }
  },
  { immediate: true }
);

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
 * Navigate to the add-domain page (org-qualified).
 * Falls back to the /domains/add redirect when no org context is available.
 */
const navigateToAddDomain = (): void => {
  if (currentOrgExtid.value) {
    router.push(`/org/${currentOrgExtid.value}/domains/add`);
  } else {
    router.push('/domains/add');
  }
};

/**
 * Navigate to edit a specific domain (uses org-qualified routes)
 */
const navigateToDomainSettings = (domain: string, event: MouseEvent): void => {
  event.stopPropagation(); // Prevent row selection when clicking gear
  const extid = getExtidByDomain(domain);
  if (extid && currentOrgExtid.value) {
    router.push(`/org/${currentOrgExtid.value}/domains/${extid}`);
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
    v-slot="{ open, close }">
    <!-- Trigger Button -->
    <MenuButton
      class="group inline-flex h-10 items-center gap-2 rounded-lg bg-gray-100 px-3 text-sm font-medium text-gray-700 transition-colors duration-150 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:bg-gray-800 dark:text-gray-300 dark:focus:ring-offset-gray-900"
      :class="[
        props.locked
          ? 'cursor-default opacity-75'
          : 'hover:bg-gray-200 hover:text-gray-900 dark:hover:bg-gray-700 dark:hover:text-white',
      ]"
      :disabled="props.locked"
      :title="props.locked ? t('web.domains.switcher_locked') : currentContext.displayName"
      :aria-label="t('web.domains.scope_switch_label')"
      :aria-disabled="props.locked ? 'true' : undefined"
      data-testid="domain-context-switcher-trigger">
      <!-- Domain Icon -->
      <OIcon
        collection="heroicons"
        name="globe-alt"
        aria-label=""
        class="size-4 text-gray-500 group-hover:text-brand-500 dark:text-gray-400 dark:group-hover:text-brand-400"
        aria-hidden="true" />

      <!-- Current Domain Display (truncated at all sizes, tighter on mobile) -->
      <span
        class="hidden truncate md:inline md:max-w-[100px] lg:max-w-[140px]"
        :title="currentContext.domain">
        {{ currentContext.displayName }}
      </span>

      <!-- Chevron or Lock icon -->
      <OIcon
        v-if="props.locked"
        collection="heroicons"
        name="lock-closed"
        aria-label=""
        class="size-4 text-gray-400"
        aria-hidden="true" />
      <OIcon
        v-else
        collection="heroicons"
        :name="open ? 'chevron-up-solid' : 'chevron-down-solid'"
        aria-label=""
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
        <div class="flex items-center justify-between px-3 py-2">
          <span
            class="font-brand text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">
            {{ t('web.domains.scope_header') }}
          </span>

          <!-- Compact add-domain action: shown once an owner/admin already has
               a domain, so the "Add Domain" call to action demotes to an icon. -->
          <button
            v-if="canManageDomains && hasCustomDomains"
            type="button"
            class="-my-1 -mr-1 rounded p-1 text-gray-400 transition-colors hover:bg-gray-100 hover:text-brand-600 focus:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 dark:text-gray-500 dark:hover:bg-gray-700 dark:hover:text-brand-400"
            :title="t('web.domains.add_domain')"
            :aria-label="t('web.domains.add_domain')"
            data-testid="domain-context-add-icon"
            @click="() => { close?.(); navigateToAddDomain(); }">
            <OIcon
              collection="heroicons"
              name="plus-20-solid"
              class="size-4"
              aria-hidden="true" />
          </button>
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
              <!-- For custom domains: hidden on row hover to show gear (owners/admins only) -->
              <!-- For canonical domain or members: always visible (no settings page) -->
              <OIcon
                v-if="isCurrentContext(domain)"
                collection="heroicons"
                name="check-20-solid"
                class="size-5 text-brand-600 dark:text-brand-400"
                :class="{ 'group-hover/row:hidden': canManageDomains && getExtidByDomain(domain) }"
                aria-hidden="true" />

              <!-- Gear icon: visible on row hover for owners/admins on custom domains -->
              <button
                v-if="canManageDomains && getExtidByDomain(domain)"
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

        <!-- Divider + footer call to action (owners and admins only) -->
        <template v-if="canManageDomains">
        <div
          class="my-1 border-t border-gray-200 dark:border-gray-700"
          role="separator"
          aria-hidden="true" ></div>

        <!-- No custom domains yet: prominent "Add Domain" call to action.
             "Manage Domains" makes no sense when there is nothing to manage. -->
        <MenuItem
          v-if="!hasCustomDomains"
          v-slot="{ active }"
          @click="navigateToAddDomain">
          <button
            type="button"
            class="mx-2 w-[calc(100%-1rem)] cursor-pointer select-none rounded-md px-2 py-2 text-left transition-colors duration-150"
            :class="active ? 'bg-gray-100 dark:bg-gray-700' : ''"
            data-testid="domain-context-add-link">
            <span class="flex items-center gap-2">
              <OIcon
                collection="heroicons"
                name="plus-20-solid"
                class="size-4 text-gray-500 dark:text-gray-400"
                aria-hidden="true" />
              <span class="text-sm text-gray-700 dark:text-gray-300">
                {{ t('web.domains.add_domain') }}
              </span>
            </span>
          </button>
        </MenuItem>

        <!-- Has custom domains: keep the "Manage Domains" link
             (the "Add Domain" action lives in the header [+] icon). -->
        <MenuItem
          v-else
          v-slot="{ active }"
          @click="navigateToManageDomains">
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
        </template>
      </MenuItems>
    </transition>
  </Menu>
</template>
