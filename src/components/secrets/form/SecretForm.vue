
<template>
  <div class="min-w-[320px]">
    <BasicFormAlerts
      :success="success"
      :error="error"
    />

    <form
      id="createSecret"
      method="post"
      autocomplete="off"
      @submit.prevent="submitForm"
      action="/api/v2/secret/conceal"
      class="form-horizontal"
      :disabled="!props.enabled"
    >
      <input
        type="hidden"
        name="utf8"
        value="✓"
      />
      <input
        type="hidden"
        name="shrimp"
        :value="csrfStore.shrimp"
      />
      <input
        type="hidden"
        name="share_domain"
        :value="selectedDomain"
      />

      <!--
          v-model:selectedDomain is equivalent to:
            :selectedDomain="selectedDomain"
            @update:selectedDomain="selectedDomain = $event"
      -->

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
        @update:content="secretContent = $event"
      />

      <CustomDomainPreview
        :default_domain="selectedDomain"
        data-testid="custom-domain-preview"
      />

      <SecretFormPrivacyOptions
        :with-recipient="props.withRecipient"
        :with-expiry="true"
        :with-passphrase="true"
      />

      <div class="mb-4 flex w-full space-x-2">
        <GenerateButton
          :disabled="isGenerateDisabled || isSubmitting"
          @click="handleButtonClick('generate')"
        />
        <ConcealButton
          :disabled="isCreateDisabled || isSubmitting"
          :with-asterisk="withAsterisk"
          @click="handleButtonClick('share')"
        />
      </div>
    </form>
  </div>
</template>

<script setup lang="ts">
import BasicFormAlerts from '@/components/BasicFormAlerts.vue';
import { useFormSubmission } from '@/composables/useFormSubmission';
import { useCsrfStore } from '@/stores/csrfStore';
import { ConcealDataApiResponse } from '@/types/api/responses';
import { computed, ref, watch } from 'vue';
import { useRouter } from 'vue-router';

import CustomDomainPreview from './../../CustomDomainPreview.vue';
import ConcealButton from './ConcealButton.vue';
import GenerateButton from './GenerateButton.vue';
import SecretContentInputArea from './SecretContentInputArea.vue';
//import SecretContentInputArea from './SecretContentInputArea.gearicon.vue';
//import SecretContentInputArea from './SecretContentInputArea.collapsed.vue';
import SecretFormPrivacyOptions from './SecretFormPrivacyOptions.vue';

const csrfStore = useCsrfStore();

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
})

const formFields = window.form_fields;
const domainsEnabled = window.domains_enabled;
const availableDomains = window.custom_domains || [];
const defaultDomain = window.site_host;

const hasInitialContent = computed(() => Boolean(formFields?.secret));

// Add defaultDomain to the list of available domains if it's not already there
if (!availableDomains.includes(defaultDomain)) {
  availableDomains.push(defaultDomain);
}

// Function to get the saved domain or default to the first available domain
const getSavedDomain = () => {
  const savedDomain = localStorage.getItem('selectedDomain');
  return savedDomain && availableDomains.includes(savedDomain)
    ? savedDomain
    : availableDomains[0];
};

// Initialize selectedDomain with the saved domain or default
const selectedDomain = ref(getSavedDomain());

// Watch for changes in selectedDomain and save to localStorage
watch(selectedDomain, (newDomain) => {
  localStorage.setItem('selectedDomain', newDomain);
});

const secretContent = ref('');
const isFormValid = computed(() => {
  return (secretContent.value.length > 0 || hasInitialContent.value);
});

// Function to update the selected domain
const updateSelectedDomain = (domain: string) => {
  selectedDomain.value = domain;
};

const isGenerateDisabled = computed(() => isFormValid.value);
const isCreateDisabled = computed(() => !isFormValid.value);

const router = useRouter();

const formKind = ref('');

const handleButtonClick = (kind: 'generate' | 'share') => {
  formKind.value = kind;
  submitForm();
};

const {
  isSubmitting,
  error,
  success,
  submitForm
} = useFormSubmission({
  url: '/api/v2/secret/conceal',
  successMessage: '',
  onSuccess: (data: ConcealDataApiResponse) => {
    // Use router to redirect to the private metadata page
    router.push({
      name: 'Metadata link',
      params: { metadataKey: data.record.metadata.key },
    })
  },
  onError: (data: unknown) => {
    console.error('Error fetching secret:', data)

    // Let's try to get a new shrimp right away
    csrfStore.checkShrimpValidity();
  },
  getFormData: () => {
    const form = document.getElementById('createSecret') as HTMLFormElement;
    const formData = new FormData(form);
    formData.append('kind', formKind.value);
    return formData;
  }
});

</script>
