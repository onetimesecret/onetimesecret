<!-- src/apps/workspace/components/navigation/DomainContextSwitcher.vue -->

<!--
  Domain Context Switcher (Production)

  User-facing dropdown for switching between custom domains in the workspace
  header. A thin adapter over the shared <ScopeSwitcher> engine: it maps the
  available domains into ScopeSwitcherItem[], supplies the domain-specific
  visuals via slots, and translates the engine's `select` / `open-settings`
  events into route-aware navigation. The dropdown open/close behaviour —
  including the gear icon's close — lives entirely in ScopeSwitcher.

  Key behaviors:
  - Shows current domain context with visual indicator
  - Dropdown menu with all available domains
  - Persists selection via useDomainContext composable
  - Route-aware navigation (updates URL when switching domains)
  - Add/Manage call-to-action for owners and admins

  Related component:
    src/apps/colonel/components/DomainContextSwitcher.vue
    - Admin tool for simulating arbitrary domains (not limited to user's domains)
    - Used for testing branding without DNS setup
    - Both share the same sessionStorage key ('domainContext')
-->

<script setup lang="ts">
import OIcon from '@/shared/components/icons/OIcon.vue';
import type { ScopeSwitcherItem } from '@/shared/components/navigation/scopeSwitcher';
import ScopeSwitcher from '@/shared/components/navigation/ScopeSwitcher.vue';
import { useDomainContext } from '@/shared/composables/useDomainContext';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import { ENTITLEMENTS } from '@/types/organization';
import type { ScopesAvailable } from '@/types/router';
import { isOwnerOrAdminOf } from '@/utils/features';
import { MenuItem } from '@headlessui/vue';
import { computed, watch } from 'vue';
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
 * Stable id for a domain row: its extid, or the 'canonical' sentinel for the
 * canonical domain (which never carries an extid).
 */
const idForDomain = (domain: string): string => getExtidByDomain(domain) ?? 'canonical';

/** Resolve a row id back to its domain string. */
const domainForId = (id: string): string | undefined =>
  availableDomains.value.find((domain) => idForDomain(domain) === id);

/**
 * The normalized rows handed to the engine. The engine never sees a raw domain.
 */
const domainItems = computed<ScopeSwitcherItem[]>(() =>
  availableDomains.value.map((domain) => ({
    id: idForDomain(domain),
    label: getDomainDisplayName(domain),
    isCurrent: isCurrentContext(domain),
    disabled: isOptionDisabled(domain),
    disabledReason: t('web.domains.canonical_no_settings'),
    // Gear shows for owners/admins on custom domains (which carry an extid).
    hasSettings: canManageDomains.value && !!getExtidByDomain(domain),
  }))
);

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
 * Handle domain selection with optional route-aware navigation.
 * The engine has already dismissed the dropdown before emitting `select`.
 */
const onSelect = (id: string): void => {
  const domain = domainForId(id);
  if (!domain || isOptionDisabled(domain)) return;

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
 * Navigate to edit a specific domain (uses org-qualified routes).
 * The engine has already stopPropagation'd and dismissed the dropdown.
 */
const onOpenSettings = (id: string): void => {
  const domain = domainForId(id);
  if (!domain) return;
  const extid = getExtidByDomain(domain);
  if (extid && currentOrgExtid.value) {
    router.push(`/org/${currentOrgExtid.value}/domains/${extid}`);
  }
  // Canonical domain has no extid and no settings page
};

/**
 * Navigate to domains management page (org-qualified)
 */
const navigateToManageDomains = (close?: () => void): void => {
  close?.();
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
const navigateToAddDomain = (close?: () => void): void => {
  close?.();
  if (currentOrgExtid.value) {
    router.push(`/org/${currentOrgExtid.value}/domains/add`);
  } else {
    router.push('/domains/add');
  }
};
</script>

<template>
  <ScopeSwitcher
    v-if="shouldShow"
    :items="domainItems"
    :header="t('web.domains.scope_header')"
    :locked="props.locked"
    :can-manage="canManageDomains"
    :trigger-aria-label="t('web.domains.scope_switch_label')"
    :trigger-title="currentContext.displayName"
    :locked-title="t('web.domains.switcher_locked')"
    :settings-label="t('web.domains.domain_settings')"
    testid="domain-context-switcher"
    item-testid="domain-menu-item"
    @select="onSelect"
    @open-settings="onOpenSettings">
    <!-- Trigger: globe icon + current domain -->
    <template #trigger>
      <OIcon
        collection="heroicons"
        name="globe-alt"
        aria-label=""
        class="size-4 text-gray-500 group-hover:text-brand-500 dark:text-gray-400 dark:group-hover:text-brand-400"
        aria-hidden="true" />
      <span
        class="hidden truncate md:inline md:max-w-[100px] lg:max-w-[140px]"
        :title="currentContext.domain">
        {{ currentContext.displayName }}
      </span>
    </template>

    <!-- Compact add-domain action: shown once an owner/admin already has a
         domain, so the "Add Domain" call to action demotes to an icon.
         This is a plain button, NOT a <MenuItem>, so HeadlessUI does not
         auto-close the menu on click — navigateToAddDomain(close) must call
         close() explicitly here (required, not belt-and-suspenders). -->
    <template
      v-if="canManageDomains && hasCustomDomains"
      #header-action="{ close }">
      <button
        type="button"
        class="-my-1 -mr-1 rounded p-1 text-gray-400 transition-colors hover:bg-gray-100 hover:text-brand-600 focus:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 dark:text-gray-500 dark:hover:bg-gray-700 dark:hover:text-brand-400"
        :title="t('web.domains.add_domain')"
        :aria-label="t('web.domains.add_domain')"
        data-testid="domain-context-add-icon"
        @click="navigateToAddDomain(close)">
        <OIcon
          collection="heroicons"
          name="plus-20-solid"
          class="size-4"
          aria-hidden="true" />
      </button>
    </template>

    <!-- Row leading icon: home for the canonical current context, else globe -->
    <template #item-visual="{ item }">
      <OIcon
        collection="heroicons"
        :name="item.isCurrent && currentContext.isCanonical ? 'home' : 'globe-alt'"
        class="size-4"
        :class="
          item.disabled
            ? 'text-gray-300 dark:text-gray-600'
            : 'text-gray-400 dark:text-gray-500'
        "
        aria-hidden="true" />
    </template>

    <!-- Footer call to action (owners and admins only; gated by can-manage) -->
    <template #footer="{ close }">
      <!-- No custom domains yet: prominent "Add Domain" call to action.
           "Manage Domains" makes no sense when there is nothing to manage. -->
      <MenuItem
        v-if="!hasCustomDomains"
        v-slot="{ active }"
        @click="navigateToAddDomain(close)">
        <button
          type="button"
          class="mx-2 w-[calc(100%-1rem)] cursor-pointer rounded-md px-2 py-2 text-left transition-colors duration-150 select-none"
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
        @click="navigateToManageDomains(close)">
        <button
          type="button"
          class="mx-2 w-[calc(100%-1rem)] cursor-pointer rounded-md px-2 py-2 text-left transition-colors duration-150 select-none"
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
  </ScopeSwitcher>
</template>
