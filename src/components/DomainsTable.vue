<script setup lang="ts">
  import DomainsTableDomainCell from '@/components/dashboard/DomainsTableDomainCell.vue';
  import DomainsTableActionsCell from '@/components/dashboard/DomainsTableActionsCell.vue';
  import ToggleWithIcon from '@/components/common/ToggleWithIcon.vue';
  import type { CustomDomain } from '@/schemas/models/domain';
  import { useConfirmDialog } from '@vueuse/core';

  import { useDomainsManager } from '@/composables/useDomainsManager';

  const { isRevealed, reveal, confirm, cancel } = useConfirmDialog();

  const { deleteDomain } = useDomainsManager();

  import OIcon from '@/components/icons/OIcon.vue';
  import { useBranding } from '@/composables/useBranding';
  import ConfirmDialog from './ConfirmDialog.vue';

  defineProps<{
    domains: CustomDomain[];
    isLoading: boolean;
  }>();

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
    const { saveBranding } = useBranding(domain.display_domain);

    await saveBranding({
      allow_public_homepage: !domain.brand?.allow_public_homepage,
    });

    emit('toggle-homepage', domain);

    // Update local domain state after successful API call
    domain.brand = {
      ...domain.brand,
      allow_public_homepage: !domain.brand?.allow_public_homepage,
    };
  };
</script>

<template>
  <template>
    <section
      class="rounded-lg bg-white p-4 shadow-sm dark:bg-gray-900 sm:p-6 lg:p-8"
      aria-labelledby="domains-heading">
      <!-- Header Section -->
      <div class="mb-6 flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1
            id="domains-heading"
            class="text-2xl font-bold tracking-tight text-gray-900 dark:text-white">
            {{ $t('domains') }}
          </h1>
          <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
            {{ $t('manage-and-configure-your-verified-custom-domains') }}
          </p>
        </div>
        <router-link
          to="/domains/add"
          class="inline-flex items-center justify-center rounded-lg bg-brand-600 px-4 py-2 font-brand text-base font-medium text-white transition-colors duration-200 hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:hover:bg-brand-500 dark:focus:ring-offset-gray-900">
          <OIcon
            name="plus-20-solid"
            collection="heroicons"
            class="mr-2 size-5" />
          {{ $t('add-domain') }}
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
                <span class="uppercase">{{ $t('domain') }} {{ $t('and-status') }}</span>
              </th>

              <th
                scope="col"
                class="px-6 py-3 text-center text-xs font-medium tracking-wider text-gray-500 dark:text-gray-400">
                <div class="flex items-center justify-center">
                  <span class="uppercase">{{ $t('homepage-access') }}</span>
                  <div class="group relative ml-2">
                    <OIcon
                      collection="heroicons"
                      name="question-mark-circle"
                      class="size-4 text-gray-400 transition-colors duration-200 hover:text-gray-500 dark:text-gray-400 dark:hover:text-gray-300" />
                    <div
                      class="invisible absolute z-10 -ml-24 mt-2 w-48 rounded-md bg-white p-2 text-xs text-gray-900 shadow-lg ring-1 ring-black/5 transition-opacity duration-200 group-hover:visible dark:bg-gray-800 dark:text-gray-100 dark:shadow-gray-900/50 dark:ring-white/10">
                      {{
                        $t(
                          'control-whether-users-can-create-secret-links-from-your-domains-homepage'
                        )
                      }}
                    </div>
                  </div>
                </div>
              </th>

              <th
                scope="col"
                class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
                {{ $t('web.LABELS.actions') }}
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
                <DomainsTableDomainCell :domain="domain" />
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
      :title="$t('delete-domain')"
      :message="$t('delete-domain-warning')"
      type="danger" />
  </template>
</template>
