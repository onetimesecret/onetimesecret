<!-- src/apps/workspace/billing/InvoiceList.vue -->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import BasicFormAlerts from '@/shared/components/forms/BasicFormAlerts.vue';
import OIcon from '@/shared/components/icons/OIcon.vue';
import BillingLayout from '@/shared/components/layout/BillingLayout.vue';
import { classifyError } from '@/schemas/errors';
import { BillingService, type StripeInvoice } from '@/services/billing.service';
import type { InvoiceStatus } from '@/types/billing';
import { formatCurrency } from '@/types/billing';
import { computed, onMounted, ref } from 'vue';

const { t } = useI18n();
const route = useRoute();

// Org extid comes from URL (e.g., /billing/:extid/invoices)
const orgExtid = computed(() => route.params.extid as string);

const invoices = ref<StripeInvoice[]>([]);
const isLoading = ref(false);
const error = ref('');

const formatDate = (timestamp: number): string => new Intl.DateTimeFormat(undefined, {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  }).format(new Date(timestamp * 1000));

const getStatusBadgeClass = (status: InvoiceStatus): string => {
  const classes: Record<string, string> = {
    paid: 'bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-400',
    open: 'bg-blue-100 text-blue-800 dark:bg-blue-900/30 dark:text-blue-400',
    pending: 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900/30 dark:text-yellow-400',
    draft: 'bg-gray-100 text-gray-800 dark:bg-gray-900/30 dark:text-gray-400',
    failed: 'bg-red-100 text-red-800 dark:bg-red-900/30 dark:text-red-400',
    uncollectible: 'bg-red-100 text-red-800 dark:bg-red-900/30 dark:text-red-400',
    void: 'bg-gray-100 text-gray-800 dark:bg-gray-900/30 dark:text-gray-400',
  };
  return classes[status] || 'bg-gray-100 text-gray-800 dark:bg-gray-900/30 dark:text-gray-400';
};

const loadInvoices = async (extid: string) => {
  isLoading.value = true;
  error.value = '';
  try {
    const response = await BillingService.listInvoices(extid);
    invoices.value = response.invoices || [];
  } catch (err) {
    const classified = classifyError(err);
    error.value = classified.message || t('web.billing.invoices.load_error');
    console.error('[InvoiceList] Error loading invoices:', err);
  } finally {
    isLoading.value = false;
  }
};

const handleDownload = async (invoice: StripeInvoice) => {
  const url = invoice.invoice_pdf || invoice.hosted_invoice_url;
  if (!url) return;

  try {
    // Open download URL in new window
    window.open(url, '_blank', 'noopener,noreferrer');
  } catch (err) {
    console.error('[InvoiceList] Error downloading invoice:', err);
  }
};

onMounted(async () => {
  if (orgExtid.value) {
    await loadInvoices(orgExtid.value);
  }
});
</script>

<template>
  <BillingLayout>
    <div class="space-y-6">
      <!-- Error Alert -->
      <BasicFormAlerts v-if="error" :error="error" />

      <!-- Loading State -->
      <div v-if="isLoading" class="flex items-center justify-center py-12">
        <div class="text-center">
          <OIcon
            collection="heroicons"
            name="arrow-path"
            class="mx-auto size-8 animate-spin text-gray-400"
            aria-hidden="true" />
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
                  {{ t('web.billing.invoices.invoice_number') }}
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
                  {{ formatDate(invoice.created) }}
                </td>
                <td class="whitespace-nowrap px-6 py-4 font-mono text-sm text-gray-500 dark:text-gray-400">
                  {{ invoice.number || invoice.id }}
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
                    v-if="invoice.invoice_pdf || invoice.hosted_invoice_url"
                    @click="handleDownload(invoice)"
                    class="inline-flex items-center gap-1 text-brand-600 hover:text-brand-900 dark:text-brand-400 dark:hover:text-brand-300">
                    <OIcon
                      collection="heroicons"
                      name="arrow-down-tray"
                      class="size-4"
                      aria-hidden="true" />
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
          aria-hidden="true" />
        <h3 class="mt-2 text-sm font-semibold text-gray-900 dark:text-white">
          {{ t('web.billing.invoices.no_invoices') }}
        </h3>
        <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.billing.invoices.no_invoices_description') }}
        </p>
        <div class="mt-6">
          <router-link
            :to="{ name: 'Billing Plans', params: { extid: orgExtid } }"
            class="inline-flex items-center gap-2 rounded-md bg-brand-600 px-3 py-2 font-brand text-base font-semibold text-white shadow-sm hover:bg-brand-500 dark:bg-brand-500 dark:hover:bg-brand-400">
            <OIcon
              collection="tabler"
              name="square-letter-s"
              class="size-4"
              aria-hidden="true" />
            {{ t('web.billing.invoices.view_plans') }}
          </router-link>
        </div>
      </div>
    </div>
  </BillingLayout>
</template>
