<!-- src/views/colonel/ColonelDomains.vue -->

<script setup lang="ts">
  import { useColonelInfoStore } from '@/shared/stores/colonelInfoStore';
  import { storeToRefs } from 'pinia';
  import { computed, onMounted } from 'vue';
  import { useI18n } from 'vue-i18n';

  const { t } = useI18n();

  const store = useColonelInfoStore();
  const { customDomains, customDomainsPagination, isLoading } = storeToRefs(store);
  const { fetchCustomDomains } = store;

  onMounted(() => fetchCustomDomains());

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

  const totalDomains = computed(() => customDomainsPagination.value?.total_count || 0);
</script>

<template>
  <div class="p-6">
    <div
      v-if="isLoading"
      class="text-center">
      {{ t('web.LABELS.loading') }}
    </div>

    <div v-else>
      <div class="mb-6">
        <h1 class="text-2xl font-bold text-gray-900 dark:text-white">Custom Domains</h1>
        <p class="mt-2 text-sm text-gray-600 dark:text-gray-400">
          Manage custom domains and branded experiences ({{ totalDomains }} total)
        </p>
      </div>

      <div
        v-if="customDomains.length === 0"
        class="rounded-lg border border-gray-200 bg-white p-12 text-center dark:border-gray-700 dark:bg-gray-800">
        <p class="text-gray-500 dark:text-gray-400">No custom domains configured</p>
      </div>

      <div
        v-else
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
                  :src="domain.logo_url"
                  :alt="`${domain.display_domain} logo`"
                  class="size-full object-contain"
                  loading="lazy" />
              </div>
              <div
                v-else
                class="flex size-16 flex-shrink-0 items-center justify-center rounded-lg border border-gray-200 bg-gray-100 dark:border-gray-700 dark:bg-gray-700">
                <span class="text-xs text-gray-400">No Logo</span>
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
              {{ domain.verification_state }}
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
          <div class="grid grid-cols-2 gap-4 border-t border-gray-100 pt-4 text-sm dark:border-gray-700">
            <div>
              <span class="text-gray-500 dark:text-gray-400">Organization:</span>
              <p class="font-medium text-gray-900 dark:text-white">{{ domain.org_name }}</p>
            </div>
            <div>
              <span class="text-gray-500 dark:text-gray-400">External ID:</span>
              <p class="font-mono text-xs text-gray-900 dark:text-white">{{ domain.extid }}</p>
            </div>
            <div>
              <span class="text-gray-500 dark:text-gray-400">Created:</span>
              <p class="text-gray-900 dark:text-white">{{ domain.created_human }}</p>
            </div>
            <div>
              <span class="text-gray-500 dark:text-gray-400">Updated:</span>
              <p class="text-gray-900 dark:text-white">{{ domain.updated_human }}</p>
            </div>
          </div>

          <!-- Status flags -->
          <div class="mt-4 flex flex-wrap gap-2 border-t border-gray-100 pt-4 dark:border-gray-700">
            <span
              v-if="domain.verified"
              class="inline-flex items-center rounded-full bg-green-50 px-2 py-1 text-xs font-medium text-green-700 dark:bg-green-900 dark:text-green-200">
              ✓ Verified
            </span>
            <span
              v-if="domain.resolving"
              class="inline-flex items-center rounded-full bg-blue-50 px-2 py-1 text-xs font-medium text-blue-700 dark:bg-blue-900 dark:text-blue-200">
              ✓ Resolving
            </span>
            <span
              v-if="domain.ready"
              class="inline-flex items-center rounded-full bg-green-50 px-2 py-1 text-xs font-medium text-green-700 dark:bg-green-900 dark:text-green-200">
              ✓ Ready
            </span>
            <span
              v-if="domain.brand.allow_public_homepage"
              class="inline-flex items-center rounded-full bg-purple-50 px-2 py-1 text-xs font-medium text-purple-700 dark:bg-purple-900 dark:text-purple-200">
              Public Homepage
            </span>
            <span
              v-if="domain.brand.allow_public_api"
              class="inline-flex items-center rounded-full bg-purple-50 px-2 py-1 text-xs font-medium text-purple-700 dark:bg-purple-900 dark:text-purple-200">
              Public API
            </span>
          </div>

          <!-- Icon preview (if available) -->
          <div
            v-if="domain.has_icon"
            class="mt-4 border-t border-gray-100 pt-4 dark:border-gray-700">
            <span class="text-xs text-gray-500 dark:text-gray-400">Favicon:</span>
            <div class="mt-2 inline-block size-8 overflow-hidden rounded border border-gray-200 bg-gray-50 dark:border-gray-700 dark:bg-gray-900">
              <img
                :src="domain.icon_url"
                :alt="`${domain.display_domain} favicon`"
                class="size-full object-contain"
                loading="lazy" />
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
