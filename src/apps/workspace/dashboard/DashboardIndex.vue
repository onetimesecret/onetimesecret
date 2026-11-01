<!-- src/apps/workspace/dashboard/DashboardIndex.vue -->

<script setup lang="ts">
  import RecentSecretsTable from '@/apps/secret/components/RecentSecretsTable.vue';
  import PrivacyOptionsBar from '@/apps/workspace/components/forms/PrivacyOptionsBar.vue';
  import WorkspaceSecretForm from '@/apps/workspace/components/forms/WorkspaceSecretForm.vue';
  import UpgradeBanner from '@/apps/workspace/dashboard/components/UpgradeBanner.vue';
  import { SecretDisplayType } from '@/schemas/contracts/secret';
  import { loggingService } from '@/services/logging.service';
  import MarkdownModeToggle from '@/shared/components/ui/MarkdownModeToggle.vue';
  import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
  import { useProductIdentity } from '@/shared/stores/identityStore';
  import { storeToRefs } from 'pinia';
  import { computed, ref } from 'vue';

  // Resolve the active brand color so the CTA tracks the same source as the
  // logo (identityStore.primaryColor → --color-brand-500). Mirrors
  // HomepageContent.vue: without this the button falls back to
  // WorkspaceSecretForm's neutral-blue default, so a branded install shows a
  // brand-colored logo above a neutral-blue "Create Link" button.
  const identityStore = useProductIdentity();
  const { primaryColor } = storeToRefs(identityStore);

  // Form ref for accessing exposed state
  const secretFormRef = ref<InstanceType<typeof WorkspaceSecretForm> | null>(null);

  // Recent secrets table ref for refreshing after creation
  const recentSecretsTableRef = ref<InstanceType<typeof RecentSecretsTable> | null>(null);

  // Computed values that read from form's exposed state
  const currentTtl = computed(() => secretFormRef.value?.currentTtl ?? 604800);
  const currentPassphrase = computed(() => secretFormRef.value?.currentPassphrase ?? '');
  const isSubmitting = computed(() => secretFormRef.value?.isSubmitting ?? false);
  const isMarkdown = computed(
    () => secretFormRef.value?.currentDisplayType === SecretDisplayType.MARKDOWN
  );

  // Markdown secrets are opt-in per platform (features.markdown); when off,
  // the chip is not offered and the bar has no trailing group. Nor in the
  // form's generate mode, which sends no display_type.
  const { features } = storeToRefs(useBootstrapStore());
  const showMarkdownToggle = computed(
    () =>
      features.value?.markdown === true && (secretFormRef.value?.offersDisplayType ?? true)
  );

  // Handlers for privacy options updates
  const handleTtlUpdate = (value: number) => {
    secretFormRef.value?.updateTtl(value);
  };

  const handlePassphraseUpdate = (value: string) => {
    secretFormRef.value?.updatePassphrase(value);
  };

  const handleMarkdownUpdate = (enabled: boolean) => {
    secretFormRef.value?.updateDisplayType(
      enabled ? SecretDisplayType.MARKDOWN : SecretDisplayType.TEXT
    );
  };

  // Refresh recent secrets table after a secret is created
  const handleSecretCreated = () => {
    const timestamp = Date.now();
    loggingService.debug('[DEBUG:DashboardIndex] handleSecretCreated called', {
      timestamp,
      hasTableRef: !!recentSecretsTableRef.value,
    });
    recentSecretsTableRef.value?.fetch();
    loggingService.debug('[DEBUG:DashboardIndex] fetch() called on table ref', {
      timestamp,
    });
  };
</script>

<template>
  <div class="container mx-auto min-w-[320px] max-w-4xl px-4">
    <!-- Upgrade Banner (shown for free plan users when billing is enabled) -->
    <UpgradeBanner />

    <!--
      Options bar: privacy chips (TTL, passphrase) on the left, the Markdown
      toggle in its own group on the right (when the platform enables it).
      One row of chips for the form.
    -->
    <PrivacyOptionsBar
      :current-ttl="currentTtl"
      :current-passphrase="currentPassphrase"
      :is-submitting="isSubmitting"
      class="mb-4"
      @update:ttl="handleTtlUpdate"
      @update:passphrase="handlePassphraseUpdate">
      <template
        v-if="showMarkdownToggle"
        #trailing>
        <MarkdownModeToggle
          :model-value="isMarkdown"
          :disabled="isSubmitting"
          @update:model-value="handleMarkdownUpdate" />
      </template>
    </PrivacyOptionsBar>

    <WorkspaceSecretForm
      ref="secretFormRef"
      class="mb-10"
      :primary-color="primaryColor"
      @created="handleSecretCreated" />

    <RecentSecretsTable
      ref="recentSecretsTableRef"
      :show-workspace-mode-toggle="true" />
  </div>
</template>
