<!-- src/apps/admin/components/AdminCheckoutLinkModal.vue -->

<script setup lang="ts">
  import { AdminModal } from '@/apps/admin/components/kit';
  import { useAdminMutation } from '@/apps/admin/composables/useAdminMutation';
  import type {
    ColonelCheckoutLinkDetails,
    ColonelCheckoutLinkRecord,
  } from '@/schemas/api/internal/responses/colonel';
  import { colonelCheckoutLinkResponseSchema } from '@/schemas/api/internal/responses/colonel';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import CopyButton from '@/shared/components/ui/CopyButton.vue';
  import { useApi } from '@/shared/composables/useApi';
  import { formatDisplayDateTime } from '@/utils/format';
  import { computed, ref, watch } from 'vue';
  import { useI18n } from 'vue-i18n';

  /**
   * "Create checkout link" form modal for the colonel customer detail page.
   *
   * A support colonel builds a Stripe Checkout session on the customer's
   * behalf (plan + billing cycle + promo toggle), then hands the
   * resulting URL to the customer. The plain AdminConfirmDialog can't carry
   * form inputs, so this uses {@link AdminModal} with its own submit action.
   *
   * Two phases inside one modal:
   *  1. FORM — plan select (catalog from /api/colonel/available-plans, passed
   *     in by the parent), monthly/yearly radio, promotion-code
   *     checkbox, submit.
   *  2. RESULT — the checkout URL with copy-to-clipboard and its expiry
   *     ("expires in ~24h", computed from the ack's `expires_at`).
   *
   * The POST response is parsed STRICTLY against
   * {@link colonelCheckoutLinkResponseSchema}: unlike the fire-and-forget
   * mutation acks elsewhere on the page, the record here IS the deliverable —
   * a 2xx we cannot read means we have nothing to hand the operator, so it is
   * surfaced as an error rather than gracefully ignored.
   *
   * State resets every time the modal opens, so a stale URL from a previous
   * customer/plan can never be copied by mistake.
   */
  const props = defineProps<{
    /** Whether the modal is shown (use with `v-model:open`). */
    open: boolean;
    /** POST endpoint (…/users/:user_id/checkout-link), built by the parent. */
    endpoint: string;
    /** Customer identifier rendered in the header (public id / email). */
    subject: string;
    /** Selectable plans (from the available-plans catalog; may be empty). */
    plans: readonly { planid: string; label: string }[];
    /** Initial plan selection (e.g. the customer's current planid). */
    defaultPlan?: string | null;
  }>();

  const emit = defineEmits<{
    'update:open': [value: boolean];
  }>();

  const { t } = useI18n();
  const $api = useApi();

  // ---- Form state -----------------------------------------------------------

  type BillingCycle = 'monthly' | 'yearly';

  const plan = ref('');
  const billingCycle = ref<BillingCycle>('monthly');
  const allowPromotionCodes = ref(false);

  /** Catalog empty → degrade to a free-text plan-family-id input. */
  const hasCatalog = computed(() => props.plans.length > 0);

  const result = ref<{
    record: ColonelCheckoutLinkRecord;
    details: ColonelCheckoutLinkDetails;
  } | null>(null);

  function initialPlan(): string {
    const preferred = props.defaultPlan ?? '';
    if (preferred && (!hasCatalog.value || props.plans.some((p) => p.planid === preferred))) {
      return preferred;
    }
    return props.plans[0]?.planid ?? '';
  }

  // ---- Submit ---------------------------------------------------------------

  const { loading, error, run, reset } = useAdminMutation(async () => {
    const response = await $api.post(props.endpoint, {
      plan: plan.value.trim(),
      billing_cycle: billingCycle.value,
      allow_promotion_codes: allowPromotionCodes.value,
    });
    const parsed = colonelCheckoutLinkResponseSchema.safeParse(response.data);
    // STRICT: the URL is the deliverable; an unreadable 2xx is a failure here.
    // (`details` is optional in the shared envelope; this ack requires it.)
    if (!parsed.success || !parsed.data.details) {
      throw new Error(t('web.admin.customers.actions.checkoutLink.parseError'));
    }
    result.value = { record: parsed.data.record, details: parsed.data.details };
  });

  // Fresh form every open — never carry a previous customer's URL or choices.
  // `immediate` covers a parent that mounts the modal already open; declared
  // after useAdminMutation so the immediate run can call `reset()`.
  watch(
    () => props.open,
    (open) => {
      if (!open) return;
      plan.value = initialPlan();
      billingCycle.value = 'monthly';
      allowPromotionCodes.value = false;
      result.value = null;
      reset();
    },
    { immediate: true }
  );

  const canSubmit = computed(() => plan.value.trim().length > 0 && !loading.value);

  async function onSubmit(): Promise<void> {
    if (!canSubmit.value) return;
    await run(); // Failure message renders in-modal via `error`.
  }

  // ---- Result presentation --------------------------------------------------

  /** Whole hours until the session expires (floored, never negative). */
  const expiresInHours = computed(() => {
    if (!result.value) return 0;
    const seconds = result.value.record.expires_at - Date.now() / 1000;
    return Math.max(0, Math.floor(seconds / 3600));
  });

  const expiresAtDisplay = computed(() =>
    result.value ? formatDisplayDateTime(new Date(result.value.record.expires_at * 1000)) : ''
  );

  function close(): void {
    emit('update:open', false);
  }
</script>

<template>
  <AdminModal
    :open="open"
    :title="t('web.admin.customers.actions.checkoutLink.modalTitle')"
    :subtitle="subject"
    :dismissable="!loading"
    testid="checkout-link-modal"
    @update:open="emit('update:open', $event)">
    <!-- Phase 2: RESULT -->
    <div
      v-if="result"
      class="space-y-4"
      data-testid="checkout-link-result">
      <p class="text-sm text-gray-700 dark:text-gray-300">
        {{ t('web.admin.customers.actions.checkoutLink.resultLead') }}
      </p>
      <div
        class="flex items-start gap-2 rounded-md border border-gray-200 bg-gray-50 px-3 py-2 dark:border-gray-700 dark:bg-gray-800">
        <code
          class="min-w-0 flex-1 font-mono text-xs break-all text-gray-900 dark:text-gray-100"
          data-testid="checkout-link-url"
          >{{ result.record.checkout_url }}</code
        >
        <CopyButton
          :text="result.record.checkout_url"
          :tooltip="t('web.admin.customers.actions.checkoutLink.copy')"
          testid="checkout-link-copy" />
      </div>
      <p
        class="text-xs text-amber-700 dark:text-amber-400"
        data-testid="checkout-link-expiry">
        {{
          t('web.admin.customers.actions.checkoutLink.expiry', {
            hours: expiresInHours,
            date: expiresAtDisplay,
          })
        }}
      </p>
      <dl class="grid grid-cols-2 gap-x-6 gap-y-2 text-xs">
        <div data-testid="checkout-link-plan-id">
          <dt class="font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
            {{ t('web.admin.customers.actions.checkoutLink.planLabel') }}
          </dt>
          <dd class="mt-0.5 font-mono text-gray-900 dark:text-gray-100">
            {{ result.record.plan_id }}
          </dd>
        </div>
        <div data-testid="checkout-link-region">
          <dt class="font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
            {{ t('web.admin.customers.actions.checkoutLink.regionLabel') }}
          </dt>
          <dd class="mt-0.5 font-mono text-gray-900 dark:text-gray-100">
            {{ result.details.region }}
          </dd>
        </div>
      </dl>
    </div>

    <!-- Phase 1: FORM -->
    <form
      v-else
      class="space-y-4"
      data-testid="checkout-link-form"
      @submit.prevent="onSubmit">
      <!-- Plan: catalog select, or a free-text family id when no catalog -->
      <div>
        <label
          for="checkout-link-plan"
          class="block text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
          {{ t('web.admin.customers.actions.checkoutLink.planLabel') }}
        </label>
        <select
          v-if="hasCatalog"
          id="checkout-link-plan"
          v-model="plan"
          data-testid="checkout-link-plan-select"
          class="mt-2 block w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-sm text-gray-700 focus:border-brand-500 focus:ring-1 focus:ring-brand-500 focus:outline-none dark:border-gray-600 dark:bg-gray-800 dark:text-gray-300">
          <option
            v-for="option in plans"
            :key="option.planid"
            :value="option.planid">
            {{ option.label }}
          </option>
        </select>
        <input
          v-else
          id="checkout-link-plan"
          v-model="plan"
          type="text"
          data-testid="checkout-link-plan-input"
          :placeholder="t('web.admin.customers.actions.checkoutLink.planPlaceholder')"
          class="mt-2 block w-full rounded-md border border-gray-300 bg-white px-3 py-2 font-mono text-sm text-gray-700 placeholder:text-gray-400 focus:border-brand-500 focus:ring-1 focus:ring-brand-500 focus:outline-none dark:border-gray-600 dark:bg-gray-800 dark:text-gray-300 dark:placeholder:text-gray-500" />
      </div>

      <!-- Billing cycle -->
      <fieldset>
        <legend
          class="block text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
          {{ t('web.admin.customers.actions.checkoutLink.cycleLabel') }}
        </legend>
        <div class="mt-2 flex gap-6">
          <label class="inline-flex items-center gap-2 text-sm text-gray-700 dark:text-gray-300">
            <input
              v-model="billingCycle"
              type="radio"
              value="monthly"
              data-testid="checkout-link-cycle-monthly"
              class="border-gray-300 text-brand-600 focus:ring-brand-500 dark:border-gray-600" />
            {{ t('web.admin.customers.actions.checkoutLink.cycleMonthly') }}
          </label>
          <label class="inline-flex items-center gap-2 text-sm text-gray-700 dark:text-gray-300">
            <input
              v-model="billingCycle"
              type="radio"
              value="yearly"
              data-testid="checkout-link-cycle-yearly"
              class="border-gray-300 text-brand-600 focus:ring-brand-500 dark:border-gray-600" />
            {{ t('web.admin.customers.actions.checkoutLink.cycleYearly') }}
          </label>
        </div>
      </fieldset>

      <!-- Toggles -->
      <div class="space-y-2">
        <label class="flex items-center gap-2 text-sm text-gray-700 dark:text-gray-300">
          <input
            v-model="allowPromotionCodes"
            type="checkbox"
            data-testid="checkout-link-promo"
            class="rounded border-gray-300 text-brand-600 focus:ring-brand-500 dark:border-gray-600" />
          {{ t('web.admin.customers.actions.checkoutLink.allowPromo') }}
        </label>
      </div>

      <!-- In-modal failure (retry stays available) -->
      <p
        v-if="error"
        class="text-sm text-red-700 dark:text-red-300"
        role="alert"
        data-testid="checkout-link-error">
        {{ error }}
      </p>
    </form>

    <template #footer>
      <div class="flex justify-end gap-3">
        <button
          type="button"
          data-testid="checkout-link-close"
          :disabled="loading"
          class="inline-flex items-center rounded-md border border-gray-300 px-3 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 focus:ring-2 focus:ring-brand-500 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-800"
          @click="close">
          {{
            result
              ? t('web.admin.customers.actions.checkoutLink.done')
              : t('web.LABELS.cancel')
          }}
        </button>
        <button
          v-if="!result"
          type="button"
          data-testid="checkout-link-submit"
          :disabled="!canSubmit"
          class="inline-flex items-center gap-1 rounded-md bg-brand-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-brand-700 focus:ring-2 focus:ring-brand-500 focus:ring-offset-1 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:bg-brand-500 dark:hover:bg-brand-600"
          @click="onSubmit">
          <OIcon
            v-if="loading"
            collection="heroicons"
            name="arrow-path"
            size="4"
            class="animate-spin motion-reduce:animate-none" />
          {{ t('web.admin.customers.actions.checkoutLink.submit') }}
        </button>
      </div>
    </template>
  </AdminModal>
</template>
