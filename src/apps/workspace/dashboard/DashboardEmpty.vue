<!-- src/apps/workspace/dashboard/DashboardEmpty.vue -->

<!-- Onboarding dashboard for users with team entitlement but no teams yet -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import SecretForm from '@/apps/secret/components/form/SecretForm.vue';
  import RecentSecretsTable from '@/apps/secret/components/RecentSecretsTable.vue';
  import { WindowService } from '@/services/window.service';
  import { computed } from 'vue';
  import { useRouter } from 'vue-router';

  const { t } = useI18n(); // auto-import
  const router = useRouter();
  const cust = WindowService.get('cust');

  const isBetaEnabled = computed(() => cust?.feature_flags?.beta ?? false);

  const navigateToCreateTeam = () => {
    router.push({ name: 'Teams' });
  };
</script>

<template>
  <div class="container mx-auto min-w-[320px] max-w-2xl">
    <SecretForm
      class="mb-12"
      :with-generate="true"
      :with-recipient="true" />

    <!-- Create Your First Team CTA -->
    <div class="mb-12 rounded-lg border border-dashed border-gray-300 bg-gray-50 p-8 text-center dark:border-gray-600 dark:bg-gray-800/50">
      <div class="mx-auto mb-4 flex size-12 items-center justify-center rounded-full bg-brand-100 dark:bg-brand-900/30">
        <OIcon
          collection="heroicons"
          name="user-group"
          class="size-6 text-brand-600 dark:text-brand-400"
          aria-hidden="true" />
      </div>

      <h2 class="mb-2 text-lg font-semibold text-gray-900 dark:text-white">
        {{ t('web.teams.create_first_team_title') }}
      </h2>

      <p class="mb-6 text-sm text-gray-600 dark:text-gray-400">
        {{ t('web.teams.create_first_team_description') }}
      </p>

      <button
        type="button"
        @click="navigateToCreateTeam"
        class="inline-flex items-center gap-2 rounded-md bg-brand-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-brand-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600 dark:bg-brand-500 dark:hover:bg-brand-400">
        <OIcon
          collection="heroicons"
          name="plus"
          class="size-5"
          aria-hidden="true" />
        {{ t('web.teams.create_team') }}
      </button>
    </div>

    <RecentSecretsTable v-if="isBetaEnabled" />
  </div>
</template>
