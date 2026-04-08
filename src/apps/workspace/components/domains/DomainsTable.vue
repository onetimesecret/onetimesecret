<!-- src/apps/workspace/components/domains/DomainsTable.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import ToggleWithIcon from '@/shared/components/common/ToggleWithIcon.vue';
  import DomainsTableActionsCell from '@/apps/workspace/components/dashboard/DomainsTableActionsCell.vue';
  import DomainsTableDomainCell from '@/apps/workspace/components/dashboard/DomainsTableDomainCell.vue';
  import { useDomainsManager } from '@/shared/composables/useDomainsManager';
  import type { CustomDomain } from '@/schemas/shapes/v3/custom-domain';
  import { useConfirmDialog } from '@vueuse/core';

  const { isRevealed, reveal, confirm, cancel } = useConfirmDialog();

  const { deleteDomain } = useDomainsManager();

  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useEntitlements } from '@/shared/composables/useEntitlements';
  import { useOrganizationStore } from '@/shared/stores/organizationStore';
  import { useDomainsStore } from '@/shared/stores/domainsStore';
  import { ENTITLEMENTS } from '@/types/organization';
  import { isOrgsSsoEnabled } from '@/utils/features';

  import ConfirmDialog from '@/shared/components/modals/ConfirmDialog.vue';
  import { computed } from 'vue';
  import { storeToRefs } from 'pinia';

const { t } = useI18n();

  // Use domainsStore for updating domain brand (proper Vue data flow)
  const domainsStore = useDomainsStore();

  const props = withDefaults(defineProps<{
    domains: CustomDomain[];
    isLoading: boolean;
    orgid: string;
    /** When true, hides the header section (title, description, add button) */
    compact?: boolean;
  }>(), {
    compact: false,
  });

  const addDomainRoute = computed(() => `/org/${props.orgid}/domains/add`);

  const organizationStore = useOrganizationStore();
  const { organizations } = storeToRefs(organizationStore);
  const organization = computed(() =>
    organizations.value.find((o) => o.extid === props.orgid) ?? null
  );
  const { can } = useEntitlements(organization);
  const canBrand = computed(() => can(ENTITLEMENTS.CUSTOM_BRANDING));
  const canManageSso = computed(() => isOrgsSsoEnabled() && can(ENTITLEMENTS.MANAGE_SSO));
  const canEmailConfig = computed(() => can(ENTITLEMENTS.CUSTOM_MAIL_SENDER));
  const canIncomingSecrets = computed(() => can(ENTITLEMENTS.INCOMING_SECRETS));

  /** Current user is owner or admin — can modify domain settings */
  const canAdmin = computed(() => {
    const role = organization.value?.current_user_role;
    return role === 'owner' || role === 'admin';
  });

  const emit = defineEmits<{
    (e: 'toggle-homepage', domain: CustomDomain): void;
  }>();

  const handleDelete = async (domain: string) => {
    const confirmed = await reveal();
    if (confirmed) {
      await deleteDomain(domain);
    }
  };

  const handleHomepageToggle = async (domain: CustomDomain) => {
    // Use domainsStore.updateDomainBrand to update brand settings.
    // This updates the store's records array, triggering reactive updates
    // without directly mutating the prop-derived domain object.
    const newValue = !domain.brand?.allow_public_homepage;
    await domainsStore.updateDomainBrand(domain.extid, {
      brand: { allow_public_homepage: newValue },
    });

    emit('toggle-homepage', domain);
  };
</script>

<template>
  <div>
    <section
      :class="[
        compact
          ? 'bg-transparent'
          : 'rounded-lg bg-white p-4 shadow-sm dark:bg-gray-900 sm:p-6 lg:p-8'
      ]"
      aria-labelledby="domains-heading">
      <!-- Header Section (hidden in compact mode) -->
      <div
        v-if="!compact"
        class="mb-6 flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
        <div class="min-w-0 md:mr-4">
          <h1
            id="domains-heading"
            class="text-2xl font-bold tracking-tight text-gray-900 dark:text-white">
            {{ t('web.domains.domains') }}
          </h1>
          <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
            {{ t('web.domains.manage_and_configure_your_verified_custom_domains') }}
          </p>
        </div>
        <router-link
          :to="addDomainRoute"
          class="inline-flex shrink-0 whitespace-nowrap items-center justify-center rounded-lg bg-brand-600 px-4 py-2 font-brand text-base font-medium text-white transition-colors duration-200 hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:hover:bg-brand-500 dark:focus:ring-offset-gray-900">
          <OIcon
            name="plus-20-solid"
            collection="heroicons"
            class="mr-2 size-5" />
          {{ t('web.domains.add_domain') }}
        </router-link>
      </div>

      <!-- List domains -->
      <div class="relative rounded-lg border border-gray-200 dark:border-gray-700">
        <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
          <thead class="bg-gray-50 font-brand dark:bg-gray-800">
            <tr>
              <th
                scope="col"
                class="px-6 py-3 text-left text-xs font-medium tracking-wider text-gray-500 dark:text-gray-400">
                <span class="uppercase">{{ t('web.domains.domain') }} &amp; {{ t('web.COMMON.status') }}</span>
              </th>
              <th
                scope="col"
                class="px-6 py-3 text-center text-xs font-medium tracking-wider text-gray-500 dark:text-gray-400">
                <span class="uppercase">{{ t('web.domains.public_homepage') }}</span>
              </th>

              <th
                scope="col"
                class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
                {{ t('web.LABELS.actions') }}
              </th>
            </tr>
          </thead>

          <tbody class="divide-y divide-gray-200 bg-white dark:divide-gray-700 dark:bg-gray-900">
            <tr
              v-for="domain in domains"
              :key="domain.domainid"
              class="transition-colors duration-150 hover:bg-gray-50 dark:hover:bg-gray-800">
              <!-- Domain & Status -->
              <td class="px-6 py-4">
                <DomainsTableDomainCell
                  :domain="domain"
                  :orgid="props.orgid"
                  :can-brand="canBrand"
                  :can-email-config="canEmailConfig" />
              </td>

              <!-- Homepage Access -->
              <td class="px-6 py-4 text-center">
                <div>
                  <!-- domain.brand?.allow_public_homepage -->
                  <ToggleWithIcon
                    :enabled="domain.brand?.allow_public_homepage ?? false"
                    :disabled="isLoading || !canAdmin"
                    @update:enabled="handleHomepageToggle(domain)" />
                </div>
              </td>

              <!-- Actions -->
              <td class="px-6 py-4 text-right">
                <DomainsTableActionsCell
                  :domain="domain"
                  :orgid="props.orgid"
                  :can-admin="canAdmin"
                  :can-brand="canBrand"
                  :can-manage-sso="canManageSso"
                  :can-email-config="canEmailConfig"
                  :can-incoming-secrets="canIncomingSecrets"
                  @delete="handleDelete" />
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <ConfirmDialog
      v-if="isRevealed"
      @confirm="confirm"
      @cancel="cancel"
      :title="t('web.domains.remove_domain')"
      :message="t('web.domains.are_you_sure_you_want_to_remove_this_domain')"
      type="danger" />
  </div>
</template>
