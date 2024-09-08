<script setup lang="ts">
import { computed, ref, watch } from 'vue';

import CustomDomainPreview from './CustomDomainPreview.vue';
import SecretContentInputArea from './SecretContentInputArea.vue';
import SecretFormPrivacyOptions from './SecretFormPrivacyOptions.vue';
import GenerateButton from './secrets/GenerateButton.vue';
import CreateButton from './secrets/CreateButton.vue';

export interface Props {
  enabled?: boolean;
  shrimp: string | null;
  withRecipient?: boolean;
  withAsterisk?: boolean;
  withGenerate?: boolean;
}

const props = withDefaults(defineProps<Props>(), {
  enabled: true,
  shrimp: null,
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

</script>

<template>
  <div class="">

    <form id="createSecret"
          method="post"
          autocomplete="off"
          action="/share"
          class="form-horizontal"
          :disabled="!props.enabled">
      <input type="hidden"
             name="utf8"
             value="✓" />
      <input type="hidden"
             name="shrimp"
             :value="shrimp" />
      <input type="hidden"
             name="share_domain"
             :value="selectedDomain" />

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
      <SecretContentInputArea :availableDomains="availableDomains"
                              :initialDomain="selectedDomain"
                              :initialContent="formFields?.secret || ''"
                              :withDomainDropdown="domainsEnabled"
                              @update:selectedDomain="updateSelectedDomain"
                              @update:content="secretContent = $event" />

      <CustomDomainPreview :default_domain="selectedDomain" />

      <SecretFormPrivacyOptions :withRecipient="props.withRecipient"
                                :withExpiry="true"
                                :withPassphrase="true" />

      <div class="flex w-full mb-4 space-x-2">
        <GenerateButton
          :disabled="isGenerateDisabled"
          @click="$emit('generate')"
        />
        <CreateButton
          :disabled="isCreateDisabled"
          :with-asterisk="withAsterisk"
          @click="$emit('create')"
        />
      </div>

    </form>
  </div>
</template>
