<!-- src/views/billing/InvoiceList.vue -->

<script setup lang="ts">
import BasicFormAlerts from '@/components/BasicFormAlerts.vue';
import OIcon from '@/components/icons/OIcon.vue';
import BillingLayout from '@/components/layout/BillingLayout.vue';
import { classifyError } from '@/schemas/errors';
import { useOrganizationStore } from '@/stores/organizationStore';
import type { Invoice, InvoiceStatus } from '@/types/billing';
import { formatCurrency } from '@/types/billing';
import { AxiosInstance } from 'axios';
import { computed, inject, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const organizationStore = useOrganizationStore();
const $api = inject('api') as AxiosInstance;

const selectedOrgId = ref<string | null>(null);
const invoices = ref<Invoice[]>([]);
const isLoading = ref(false);
const error = ref('');

const organizations = computed(() => organizationStore.organizations);

const formatDate = (date: Date): string => new Intl.DateTimeFormat('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  }).format(date);

const getStatusBadgeClass = (status: InvoiceStatus): string => {
  const classes = {
    paid: 'bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-400',
    pending: 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900/30 dark:text-yellow-400',
    failed: 'bg-red-100 text-red-800 dark:bg-red-900/30 dark:text-red-400',
  };
  return classes[status];
};

const handleOrgChange = async (orgId: string) => {
  selectedOrgId.value = orgId;
  await loadInvoices(orgId);
};

const loadInvoices = async (orgId: string) => {
  isLoading.value = true;
  error.value = '';
  try {
    const response = await $api.get(`/api/billing/org/${orgId}/invoices`);
    // TODO: Add proper schema validation once backend is implemented
    invoices.value = response.data.invoices || [];
  } catch (err) {
    const classified = classifyError(err);
    error.value = classified.message || t('web.billing.invoices.load_error');
    console.error('[InvoiceList] Error loading invoices:', err);
  } finally {
    isLoading.value = false;
  }
};

const handleDownload = async (invoice: Invoice) => {
  if (!invoice.download_url) return;

  try {
    // Open download URL in new window
    window.open(invoice.download_url, '_blank');
  } catch (err) {
    console.error('[InvoiceList] Error downloading invoice:', err);
  }
};

onMounted(async () => {
  try {
    if (organizations.value.length === 0) {
      await organizationStore.fetchOrganizations();
    }

    if (organizations.value.length > 0) {
      selectedOrgId.value = organizations.value[0].id;
      await loadInvoices(organizations.value[0].id);
    }
  } catch (err) {
    const classified = classifyError(err);
    error.value = classified.message || 'Failed to load organizations';
    console.error('[InvoiceList] Error loading organizations:', err);
  }
});
</script>

<template>
  <BillingLayout>
    <div class="space-y-6">
      <!-- Header -->
      <div>
        <h1 class="text-2xl font-bold text-gray-900 dark:text-white">
          {{ t('web.billing.invoices.title') }}
        </h1>
        <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
          View and download your billing history
        </p>
      </div>

      <!-- Organization Selector -->
      <div v-if="organizations.length > 1" class="rounded-lg border border-gray-200 bg-white p-4 dark:border-gray-700 dark:bg-gray-800">
        <label for="org-select" class="mb-2 block text-sm font-medium text-gray-700 dark:text-gray-300">
          {{ t('web.billing.overview.organization_selector') }}
        </label>
        <select
          id="org-select"
          v-model="selectedOrgId"
          @change="handleOrgChange(selectedOrgId!)"
          class="block w-full rounded-md border-gray-300 shadow-sm focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white sm:text-sm">
          <option
            v-for="org in organizations"
            :key="org.id"
            :value="org.id">
            {{ org.display_name }}
          </option>
        </select>
      </div>

      <!-- Error Alert -->
      <BasicFormAlerts v-if="error" :error="error" />

      <!-- Loading State -->
      <div v-if="isLoading" class="flex items-center justify-center py-12">
        <div class="text-center">
          <OIcon
            collection="heroicons"
            name="arrow-path"
            class="mx-auto size-8 animate-spin text-gray-400"
            aria-hidden="true"
          />
          <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
            {{ t('web.COMMON.loading') }}
          </p>
        </div>
      </div>

      <!-- Invoice Table -->
      <div v-else-if="invoices.length > 0" class="overflow-hidden rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-700 dark:bg-gray-800">
        <div class="overflow-x-auto">
          <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
            <thead class="bg-gray-50 dark:bg-gray-900/50">
              <tr>
                <th
                  scope="col"
                  class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
                  {{ t('web.billing.invoices.invoice_date') }}
                </th>
                <th
                  scope="col"
                  class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
                  Invoice #
                </th>
                <th
                  scope="col"
                  class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
                  {{ t('web.billing.invoices.invoice_amount') }}
                </th>
                <th
                  scope="col"
                  class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
                  {{ t('web.billing.invoices.invoice_status') }}
                </th>
                <th
                  scope="col"
                  class="relative px-6 py-3">
                  <span class="sr-only">{{ t('web.billing.invoices.invoice_download') }}</span>
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-gray-200 bg-white dark:divide-gray-700 dark:bg-gray-800">
              <tr
                v-for="invoice in invoices"
                :key="invoice.id"
                class="hover:bg-gray-50 dark:hover:bg-gray-700/50">
                <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-900 dark:text-white">
                  {{ formatDate(invoice.invoice_date) }}
                </td>
                <td class="whitespace-nowrap px-6 py-4 font-mono text-sm text-gray-500 dark:text-gray-400">
                  {{ invoice.id }}
                </td>
                <td class="whitespace-nowrap px-6 py-4 text-sm font-medium text-gray-900 dark:text-white">
                  {{ formatCurrency(invoice.amount, invoice.currency) }}
                </td>
                <td class="whitespace-nowrap px-6 py-4 text-sm">
                  <span
                    :class="[
                      'inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium',
                      getStatusBadgeClass(invoice.status),
                    ]">
                    {{ t(`web.billing.invoices.${invoice.status}`) }}
                  </span>
                </td>
                <td class="whitespace-nowrap px-6 py-4 text-right text-sm">
                  <button
                    v-if="invoice.download_url"
                    @click="handleDownload(invoice)"
                    class="inline-flex items-center gap-1 text-brand-600 hover:text-brand-900 dark:text-brand-400 dark:hover:text-brand-300">
                    <OIcon
                      collection="heroicons"
                      name="arrow-down-tray"
                      class="size-4"
                      aria-hidden="true"
                    />
                    {{ t('web.billing.invoices.invoice_download') }}
                  </button>
                  <span v-else class="text-gray-400 dark:text-gray-600">
                    -
                  </span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <!-- Empty State -->
      <div v-else class="rounded-lg border border-gray-200 bg-white p-12 text-center dark:border-gray-700 dark:bg-gray-800">
        <OIcon
          collection="heroicons"
          name="document-text"
          class="mx-auto size-12 text-gray-400"
          aria-hidden="true"
        />
        <h3 class="mt-2 text-sm font-semibold text-gray-900 dark:text-white">
          {{ t('web.billing.invoices.no_invoices') }}
        </h3>
        <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
          Your invoices will appear here once you upgrade to a paid plan
        </p>
        <div class="mt-6">
          <router-link
            :to="{ name: 'Billing Plans' }"
            class="inline-flex items-center gap-2 rounded-md bg-brand-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-brand-500 dark:bg-brand-500 dark:hover:bg-brand-400">
            <OIcon
              collection="heroicons"
              name="sparkles"
              class="size-4"
              aria-hidden="true"
            />
            View Plans
          </router-link>
        </div>
      </div>
    </div>
  </BillingLayout>
</template>
