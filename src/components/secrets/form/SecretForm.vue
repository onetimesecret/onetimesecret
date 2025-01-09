<!-- src/components/secrets/form/SecretForm.vue -->

<script setup lang="ts">
  import BasicFormAlerts from '@/components/BasicFormAlerts.vue';
  import CustomDomainPreview from './../../CustomDomainPreview.vue';
  import ConcealButton from './ConcealButton.vue';
  import GenerateButton from './GenerateButton.vue';
  import SecretContentInputArea from './SecretContentInputArea.vue';
  import SecretFormPrivacyOptions from './SecretFormPrivacyOptions.vue';
  import { useSecretForm } from '@/composables/useSecretForm';
  import { useDomainDropdown } from '@/composables/useDomainDropdown';
  import { useCsrfStore } from '@/stores/csrfStore';
  import { useProductIdentity } from '@/stores/identityStore';

  const csrfStore = useCsrfStore();
  const productIdentity = useProductIdentity();

  export interface Props {
    enabled?: boolean;
    withRecipient?: boolean;
    withAsterisk?: boolean;
    withGenerate?: boolean;
  }

  const props = withDefaults(defineProps<Props>(), {
    enabled: true,
    withRecipient: false,
    withAsterisk: false,
    withGenerate: false,
  });

  const {
    secretContent,
    isSubmitting,
    error,
    success,
    formKind,
    handleButtonClick,
    submitForm,
  } = useSecretForm();

  const {
    availableDomains,
    selectedDomain,
    domainsEnabled,
    hasInitialContent,
    updateSelectedDomain,
    formFields,
  } = useDomainDropdown();
</script>

<template>
  <div class="min-w-[320px]">
    <BasicFormAlerts
      :success="success"
      :error="error" />

    <form
      id="createSecret"
      method="post"
      autocomplete="off"
      @submit.prevent="submitForm"
      :disabled="!props.enabled">
      <input
        type="hidden"
        name="utf8"
        value="✓" />
      <input
        type="hidden"
        name="shrimp"
        :value="csrfStore.shrimp" />
      <input
        type="hidden"
        name="share_domain"
        :value="selectedDomain" />

      <!--
        Domain selection and persistence logic:
          - getSavedDomain() retrieves the saved domain from localStorage or defaults
            to the first available domain
                - selectedDomain is initialized with getSavedDomain()
                - A watcher saves selectedDomain to localStorage on changes
          - updateSelectedDomain() updates the selectedDomain ref when the child
            component emits an update
          - The template passes initialDomain to SecretContentInputArea and listens
            for update:selectedDomain events
          This setup allows SecretForm to manage domain state and persistence while
          SecretContentInputArea handles the dropdown UI. The selected domain
          persists across sessions and can be overridden when needed.
      -->
      <SecretContentInputArea
        :available-domains="availableDomains"
        :initial-domain="selectedDomain"
        :initial-content="formFields?.secret || ''"
        :with-domain-dropdown="domainsEnabled"
        @update:selected-domain="updateSelectedDomain"
        @update:content="secretContent = $event" />

      <CustomDomainPreview
        v-if="productIdentity.isCanonical"
        :default_domain="selectedDomain"
        data-testid="custom-domain-preview" />

      <SecretFormPrivacyOptions
        :with-recipient="props.withRecipient"
        :with-expiry="true"
        :with-passphrase="true" />

      <div class="mb-4 flex w-full space-x-2">
        <GenerateButton
          v-if="withGenerate"
          :disabled="hasInitialContent || isSubmitting"
          @click="handleButtonClick('generate')" />
        <ConcealButton
          :disabled="!hasInitialContent || isSubmitting"
          :with-asterisk="withAsterisk"
          :primary-color="productIdentity.primaryColor"
          @click="handleButtonClick('share')" />
      </div>
    </form>
  </div>
</template>
