<!-- src/views/PreviewCreate.vue -->

<script setup lang="ts">
  import SecretForm from '@/components/secrets/form/SecretForm.vue';
  import SecretLinkCopyFirstModal from '@/components/modals/SecretLinkCopyFirstModal.vue';
  import SecretLinkTwoStepModal from '@/components/modals/SecretLinkTwoStepModal.vue';
  import { useSecretLinkPopup } from '@/composables/useSecretLinkPopup';

  const props = withDefaults(defineProps<{
    mode?: 'copy-first' | 'two-step';
  }>(), {
    mode: 'copy-first',
  });

  const {
    showModal,
    modalData,
    handleSecretCreated,
    handleCloseModal,
  } = useSecretLinkPopup();
</script>

<template>
  <div class="preview-create">
    <!-- Preview mode indicator -->
    <div class="mx-auto mb-4 max-w-2xl">
      <div
        class="inline-flex items-center gap-1.5 rounded-full border border-violet-200 bg-violet-50 px-3 py-1
          text-xs font-medium text-violet-600 dark:border-violet-800/50 dark:bg-violet-900/30 dark:text-violet-400">
        Preview mode: {{ props.mode }}
      </div>
    </div>

    <SecretForm
      :with-expiry="true"
      :on-secret-created="handleSecretCreated" />

    <!-- Copy-First modal (Approach A) -->
    <SecretLinkCopyFirstModal
      v-if="props.mode === 'copy-first' && modalData"
      :show="showModal"
      :share-url="modalData.shareUrl"
      :natural-expiration="modalData.naturalExpiration"
      :has-passphrase="modalData.hasPassphrase"
      :metadata-key="modalData.metadataKey"
      :secret-shortkey="modalData.secretShortkey"
      @close="handleCloseModal" />

    <!-- Two-Step modal (Approach C) -->
    <SecretLinkTwoStepModal
      v-if="props.mode === 'two-step' && modalData"
      :show="showModal"
      :share-url="modalData.shareUrl"
      :natural-expiration="modalData.naturalExpiration"
      :has-passphrase="modalData.hasPassphrase"
      :metadata-key="modalData.metadataKey"
      :secret-shortkey="modalData.secretShortkey"
      @close="handleCloseModal" />
  </div>
</template>
