<!-- src/apps/workspace/domains/DomainAdd.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import { computed } from 'vue';
  import { storeToRefs } from 'pinia';
  import { useRoute } from 'vue-router';
  import DomainForm from '@/apps/workspace/components/domains/DomainForm.vue';
  import ErrorDisplay from '@/shared/components/ui/ErrorDisplay.vue';
  import { useDomainsManager } from '@/shared/composables/useDomainsManager';
  import { useOrgPermissions } from '@/shared/composables/useOrgPermissions';
  import { useOrganizationStore } from '@/shared/stores/organizationStore';

  const { t } = useI18n();
  const route = useRoute();

  const {
    isLoading,
    error,
    handleAddDomain,
    goBack,
  } = useDomainsManager();

  // Resolve the org backing this route by its extid (the :orgid URL param),
  // falling back to the active organization when the lookup hasn't loaded.
  const organizationStore = useOrganizationStore();
  const { organizations, currentOrganization } = storeToRefs(organizationStore);

  const routeOrgid = computed(() => (route.params.orgid as string | undefined) ?? null);

  const organization = computed(() => {
    const orgid = routeOrgid.value;
    if (orgid) {
      const matched = organizations.value.find((o) => o.extid === orgid);
      if (matched) return matched;
      if (currentOrganization.value?.extid === orgid) return currentOrganization.value;
    }
    return currentOrganization.value ?? null;
  });

  const { currentRole, canCreateDomain } = useOrgPermissions(organization);

  // Defense-in-depth: route guard already redirects members away. This v-if
  // covers direct refresh / deep-link scenarios where role is known. Unknown
  // role (organization list not yet loaded) falls through to the form so we
  // don't flash an unauthorized message during normal navigation. See #3033.
  const showAccessDenied = computed(
    () => currentRole.value !== null && !canCreateDomain.value
  );
</script>

<template>
  <div class="">
    <h1 class="mb-6 text-3xl font-bold dark:text-white">
      {{ t('web.domains.add_your_domain') }}
    </h1>

    <div
      v-if="showAccessDenied"
      role="alert"
      class="rounded-lg border border-amber-200 bg-amber-50 p-6 dark:border-amber-800 dark:bg-amber-900/20">
      <h2 class="text-lg font-semibold text-amber-900 dark:text-amber-100">
        {{ t('web.domains.add_access_denied') }}
      </h2>
      <p class="mt-2 text-sm text-amber-800 dark:text-amber-200">
        {{ t('web.domains.add_access_denied_description') }}
      </p>
    </div>

    <template v-else>
      <ErrorDisplay v-if="error" :error="error" />

      <DomainForm
        :is-submitting="isLoading"
        @submit="handleAddDomain"
        @back="goBack" />
    </template>
  </div>
</template>
