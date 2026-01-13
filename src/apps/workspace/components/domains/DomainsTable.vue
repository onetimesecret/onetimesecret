<!-- src/apps/workspace/components/domains/DomainsTable.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import ToggleWithIcon from '@/shared/components/common/ToggleWithIcon.vue';
  import DomainsTableActionsCell from '@/apps/workspace/components/dashboard/DomainsTableActionsCell.vue';
  import DomainsTableDomainCell from '@/apps/workspace/components/dashboard/DomainsTableDomainCell.vue';
  import { useDomainsManager } from '@/shared/composables/useDomainsManager';
  import type { CustomDomain } from '@/schemas/models/domain';
  import { useConfirmDialog } from '@vueuse/core';

  const { isRevealed, reveal, confirm, cancel } = useConfirmDialog();

  const { deleteDomain } = useDomainsManager();

  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useBranding } from '@/shared/composables/useBranding';

  import ConfirmDialog from '@/shared/components/modals/ConfirmDialog.vue';
  import { computed } from 'vue';

const { t } = useI18n();

  // Call useBranding at setup time (required for Vue composable hooks)
  // Pass domain ID to saveBranding when needed
  const { saveBranding } = useBranding();

  const props = defineProps<{
    domains: CustomDomain[];
    isLoading: boolean;
    orgid: string;
  }>();

  const addDomainRoute = computed(() => `/org/${props.orgid}/domains/add`);

  const emit = defineEmits<{
    (e: 'toggle-homepage', domain: CustomDomain): void;
  }>();

  const handleDelete = async (domain: string) => {
    console.log('Deleting domain', domain);
    const confirmed = await reveal();
    if (confirmed) {
      await deleteDomain(domain);
    }
  };

  const handleHomepageToggle = async (domain: CustomDomain) => {
    await saveBranding(
      { allow_public_homepage: !domain.brand?.allow_public_homepage },
      domain.extid
    );

    emit('toggle-homepage', domain);

    // Update local domain state after successful API call
    domain.brand = {
      ...domain.brand,
      allow_public_homepage: !domain.brand?.allow_public_homepage,
    };
  };
</script>

<template>
  <div>
    <section
      class="rounded-lg bg-white p-4 shadow-sm dark:bg-gray-900 sm:p-6 lg:p-8"
      aria-labelledby="domains-heading">
      <!-- Header Section -->
      <div class="mb-6 flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div>
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
          class="inline-flex min-w-max items-center justify-center rounded-lg bg-brand-600 px-4 py-2 font-brand text-base font-medium text-white transition-colors duration-200 hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:hover:bg-brand-500 dark:focus:ring-offset-gray-900">
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
                <div class="flex items-center justify-center">
                  <span class="uppercase">{{ t('web.domains.homepage_access') }}</span>
                  <div class="group relative ml-2">
                    <OIcon
                      collection="heroicons"
                      name="question-mark-circle"
                      class="size-4 text-gray-400 transition-colors duration-200 hover:text-gray-500 dark:text-gray-400 dark:hover:text-gray-300" />
                    <div
                      class="invisible absolute z-10 -ml-24 mt-2 w-48 rounded-md bg-white p-2 text-xs text-gray-900 shadow-lg ring-1 ring-black/5 transition-opacity duration-200 group-hover:visible dark:bg-gray-800 dark:text-gray-100 dark:shadow-gray-900/50 dark:ring-white/10">
                      {{ t('web.domains.control_whether_users_can_create_secret_links') }}
                    </div>
                  </div>
                </div>
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
              :key="domain.identifier"
              class="transition-colors duration-150 hover:bg-gray-50 dark:hover:bg-gray-800">
              <!-- Domain & Status -->
              <td class="px-6 py-4">
                <DomainsTableDomainCell :domain="domain" :orgid="props.orgid" />
              </td>

              <!-- Homepage Access -->
              <td class="px-6 py-4 text-center">
                <div>
                  <!-- domain.brand?.allow_public_homepage -->
                  <ToggleWithIcon
                    :enabled="domain.brand?.allow_public_homepage ?? false"
                    :disabled="isLoading"
                    @update:enabled="handleHomepageToggle(domain)" />
                </div>
              </td>

              <!-- Actions -->
              <td class="px-6 py-4 text-right">
                <DomainsTableActionsCell
                  :domain="domain"
                  :orgid="props.orgid"
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
