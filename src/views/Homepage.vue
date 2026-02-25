<!-- src/views/Homepage.vue -->

<script setup lang="ts">
  import HomepageTaglines from '@/components/HomepageTaglines.vue';
  import SecretLinkCopyFirstModal from '@/components/modals/SecretLinkCopyFirstModal.vue';
  import SecretForm from '@/components/secrets/form/SecretForm.vue';
  import RecentSecretsTable from '@/components/secrets/RecentSecretsTable.vue';
  import { useSecretLinkPopup } from '@/composables/useSecretLinkPopup';
  import { WindowService } from '@/services/window.service';
  import { getPopupMode } from '@/utils/popupMode';

  const windowProps = WindowService.getMultiple([
    'authenticated',
    'authentication',
    'plans_enabled',
    'ui',
  ]);

  const popupMode = getPopupMode();
  const usePopupWorkflow = popupMode !== 'none';

  const {
    showModal,
    modalData,
    handleSecretCreated,
    handleCloseModal,
  } = useSecretLinkPopup();

</script>

<template>
  <div class="container mx-auto min-w-[320px] max-w-2xl py-4">
    <HomepageTaglines
      v-if="!windowProps.authenticated"
      class="mb-6" />

    <SecretForm
      v-if="windowProps.ui?.enabled !== false"
      class="mb-12"
      :with-recipient="false"
      :with-asterisk="true"
      :with-generate="false"
      :create-link-label="$t('web.LABELS.create-link-next')"
      :on-secret-created="usePopupWorkflow ? handleSecretCreated : undefined" />

    <SecretLinkCopyFirstModal
      v-if="usePopupWorkflow && modalData"
      :show="showModal"
      :share-url="modalData.shareUrl"
      :natural-expiration="modalData.naturalExpiration"
      :has-passphrase="modalData.hasPassphrase"
      :metadata-key="modalData.metadataKey"
      :secret-shortkey="modalData.secretShortkey"
      @close="handleCloseModal" />

    <!-- Space divider -->
    <div class="mb-6 "></div>

    <RecentSecretsTable
      v-if="false" />
  </div>
</template>
