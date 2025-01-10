<!-- src/components/secrets/form/SecretForm.vue -->

<script setup lang="ts">
  import BasicFormAlerts from '@/components/BasicFormAlerts.vue';
  import CustomDomainPreview from './../../CustomDomainPreview.vue';
  import ConcealButton from './ConcealButton.vue';
  import GenerateButton from './GenerateButton.vue';
  import SecretContentInputArea from './SecretContentInputArea.vue';
  import SecretFormPrivacyOptions from './SecretFormPrivacyOptions.vue';
  import {
    useSecretConcealer,
    type SecretFormData,
  } from '@/composables/useSecretConcealer';
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

  const { formData, isSubmitting, error, submit } = useSecretConcealer();

  const handleAction = (kind: 'generate' | 'conceal') => {
    formData.value.kind = kind;
    return submit(kind);
  };

  const updateContent = (content: string) => {
    formData.value.secret = content;
  };

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
    <BasicFormAlerts :error="error" />

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
    <form @submit.prevent="handleAction(formData.kind)">
      <SecretContentInputArea
        :content="formData.secret"
        :share-domain="formData.share_domain"
        :available-domains="availableDomains"
        :initial-domain="selectedDomain"
        :initial-content="formFields?.secret || ''"
        :with-domain-dropdown="domainsEnabled"
        @update:selected-domain="updateSelectedDomain"
        @update:content="updateContent" />

      <CustomDomainPreview
        v-if="productIdentity.isCanonical"
        :default_domain="selectedDomain"
        data-testid="custom-domain-preview" />

      <SecretFormPrivacyOptions
        :with-recipient="props.withRecipient"
        :with-expiry="true"
        :with-passphrase="true" />

      <div class="mb-4 flex w-full space-x-2">
        <Suspense v-if="withGenerate">
          <GenerateButton
            v-if="withGenerate"
            :disabled="hasInitialContent || isSubmitting"
            @click="() => submit('generate')" />
        </Suspense>
        <ConcealButton
          :disabled="!hasInitialContent || isSubmitting"
          :with-asterisk="withAsterisk"
          :primary-color="productIdentity.primaryColor"
          @click="() => submit('conceal')" />
      </div>
    </form>
  </div>
</template>
