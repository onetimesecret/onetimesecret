<!-- src/apps/admin/components/customers/AdminCustomerOrganizationsSection.vue -->

<script setup lang="ts">
  import { AdminConfirmDialog } from '@/apps/admin/components/kit';
  import { useAdminMutation } from '@/apps/admin/composables/useAdminMutation';
  import { confirmHeaders } from '@/apps/admin/utils/confirmHeader';
  import { reasonBody } from '@/apps/admin/utils/operatorReason';
  import type { ColonelUserDetailOrganization } from '@/schemas/api/internal/responses/colonel';
  import { colonelUserDefaultOrganizationResponseSchema } from '@/schemas/api/internal/responses/colonel';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useApi } from '@/shared/composables/useApi';
  import { useNotificationsStore } from '@/shared/stores/notificationsStore';
  import { gracefulParse } from '@/utils/schemaValidation';
  import { computed, ref } from 'vue';
  import { useI18n } from 'vue-i18n';

  /**
   * The customer's organizations, with THIS customer's default marked and a
   * control to move that default to another organization in the list.
   *
   *   POST /api/colonel/users/:user_id/default-organization
   *   body { organization_id: <org extid>, reason? }
   *
   * TIER 2 server-side: gated on the X-OTS-Confirm account token (the same
   * header the other /users/:user_id verbs send) but not on elevation, so it is
   * a plain mutation behind a simple confirm with an optional reason.
   *
   * Only organizations already in the customer's own list are offered. That
   * matches the server, which refuses any organization the customer is not an
   * active member of; whatever else it refuses (an archived organization, say)
   * comes back as a 4xx whose message renders in the dialog.
   *
   * Success shows a notice and emits `changed`; the parent refetches the user
   * detail GET, so the badge always reflects live state rather than the ack.
   */
  const props = defineProps<{
    /** The customer's public id, the `:user_id` the detail view routes on. */
    userId: string;
    /** `details.organizations`; undefined when that section failed its schema. */
    organizations: ColonelUserDetailOrganization[] | undefined;
    /**
     * The account identifier for X-OTS-Confirm (email, else public id),
     * resolved by the detail view. Blank means the record is not loaded, and
     * the control stays unavailable rather than sending a request the server
     * would refuse.
     */
    confirmToken: string;
  }>();

  const emit = defineEmits<{
    /** The default changed server-side; the parent refetches the record. */
    changed: [];
  }>();

  const { t } = useI18n();
  const $api = useApi();
  const notifications = useNotificationsStore();

  const dialogOpen = ref(false);
  const target = ref<ColonelUserDetailOrganization | null>(null);

  function orgLabel(org: { display_name: string | null; extid: string } | null): string {
    return org?.display_name || org?.extid || '';
  }

  /** The organization currently marked as this customer's default, if any. */
  const currentDefault = computed(
    () => props.organizations?.find((org) => org.is_customer_default) ?? null
  );

  const {
    loading,
    error,
    run: runSetDefault,
    reset,
  } = useAdminMutation(async (reason?: string) => {
    const org = target.value;
    if (!org || !props.confirmToken) throw new Error('No organization selected');

    const response = await $api.post(
      `/api/colonel/users/${encodeURIComponent(props.userId)}/default-organization`,
      { organization_id: org.extid, ...reasonBody(reason) },
      { headers: confirmHeaders(props.confirmToken) }
    );
    // Tripwire only: a 2xx means the default moved, and the badge is redrawn
    // from the refetched record.
    gracefulParse(
      colonelUserDefaultOrganizationResponseSchema,
      response.data,
      'ColonelUserDefaultOrganizationResponse'
    );
  });

  function requestMakeDefault(org: ColonelUserDetailOrganization): void {
    if (org.is_customer_default || !props.confirmToken || loading.value) return;
    target.value = org;
    reset();
    dialogOpen.value = true;
  }

  async function onConfirm(reason?: string): Promise<void> {
    const org = target.value;
    if (!org) return;

    if (!(await runSetDefault(reason))) return; // Failure stays in the dialog.

    dialogOpen.value = false;
    target.value = null;
    notifications.show(
      t('web.admin.customers.defaultOrganization.success', { org: orgLabel(org) }),
      'success'
    );
    emit('changed');
  }

  function onCancel(): void {
    dialogOpen.value = false;
    target.value = null;
    reset();
  }

  const dialogDescription = computed(() => {
    const next = orgLabel(target.value);
    return currentDefault.value
      ? t('web.admin.customers.defaultOrganization.confirmDescription', {
          org: next,
          current: orgLabel(currentDefault.value),
        })
      : t('web.admin.customers.defaultOrganization.confirmDescriptionNoCurrent', { org: next });
  });
</script>

<template>
  <section
    class="rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-800 dark:bg-gray-900"
    data-testid="organizations-section">
    <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-800">
      <h3 class="text-lg font-medium text-gray-900 dark:text-white">
        {{ t('web.admin.customers.detail.sections.organizations') }}
        <span
          v-if="organizations"
          class="ml-1 text-sm font-normal text-gray-500 dark:text-gray-400"
          >({{ organizations.length }})</span
        >
      </h3>
    </div>
    <p
      v-if="!organizations"
      class="px-6 py-8 text-center text-sm text-amber-700 dark:text-amber-400"
      data-testid="section-invalid-organizations">
      {{ t('web.admin.customers.detail.sectionInvalid') }}
    </p>
    <ul
      v-else-if="organizations.length > 0"
      class="divide-y divide-gray-200 dark:divide-gray-800"
      data-testid="organizations-list">
      <li
        v-for="org in organizations"
        :key="org.organization_id"
        :data-testid="`organization-row-${org.extid}`"
        class="flex items-center justify-between px-6 py-3">
        <div class="min-w-0">
          <p class="truncate text-sm font-medium text-gray-900 dark:text-gray-100">
            {{ org.display_name || t('web.admin.customers.detail.none') }}
          </p>
          <p class="truncate font-mono text-xs text-gray-400 dark:text-gray-500">
            {{ org.extid }}
          </p>
        </div>
        <div class="ml-3 flex shrink-0 items-center gap-2">
          <!-- This customer's default, not the owner's auto-created workspace -->
          <span
            v-if="org.is_customer_default"
            data-testid="organization-default-badge"
            class="rounded bg-brand-50 px-2 py-0.5 text-xs font-medium text-brand-700 dark:bg-brand-900/30 dark:text-brand-300">
            {{ t('web.admin.customers.detail.organizations.default') }}
          </span>
          <button
            v-else
            type="button"
            :data-testid="`organization-make-default-${org.extid}`"
            :disabled="!confirmToken || loading"
            :aria-label="
              t('web.admin.customers.defaultOrganization.ariaLabel', { org: orgLabel(org) })
            "
            class="inline-flex items-center gap-1.5 rounded-md border border-gray-300 px-3 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 focus:ring-2 focus:ring-brand-500 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-800"
            @click="requestMakeDefault(org)">
            <OIcon
              collection="heroicons"
              name="check-badge"
              size="4"
              aria-hidden="true" />
            {{ t('web.admin.customers.defaultOrganization.button') }}
          </button>
          <router-link
            :to="{ name: 'AdminOrganizationDetail', params: { id: org.extid } }"
            data-testid="organization-link"
            class="inline-flex items-center gap-1.5 rounded-md border border-gray-300 px-3 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 focus:ring-2 focus:ring-brand-500 focus:outline-none dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-800">
            {{ t('web.admin.customers.detail.organizations.open') }}
            <OIcon
              collection="heroicons"
              name="arrow-right"
              size="4" />
          </router-link>
        </div>
      </li>
    </ul>
    <p
      v-else
      class="px-6 py-8 text-center text-sm text-gray-500 dark:text-gray-400">
      {{ t('web.admin.customers.detail.organizations.empty') }}
    </p>

    <!-- Change default organization (TIER 2: simple confirm + optional reason). -->
    <AdminConfirmDialog
      v-model:open="dialogOpen"
      :title="t('web.admin.customers.defaultOrganization.confirmTitle')"
      :description="dialogDescription"
      :confirm-text="t('web.admin.customers.defaultOrganization.confirm')"
      request-reason
      :loading="loading"
      :error="error"
      @confirm="onConfirm"
      @cancel="onCancel" />
  </section>
</template>
