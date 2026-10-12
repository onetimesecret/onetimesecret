<!-- src/apps/workspace/domains/DomainDetail.vue -->

<script setup lang="ts">
/**
 * Domain Detail Hub Page
 *
 * Navigation hub showing all available configuration sections for a domain.
 * Each section is displayed as a card linking to its dedicated page.
 * Entitlement-gated sections show a lock icon and upgrade link.
 */
import { useI18n } from 'vue-i18n';
import { useConfirmDialog } from '@vueuse/core';
import OIcon from '@/shared/components/icons/OIcon.vue';
import ConfirmDialog from '@/shared/components/modals/ConfirmDialog.vue';
import DomainHeader from '@/apps/workspace/components/dashboard/DomainHeader.vue';
import DomainHomepageNetworkAccess, {
  type HomepageNetworkRules,
} from '@/apps/workspace/components/domains/DomainHomepageNetworkAccess.vue';
import DomainHomepageSelector, {
  type HomepageChoice,
} from '@/apps/workspace/components/domains/DomainHomepageSelector.vue';
import { useDomain } from '@/shared/composables/useDomain';
import { useDomainsManager } from '@/shared/composables/useDomainsManager';
import { useEntitlements } from '@/shared/composables/useEntitlements';
import { useNotificationsStore } from '@/shared/stores/notificationsStore';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import { ENTITLEMENTS } from '@/types/organization';
import {
  isDomainOwnershipChecked,
  isOrgsCustomMailEnabled,
  isOrgsIncomingSecretsEnabled,
} from '@/utils/features';
import { storeToRefs } from 'pinia';
import { computed, onMounted, ref } from 'vue';
import { onBeforeRouteLeave, useRouter } from 'vue-router';

const { t } = useI18n();
const router = useRouter();

const props = defineProps<{ extid: string; orgid: string }>();

const { isRevealed, reveal, confirm, cancel } = useConfirmDialog();
const { deleteDomain, updateHomepageConfig } = useDomainsManager();
const notifications = useNotificationsStore();

const handleBack = () => {
  router.push(`/org/${props.orgid}/domains`);
};

const handleRemoveDomain = async () => {
  const { isCanceled } = await reveal();
  if (!isCanceled) {
    await deleteDomain(props.extid);
    router.push(`/org/${props.orgid}/domains`);
  }
};

const {
  domain: customDomainRecord,
  isLoading: domainLoading,
  initialize: initializeDomain,
} = useDomain(props.extid);

const organizationStore = useOrganizationStore();
const { organizations } = storeToRefs(organizationStore);
const organization = computed(() =>
  organizations.value.find((o) => o.extid === props.orgid) ?? null
);
const { can } = useEntitlements(organization);

const canBrand = computed(() => can(ENTITLEMENTS.CUSTOM_BRANDING));
const canEmailConfig = computed(() => can(ENTITLEMENTS.CUSTOM_MAIL_SENDER));
const canIncomingSecrets = computed(() => can(ENTITLEMENTS.INCOMING_SECRETS));
const canCustomSignin = computed(() => can(ENTITLEMENTS.CUSTOM_SIGNIN_CONFIG));
const canHomepageNetwork = computed(() => can(ENTITLEMENTS.HOMEPAGE_NETWORK_RULES));
const canCustomSignup = computed(() => can(ENTITLEMENTS.CUSTOM_SIGNUP_VALIDATION));

/** Current user is owner or admin — can modify domain settings */
const canAdmin = computed(() => {
  const role = organization.value?.current_user_role;
  return role === 'owner' || role === 'admin';
});

// Removing a domain is owner-only — admins manage configuration but not lifecycle.
const isOwner = computed(() => organization.value?.current_user_role === 'owner');

// ---------------------------------------------------------------------------
// Homepage experience (private landing / create form / incoming form)
//
// One three-way choice for the operator; stored backend-side as
// enabled + secrets_mode with merge semantics.
// ---------------------------------------------------------------------------

const homepageExpanded = ref(false);
const homepageSaving = ref(false);

const homepageChoice = computed<HomepageChoice>(() => {
  const config = customDomainRecord.value?.homepage_config;
  if (!config?.enabled) return 'private';
  return config.secrets_mode === 'incoming' ? 'incoming' : 'create';
});

/** Incoming option offered at all: deployment flag + plan entitlement. */
const homepageIncomingAvailable = computed(
  () => isOrgsIncomingSecretsEnabled() && canIncomingSecrets.value
);

/** Incoming selectable: server-computed readiness (enabled + >= 1 recipient). */
const homepageIncomingReady = computed(
  () => customDomainRecord.value?.incoming_ready ?? false
);

// Stored choice can drift from what visitors actually see: 'incoming' stays
// selected (preserving the operator's intent) even after recipients are
// removed elsewhere, but the backend fails closed to the private trust card
// at that point (HomepageConfig#effectively_enabled?). Reflect that here so
// the status line never claims the homepage is interactive when it isn't.
const homepageStatusKey = computed(() => {
  switch (homepageChoice.value) {
    case 'create':
      return 'web.domains.homepage.status_create';
    case 'incoming':
      return homepageIncomingReady.value
        ? 'web.domains.homepage.status_incoming'
        : 'web.domains.homepage.status_incoming_unready';
    default:
      return 'web.domains.homepage.status_private';
  }
});

const incomingConfigRoute = computed(() => ({
  name: 'DomainIncoming',
  params: { orgid: props.orgid, extid: props.extid },
}));

const handleHomepageSelect = async (choice: HomepageChoice) => {
  const domain = customDomainRecord.value;
  if (!domain || homepageSaving.value) return;

  // 'private' sends enabled only — merge semantics preserve the stored
  // secrets_mode, so re-enabling later restores the operator's selection.
  const update =
    choice === 'private'
      ? { enabled: false }
      : { enabled: true, secrets_mode: choice };

  homepageSaving.value = true;
  try {
    const result = await updateHomepageConfig(
      domain.extid,
      update,
      organization.value?.current_user_role,
    );
    if (result) {
      // Gate the success toast on the refetch actually landing. The selector
      // reads its value from the refreshed domain record, so if the refetch
      // fails (initializeDomain surfaces its own error) a "saved" toast would
      // both contradict that error and sit above a selector still showing the
      // pre-change value.
      const refreshed = await initializeDomain();
      if (refreshed) {
        notifications.show(t('web.domains.homepage.update_success'), 'success', 'top');
      }
    }
  } finally {
    homepageSaving.value = false;
  }
};

// ---------------------------------------------------------------------------
// Homepage network rules (allowed / denied CIDR ranges)
//
// Stored on the same HomepageConfig record with merge semantics; the editor
// stages entries and writes both lists explicitly. `enabled` is required by
// the PUT, so the current stored choice is re-sent unchanged alongside.
// ---------------------------------------------------------------------------

const homepageAllowedCidrs = computed<string[]>(
  () => customDomainRecord.value?.homepage_config?.allowed_cidrs ?? []
);
const homepageDeniedCidrs = computed<string[]>(
  () => customDomainRecord.value?.homepage_config?.denied_cidrs ?? []
);
const homepageNetworkRestricted = computed(
  () => homepageAllowedCidrs.value.length > 0 || homepageDeniedCidrs.value.length > 0
);
const homepageNetworkSaving = ref(false);
/** The network editor holds staged, unsaved list edits. */
const homepageNetworkDirty = ref(false);

// The network editor is the one explicit-save form on this hub; guard its
// staged edits the way the dedicated domain config pages guard theirs.
onBeforeRouteLeave((_to, _from, next) => {
  if (homepageNetworkDirty.value) {
    const answer = window.confirm(t('web.domains.unsaved_changes_confirmation'));
    if (answer) next();
    else next(false);
  } else {
    next();
  }
});

const handleHomepageNetworkSave = async (rules: HomepageNetworkRules) => {
  const domain = customDomainRecord.value;
  if (!domain || homepageNetworkSaving.value || homepageSaving.value) return;

  homepageNetworkSaving.value = true;
  try {
    const result = await updateHomepageConfig(
      domain.extid,
      { enabled: domain.homepage_config?.enabled ?? false, ...rules },
      organization.value?.current_user_role,
    );
    if (result) {
      // Same refetch gate as the experience selector: the editor re-seeds
      // from the refreshed record (normalized entries), so only confirm
      // once that record has landed. homepageNetworkSaving stays set until
      // then; the editor relies on it to tell this refresh from an
      // unrelated one that must keep its staged edits.
      const refreshed = await initializeDomain();
      if (refreshed) {
        notifications.show(t('web.domains.homepage.network_update_success'), 'success', 'top');
      }
    }
  } finally {
    homepageNetworkSaving.value = false;
  }
};

interface Section {
  key: string;
  route: { name: string; params: { orgid: string; extid: string } } | null;
  icon: { collection: string; name: string };
  titleKey: string;
  descriptionKey: string;
  available: boolean;
  locked: boolean;
  /** When true, the row expands in place (homepage selector) instead of navigating */
  expandable: boolean;
}

// eslint-disable-next-line max-lines-per-function
const sections = computed<Section[]>(() => [
  {
    // DNS setup is only surfaced on installs that do not check ownership.
    // The others reach DNS/verification via the header status badge instead
    // (the DomainDns route redirects to DomainVerify there).
    key: 'dns',
    route: { name: 'DomainDns', params: { orgid: props.orgid, extid: props.extid } },
    icon: { collection: 'heroicons', name: 'globe-alt' },
    titleKey: 'web.domains.detail.dns_title',
    descriptionKey: 'web.domains.detail.dns_description',
    available: !isDomainOwnershipChecked(),
    locked: false,
    expandable: false,
  },
  {
    key: 'brand',
    route: { name: 'DomainBrand', params: { orgid: props.orgid, extid: props.extid } },
    icon: { collection: 'heroicons', name: 'paint-brush' },
    titleKey: 'web.domains.manage_brand',
    descriptionKey: 'web.domains.detail.brand_description',
    available: true,
    locked: !canBrand.value,
    expandable: false,
  },
  {
    key: 'homepage',
    route: null,
    icon: { collection: 'heroicons', name: 'home' },
    titleKey: 'web.domains.homepage.title',
    descriptionKey: 'web.domains.homepage.description',
    available: true,
    locked: false,
    expandable: true,
  },
  {
    key: 'incoming',
    route: { name: 'DomainIncoming', params: { orgid: props.orgid, extid: props.extid } },
    icon: { collection: 'heroicons', name: 'inbox-arrow-down' },
    titleKey: 'web.domains.incoming.configure_incoming',
    descriptionKey: 'web.domains.detail.incoming_description',
    available: isOrgsIncomingSecretsEnabled(),
    locked: !canIncomingSecrets.value,
    expandable: false,
  },
  {
    key: 'email',
    route: { name: 'DomainEmail', params: { orgid: props.orgid, extid: props.extid } },
    icon: { collection: 'heroicons', name: 'envelope' },
    titleKey: 'web.domains.email.configure_email',
    descriptionKey: 'web.domains.detail.email_description',
    available: isOrgsCustomMailEnabled(),
    locked: !canEmailConfig.value,
    expandable: false,
  },
  {
    key: 'signin',
    route: { name: 'DomainSignin', params: { orgid: props.orgid, extid: props.extid } },
    icon: { collection: 'heroicons', name: 'arrow-right-on-rectangle' },
    titleKey: 'web.domains.signin.configure_signin',
    descriptionKey: 'web.domains.detail.signin_description',
    available: true,
    locked: !canCustomSignin.value,
    expandable: false,
  },
  {
    key: 'signup',
    route: { name: 'DomainSignup', params: { orgid: props.orgid, extid: props.extid } },
    icon: { collection: 'heroicons', name: 'user-plus' },
    titleKey: 'web.domains.signup.configure_signup',
    descriptionKey: 'web.domains.detail.signup_description',
    available: false,
    locked: !canCustomSignup.value,
    expandable: false,
  },
]);

// Unlocked sections first, locked (greyed-out, upgrade-gated) last.
// Array#sort is stable, so original order is preserved within each group.
const visibleSections = computed(() =>
  sections.value
    .filter((s) => s.available)
    .sort((a, b) => Number(a.locked) - Number(b.locked))
);

onMounted(() => {
  initializeDomain();
});
</script>

<template>
  <div class="min-h-screen bg-gray-50 dark:bg-gray-900">
    <!-- Header Section. Back folded into the header row (opt-in affordance),
         so there's no separate Back row above it. The only explicit save on
         this hub is the homepage network editor. -->
    <div class="sticky top-0 z-30">
      <DomainHeader
        :domain="customDomainRecord"
        :has-unsaved-changes="homepageNetworkDirty"
        :orgid="props.orgid"
        external-path="/"
        back-visible
        @back="handleBack" />
    </div>

    <!-- Features list -->
    <div class="mx-auto max-w-4xl px-4 py-8 sm:px-6 lg:px-8">
      <h2 class="mb-6 text-lg font-semibold text-gray-900 dark:text-white">
        {{ t('web.domains.detail.features') }}
      </h2>

      <div class="divide-y divide-gray-200 rounded-lg border border-gray-200 bg-white dark:divide-gray-700 dark:border-gray-700 dark:bg-gray-800">
        <template
          v-for="section in visibleSections"
          :key="section.key">
          <!-- Expandable: homepage experience selector opens in place -->
          <div v-if="section.expandable && !section.locked">
            <button
              type="button"
              class="flex w-full items-center justify-between gap-4 px-5 py-4 text-left transition-colors hover:bg-gray-50 focus:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-brand-500 dark:hover:bg-gray-700/50"
              :aria-expanded="homepageExpanded"
              data-testid="homepage-section-toggle"
              @click="homepageExpanded = !homepageExpanded">
              <div class="flex min-w-0 items-center gap-4">
                <div class="flex size-10 shrink-0 items-center justify-center rounded-lg bg-brand-50 dark:bg-brand-900/20">
                  <OIcon
                    :collection="section.icon.collection"
                    :name="section.icon.name"
                    class="size-5 text-brand-600 dark:text-brand-400"
                    aria-hidden="true" />
                </div>
                <div class="min-w-0">
                  <h3 class="font-brand text-sm font-semibold text-gray-900 dark:text-white">
                    {{ t(section.titleKey) }}
                  </h3>
                  <p class="mt-0.5 text-xs text-gray-500 dark:text-gray-400">
                    {{ t(section.descriptionKey) }}
                  </p>
                </div>
              </div>
              <div class="flex shrink-0 items-center gap-3">
                <!-- Live status of the current homepage experience -->
                <span
                  class="hidden text-xs text-gray-500 dark:text-gray-400 sm:inline"
                  data-testid="homepage-status">
                  {{ t(homepageStatusKey) }}
                </span>
                <!-- Network rules narrow who gets that experience -->
                <span
                  v-if="homepageNetworkRestricted"
                  class="hidden items-center gap-1 rounded-full bg-amber-50 px-2 py-0.5 text-xs font-medium text-amber-700 sm:inline-flex dark:bg-amber-900/20 dark:text-amber-300"
                  data-testid="homepage-network-badge">
                  <OIcon
                    collection="heroicons"
                    name="globe-alt"
                    class="size-3"
                    aria-hidden="true" />
                  {{ t('web.domains.homepage.status_network_restricted') }}
                </span>
                <OIcon
                  collection="heroicons"
                  name="chevron-down"
                  :class="[
                    'size-5 text-gray-400 transition-transform dark:text-gray-500',
                    homepageExpanded ? 'rotate-180' : '',
                  ]"
                  aria-hidden="true" />
              </div>
            </button>

            <!-- v-show, not v-if: collapsing must not discard the network
                 editor's staged edits. -->
            <div
              v-show="homepageExpanded"
              class="border-t border-gray-100 px-5 py-4 dark:border-gray-700/50">
              <DomainHomepageSelector
                :model-value="homepageChoice"
                :disabled="domainLoading || homepageSaving || homepageNetworkSaving || !canAdmin"
                :incoming-available="homepageIncomingAvailable"
                :incoming-ready="homepageIncomingReady"
                :incoming-config-route="incomingConfigRoute"
                @update:model-value="handleHomepageSelect" />

              <!-- Network rules apply to whichever interactive experience is selected -->
              <DomainHomepageNetworkAccess
                class="mt-5 border-t border-gray-100 pt-4 dark:border-gray-700/50"
                :allowed-cidrs="homepageAllowedCidrs"
                :denied-cidrs="homepageDeniedCidrs"
                :disabled="domainLoading || homepageSaving || !canAdmin"
                :saving="homepageNetworkSaving"
                :locked="!canHomepageNetwork"
                @save="handleHomepageNetworkSave"
                @update:dirty="homepageNetworkDirty = $event">
                <template #upgrade>
                  <RouterLink
                    :to="`/billing/${props.orgid}/plans`"
                    class="inline-flex items-center gap-1 font-medium text-amber-600 hover:text-amber-700 dark:text-amber-400 dark:hover:text-amber-300">
                    {{ t('web.billing.overview.view_plans_action') }}
                    <OIcon
                      collection="heroicons"
                      name="arrow-right"
                      class="size-3"
                      aria-hidden="true" />
                  </RouterLink>
                </template>
              </DomainHomepageNetworkAccess>
            </div>
          </div>

          <!-- Unlocked: feature row with navigation -->
          <component
            :is="section.route && !section.locked ? 'RouterLink' : 'div'"
            v-else-if="!section.locked"
            v-bind="section.route ? { to: section.route } : {}"
            :class="[
              'flex items-center justify-between gap-4 px-5 py-4',
              section.route ? 'group transition-colors hover:bg-gray-50 dark:hover:bg-gray-700/50' : '',
            ]">
            <div class="flex min-w-0 items-center gap-4">
              <div class="flex size-10 shrink-0 items-center justify-center rounded-lg bg-brand-50 dark:bg-brand-900/20">
                <OIcon
                  :collection="section.icon.collection"
                  :name="section.icon.name"
                  class="size-5 text-brand-600 dark:text-brand-400"
                  aria-hidden="true" />
              </div>
              <div class="min-w-0">
                <h3 class="font-brand text-sm font-semibold text-gray-900 dark:text-white">
                  {{ t(section.titleKey) }}
                </h3>
                <p class="mt-0.5 text-xs text-gray-500 dark:text-gray-400">
                  {{ t(section.descriptionKey) }}
                </p>
              </div>
            </div>
            <div class="flex shrink-0 items-center">
              <!-- Arrow for navigable features -->
              <OIcon
                collection="heroicons"
                name="chevron-right"
                class="size-5 text-gray-400 transition-colors group-hover:text-brand-500 dark:text-gray-500 dark:group-hover:text-brand-400"
                aria-hidden="true" />
            </div>
          </component>

          <!-- Locked: disabled row with upgrade hint -->
          <div
            v-else
            class="flex items-center justify-between gap-4 bg-gray-50/50 px-5 py-4 dark:bg-gray-800/50">
            <div class="flex min-w-0 items-center gap-4">
              <div class="flex size-10 shrink-0 items-center justify-center rounded-lg bg-gray-100 dark:bg-gray-700">
                <OIcon
                  :collection="section.icon.collection"
                  :name="section.icon.name"
                  class="size-5 text-gray-400 dark:text-gray-500"
                  aria-hidden="true" />
              </div>
              <div class="min-w-0">
                <h3 class="font-brand text-sm font-semibold text-gray-500 dark:text-gray-400">
                  {{ t(section.titleKey) }}
                </h3>
                <p class="mt-0.5 text-xs text-gray-400 dark:text-gray-500">
                  {{ t(section.descriptionKey) }}
                </p>
              </div>
            </div>
            <div class="flex shrink-0 items-center gap-3">
              <RouterLink
                :to="`/billing/${props.orgid}/plans`"
                class="inline-flex items-center gap-1 text-xs font-medium text-amber-600 hover:text-amber-700 dark:text-amber-400 dark:hover:text-amber-300">
                {{ t('web.billing.overview.view_plans_action') }}
                <OIcon
                  collection="heroicons"
                  name="arrow-right"
                  class="size-3"
                  aria-hidden="true" />
              </RouterLink>
              <OIcon
                collection="heroicons"
                name="lock-closed"
                class="size-4 text-gray-300 dark:text-gray-600"
                aria-hidden="true" />
            </div>
          </div>
        </template>
      </div>

      <!-- Careful Consideration Zone (owner-only — domain removal is lifecycle, not config) -->
      <template v-if="isOwner">
        <hr class="my-10 border-gray-200 dark:border-gray-700/50" />
        <div>
        <h2 class="mb-4 text-sm font-medium text-red-600 dark:text-red-400">
          {{ t('web.COMMON.caution_zone') }}
        </h2>
        <div class="rounded-lg border border-red-200 bg-red-50/50 dark:border-red-900/50 dark:bg-red-950/20">
          <div class="flex items-center justify-between gap-4 px-5 py-4">
            <div class="flex min-w-0 items-center gap-4">
              <div class="flex size-10 shrink-0 items-center justify-center rounded-lg bg-red-100 dark:bg-red-900/30">
                <OIcon
                  collection="heroicons"
                  name="trash"
                  class="size-5 text-red-600 dark:text-red-400"
                  aria-hidden="true" />
              </div>
              <div class="min-w-0">
                <h3 class="font-brand text-sm font-semibold text-gray-900 dark:text-white">
                  {{ t('web.domains.remove_domain') }}
                </h3>
                <p class="mt-0.5 text-xs text-gray-500 dark:text-gray-400">
                  {{ t('web.domains.remove_domain_description') }}
                </p>
              </div>
            </div>
            <button
              type="button"
              class="shrink-0 rounded-md border border-red-300 bg-white px-3 py-1.5 text-sm font-medium text-red-600 transition-colors hover:bg-red-50 focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-offset-2 dark:border-red-700 dark:bg-transparent dark:text-red-400 dark:hover:bg-red-950/50 dark:focus:ring-offset-gray-900"
              @click="handleRemoveDomain">
              {{ t('web.COMMON.remove') }}
            </button>
          </div>
        </div>
        </div>
      </template>
    </div>

    <!-- Confirm Dialog -->
    <ConfirmDialog
      v-if="isRevealed"
      :title="t('web.domains.remove_domain')"
      :message="t('web.domains.are_you_sure_you_want_to_remove_this_domain')"
      type="danger"
      @confirm="confirm"
      @cancel="cancel" />
  </div>
</template>
