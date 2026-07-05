<!-- src/apps/workspace/components/navigation/OrganizationScopeSwitcher.vue -->

<!--
  Organization Scope Switcher Component

  Allows users to switch between their organizations in the workspace header.
  Shows for any authenticated user with organizations (including default).

  A thin adapter over the shared <ScopeSwitcher> engine: it maps the available
  organizations into ScopeSwitcherItem[], supplies the org-specific visuals via
  slots, and translates the engine's `select` / `open-settings` events into
  route-aware navigation. The dropdown open/close behaviour — including the gear
  icon's close — lives entirely in ScopeSwitcher.

  Key behaviors:
  - Shows current organization with visual indicator
  - Dropdown menu with all available organizations
  - Links to organization management pages
  - Compact header-friendly design
-->

<script setup lang="ts">
import OIcon from '@/shared/components/icons/OIcon.vue';
import type { ScopeSwitcherItem } from '@/shared/components/navigation/scopeSwitcher';
import ScopeSwitcher from '@/shared/components/navigation/ScopeSwitcher.vue';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import type { Organization } from '@/types/organization';
import type { ScopesAvailable } from '@/types/router';
import { MenuItem } from '@headlessui/vue';
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';

/**
 * Props for controlling switcher behavior from parent
 */
interface Props {
  /** When true, switcher shows current org but dropdown is disabled */
  locked?: boolean;
}

const props = withDefaults(defineProps<Props>(), {
  locked: false,
});

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const organizationStore = useOrganizationStore();

/**
 * Get the onOrgSwitch navigation target from route meta
 */
const onOrgSwitch = computed<string | undefined>(() => {
  const scopesAvailable = route.meta?.scopesAvailable as ScopesAvailable | undefined;
  return scopesAvailable?.onOrgSwitch;
});

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
 * Check if an organization has a paid plan
 * Paid = planid exists and doesn't start with "free"
 */
const hasPaidPlan = (org: Organization): boolean => {
  if (!org.planid) return false;
  return !org.planid.toLowerCase().startsWith('free');
};

/**
 * Get initials for organization avatar (first letter)
 */
const getOrganizationInitial = (org: Organization): string =>
  (org.display_name || org.objid || 'O').charAt(0).toUpperCase();

/**
 * Get display name for organization
 */
const getOrganizationDisplayName = (org: Organization): string =>
  org.display_name || org.objid || t('web.organizations.organization');

/**
 * Check if an organization is the currently selected one
 */
const isCurrentOrganization = (org: Organization): boolean =>
  currentOrganization.value?.objid === org.objid;

/**
 * Stable id for an org row: its extid, falling back to objid for orgs that have
 * no extid (which also means no settings/gear).
 */
const idForOrg = (org: Organization): string => org.extid ?? org.objid;

/** id → org lookup, used by the row slots to recover the source object. */
const orgById = computed<Record<string, Organization>>(() => {
  const map: Record<string, Organization> = {};
  for (const org of visibleOrganizations.value) map[idForOrg(org)] = org;
  return map;
});

/** Resolve a row id back to its organization. */
const orgForId = (id: string): Organization | undefined => orgById.value[id];

/**
 * The normalized rows handed to the engine. The engine never sees a raw org.
 */
const organizationItems = computed<ScopeSwitcherItem[]>(() =>
  visibleOrganizations.value.map((org) => ({
    id: idForOrg(org),
    label: getOrganizationDisplayName(org),
    isCurrent: isCurrentOrganization(org),
    // Gear (settings) shows for orgs that carry an extid to navigate to.
    hasSettings: !!org.extid,
  }))
);

/**
 * Handle organization selection with optional route-aware navigation.
 * The engine has already dismissed the dropdown before emitting `select`.
 */
const onSelect = (id: string): void => {
  const org = orgForId(id);
  if (!org) return;

  // setCurrentOrganization triggers the store's watcher to persist to localStorage
  organizationStore.setCurrentOrganization(org);

  // Handle route-aware navigation based on onOrgSwitch meta
  const switchTarget = onOrgSwitch.value;
  if (!switchTarget) {
    // No navigation configured, just update store (current behavior)
    return;
  }

  if (switchTarget === 'same') {
    if (!org.extid) {
      console.warn('[OrganizationScopeSwitcher] Cannot navigate: org missing extid', org.objid);
      return;
    }
    if (route.name) {
      router.push({ name: route.name, params: { ...route.params, extid: org.extid } });
    }
  } else if (switchTarget.includes(':extid')) {
    if (!org.extid) {
      console.warn('[OrganizationScopeSwitcher] Cannot navigate: org missing extid', org.objid);
      return;
    }
    const newPath = switchTarget.replace(':extid', org.extid);
    router.push(newPath);
  } else {
    // Path without :extid - navigate directly
    router.push(switchTarget);
  }
};

/**
 * Navigate to organization management page (requires extid).
 * The engine has already stopPropagation'd and dismissed the dropdown.
 */
const onOpenSettings = (id: string): void => {
  const org = orgForId(id);
  if (!org?.extid) {
    // Cannot navigate without extid - gear icon should be hidden for these orgs
    console.warn('[OrganizationScopeSwitcher] Cannot navigate: org missing extid', org?.objid);
    return;
  }
  router.push(`/org/${org.extid}`);
};

/**
 * Navigate to manage organizations page
 */
const navigateToManageOrganizations = (close?: () => void): void => {
  close?.();
  router.push('/orgs');
};
</script>

<template>
  <ScopeSwitcher
    v-if="shouldShow"
    :items="organizationItems"
    :header="t('web.organizations.my_organizations')"
    :locked="props.locked"
    :can-manage="true"
    :trigger-aria-label="t('web.organizations.select_organization')"
    :trigger-title="currentOrganization ? getOrganizationDisplayName(currentOrganization) : undefined"
    :locked-title="t('web.organizations.switcher_locked')"
    :settings-label="t('web.organizations.organization_settings')"
    testid="org-scope-switcher"
    item-testid="org-menu-item"
    @select="onSelect"
    @open-settings="onOpenSettings">
    <!-- Trigger: org avatar + current org name -->
    <template #trigger>
      <span
        v-if="currentOrganization"
        class="flex size-5 items-center justify-center rounded text-xs font-bold"
        :class="
          isCurrentOrgDefault
            ? 'bg-gray-200 dark:bg-gray-700'
            : 'bg-brand-500 text-white dark:bg-brand-500'
        "
        aria-hidden="true">
        <OIcon
          v-if="isCurrentOrgDefault"
          collection="heroicons"
          name="building-office"
          class="size-3.5 text-gray-600 dark:text-gray-300" />
        <template v-else>{{ getOrganizationInitial(currentOrganization) }}</template>
      </span>
      <span
        class="hidden max-w-[80px] truncate lg:inline lg:max-w-[120px]"
        :title="currentOrganization ? getOrganizationDisplayName(currentOrganization) : undefined">
        {{
          currentOrganization
            ? getOrganizationDisplayName(currentOrganization)
            : t('web.organizations.select_organization')
        }}
      </span>
    </template>

    <!-- Row leading avatar -->
    <template #item-visual="{ item }">
      <span
        class="flex size-5 items-center justify-center rounded text-xs font-bold"
        :class="[
          orgForId(item.id) && isDefaultOrg(orgForId(item.id)!)
            ? 'bg-gray-200 dark:bg-gray-700'
            : item.isCurrent
              ? 'bg-gray-600 text-white dark:bg-brand-500'
              : 'bg-gray-300 text-gray-700 dark:bg-gray-600 dark:text-gray-200',
        ]"
        aria-hidden="true">
        <OIcon
          v-if="orgForId(item.id) && isDefaultOrg(orgForId(item.id)!)"
          collection="heroicons"
          name="building-office"
          class="size-3.5 text-gray-600 dark:text-gray-300" />
        <template v-else-if="orgForId(item.id)">
          {{ getOrganizationInitial(orgForId(item.id)!) }}
        </template>
      </span>
    </template>

    <!-- Paid plan badge -->
    <template #item-badge="{ item }">
      <span
        v-if="orgForId(item.id) && hasPaidPlan(orgForId(item.id)!)"
        class="ml-1.5 inline-flex items-center rounded bg-brand-100 px-1.5 py-0.5 text-[10px] font-semibold tracking-wide text-brand-700 uppercase dark:bg-brand-900/50 dark:text-brand-300">
        {{ t('web.organizations.paid_badge') }}
      </span>
    </template>

    <!-- Manage Organizations link -->
    <template #footer="{ close }">
      <MenuItem v-slot="{ active }" @click="navigateToManageOrganizations(close)">
        <button
          type="button"
          class="mx-2 w-[calc(100%-1rem)] cursor-pointer rounded-md px-2 py-2 text-left transition-colors duration-150 select-none"
          :class="active ? 'bg-gray-100 dark:bg-gray-700' : ''"
          data-testid="org-scope-manage-link">
          <span class="flex items-center gap-2">
            <OIcon
              collection="heroicons"
              name="cog-6-tooth"
              class="size-4 text-gray-500 dark:text-gray-400"
              aria-hidden="true" />
            <span class="text-sm text-gray-700 dark:text-gray-300">
              {{ t('web.organizations.manage_organizations') }}
            </span>
          </span>
        </button>
      </MenuItem>
    </template>
  </ScopeSwitcher>
</template>
