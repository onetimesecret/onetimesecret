<!-- src/apps/colonel/views/ColonelDomains.vue -->

<script setup lang="ts">
  import ColonelListPage from '@/apps/colonel/components/ColonelListPage.vue';
  import ColonelPagination from '@/apps/colonel/components/ColonelPagination.vue';
  import { useColonelInfoStore } from '@/shared/stores/colonelInfoStore';
  import { formatDisplayDateTime } from '@/utils/format';
  import { storeToRefs } from 'pinia';
  import { computed, onMounted } from 'vue';
  import { useI18n } from 'vue-i18n';

  const { t } = useI18n();

  const store = useColonelInfoStore();
  const { customDomains, customDomainsPagination, loading, customDomainsFetchError } = storeToRefs(store);
  const { fetchCustomDomains } = store;

  onMounted(() => fetchCustomDomains(1, 50));

  function handlePageChange(page: number): void {
    fetchCustomDomains(page, customDomainsPagination.value?.per_page ?? 50);
  }

  function handlePerPageChange(newPerPage: number): void {
    fetchCustomDomains(1, newPerPage);
  }

  // Verification state badge colors
  const getStateBadgeClass = (state: string) => {
    switch (state) {
      case 'verified':
        return 'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200';
      case 'pending':
        return 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200';
      case 'resolving':
        return 'bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200';
      default:
        console.warn(`Unknown domain state: ${state}`);
        return 'bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-200';
    }
  };

  const stateLabels = computed(() => ({
    verified: t('web.colonel.customDomains.status.verified'),
    resolving: t('web.colonel.customDomains.status.resolving'),
    pending: t('web.colonel.customDomains.status.pending'),
  }));
</script>

<template>
  <ColonelListPage
    :loading="loading.customDomains"
    :title="t('web.colonel.customDomains.title')"
    :description="t('web.colonel.customDomains.description')"
    :fetch-error="customDomainsFetchError"
    resource="custom domains">
    <template
      v-if="customDomainsPagination"
      #count>
      Showing {{ customDomains.length }} of {{ customDomainsPagination.total_count }} domains
    </template>

    <div
      v-if="customDomains.length === 0"
      class="rounded-lg border border-gray-200 bg-white p-12 text-center dark:border-gray-700 dark:bg-gray-800">
      <p class="text-gray-500 dark:text-gray-400">{{ t('web.colonel.customDomains.empty') }}</p>
    </div>

    <template v-else>
      <div
        data-testid="colonel-domains-table"
        class="grid gap-6 sm:grid-cols-1 lg:grid-cols-2">
        <div
          v-for="domain in customDomains"
          :key="domain.domain_id"
          class="rounded-lg border border-gray-200 bg-white p-6 shadow-sm dark:border-gray-700 dark:bg-gray-800">
          <!-- Header with logo and domain -->
          <div class="mb-4 flex items-start justify-between">
            <div class="flex items-center gap-4">
              <!-- Logo thumbnail -->
              <div
                v-if="domain.has_logo"
                class="size-16 flex-shrink-0 overflow-hidden rounded-lg border border-gray-200 bg-gray-50 dark:border-gray-700 dark:bg-gray-900">
                <img
                  :src="domain.logo_url ?? undefined"
                  :alt="`${domain.display_domain} logo`"
                  class="size-full object-contain"
                  loading="lazy" />
              </div>
              <div
                v-else
                class="flex size-16 flex-shrink-0 items-center justify-center rounded-lg border border-gray-200 bg-gray-100 dark:border-gray-700 dark:bg-gray-700">
                <span class="text-xs text-gray-400">{{ t('web.colonel.customDomains.noLogo') }}</span>
              </div>

              <!-- Domain info -->
              <div>
                <h3 class="text-lg font-semibold text-gray-900 dark:text-white">
                  {{ domain.display_domain }}
                </h3>
                <p
                  v-if="domain.brand.name"
                  class="text-sm text-gray-600 dark:text-gray-400">
                  {{ domain.brand.name }}
                </p>
              </div>
            </div>

            <!-- Verification badge -->
            <span
              :class="[
                'inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium',
                getStateBadgeClass(domain.verification_state),
              ]">
              {{ stateLabels[domain.verification_state as keyof typeof stateLabels] || domain.verification_state }}
            </span>
          </div>

          <!-- Brand details -->
          <div
            v-if="domain.brand.tagline || domain.brand.homepage_url"
            class="mb-4 border-t border-gray-100 pt-4 dark:border-gray-700">
            <p
              v-if="domain.brand.tagline"
              class="text-sm text-gray-600 dark:text-gray-400">
              {{ domain.brand.tagline }}
            </p>
            <a
              v-if="domain.brand.homepage_url"
              :href="domain.brand.homepage_url"
              target="_blank"
              rel="noopener noreferrer"
              class="mt-1 inline-block text-sm text-brand-600 hover:text-brand-700 dark:text-brand-400">
              {{ domain.brand.homepage_url }} ↗
            </a>
          </div>

          <!-- Domain details grid -->
          <div
            class="grid grid-cols-2 gap-4 border-t border-gray-100 pt-4 text-sm dark:border-gray-700">
            <div>
              <span class="text-gray-500 dark:text-gray-400">{{ t('web.colonel.customDomains.labels.organization') }}:</span>
              <p class="font-medium text-gray-900 dark:text-white">{{ domain.org_name }}</p>
            </div>
            <div>
              <span class="text-gray-500 dark:text-gray-400">{{ t('web.colonel.customDomains.labels.externalId') }}:</span>
              <p class="font-mono text-xs text-gray-900 dark:text-white">{{ domain.extid }}</p>
            </div>
            <div>
              <span class="text-gray-500 dark:text-gray-400">{{ t('web.colonel.customDomains.labels.created') }}:</span>
              <p class="text-gray-900 dark:text-white">
                {{ formatDisplayDateTime(domain.created) }}
              </p>
            </div>
            <div>
              <span class="text-gray-500 dark:text-gray-400">{{ t('web.colonel.customDomains.labels.updated') }}:</span>
              <p class="text-gray-900 dark:text-white">
                {{ domain.updated ? formatDisplayDateTime(domain.updated) : '—' }}
              </p>
            </div>
          </div>

          <!-- Status flags -->
          <div class="mt-4 flex flex-wrap gap-2 border-t border-gray-100 pt-4 dark:border-gray-700">
            <span
              v-if="domain.verified"
              class="inline-flex items-center rounded-full bg-green-50 px-2 py-1 text-xs font-medium text-green-700 dark:bg-green-900 dark:text-green-200">
              ✓ {{ t('web.colonel.customDomains.status.verified') }}
            </span>
            <span
              v-if="domain.resolving"
              class="inline-flex items-center rounded-full bg-blue-50 px-2 py-1 text-xs font-medium text-blue-700 dark:bg-blue-900 dark:text-blue-200">
              ✓ {{ t('web.colonel.customDomains.status.resolving') }}
            </span>
            <span
              v-if="domain.ready"
              class="inline-flex items-center rounded-full bg-green-50 px-2 py-1 text-xs font-medium text-green-700 dark:bg-green-900 dark:text-green-200">
              ✓ {{ t('web.colonel.customDomains.status.ready') }}
            </span>
            <span
              v-if="domain.brand.allow_public_homepage"
              class="inline-flex items-center rounded-full bg-purple-50 px-2 py-1 text-xs font-medium text-purple-700 dark:bg-purple-900 dark:text-purple-200">
              {{ t('web.colonel.customDomains.status.publicHomepage') }}
            </span>
            <span
              v-if="domain.brand.allow_public_api"
              class="inline-flex items-center rounded-full bg-purple-50 px-2 py-1 text-xs font-medium text-purple-700 dark:bg-purple-900 dark:text-purple-200">
              {{ t('web.colonel.customDomains.status.publicApi') }}
            </span>
          </div>

          <!-- Icon preview (if available) -->
          <div
            v-if="domain.has_icon"
            class="mt-4 border-t border-gray-100 pt-4 dark:border-gray-700">
            <span class="text-xs text-gray-500 dark:text-gray-400">{{ t('web.colonel.customDomains.labels.favicon') }}:</span>
            <div
              class="mt-2 inline-block size-8 overflow-hidden rounded border border-gray-200 bg-gray-50 dark:border-gray-700 dark:bg-gray-900">
              <img
                :src="domain.icon_url ?? undefined"
                :alt="`${domain.display_domain} favicon`"
                class="size-full object-contain"
                loading="lazy" />
            </div>
          </div>
        </div>
      </div>

      <!-- Pagination -->
      <ColonelPagination
        v-if="customDomainsPagination && customDomainsPagination.total_pages > 1"
        class="mt-6"
        :pagination="customDomainsPagination"
        :loading="loading.customDomains"
        @update:page="handlePageChange"
        @update:per-page="handlePerPageChange" />
    </template>
  </ColonelListPage>
</template>
