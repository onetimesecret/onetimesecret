<script setup lang="ts">
import { computed, ref, watch } from 'vue';

import CustomDomainPreview from './CustomDomainPreview.vue';
import SecretContentInputArea from './SecretContentInputArea.vue';
import SecretFormPrivacyOptions from './SecretFormPrivacyOptions.vue';

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

      <div class="flex w-full mb-4">
        <button type="submit"
                class="generate-btn text-base py-2 px-2 pr-6 rounded mr-2
                dark:bg-brandcompdim-900 bg-brand-100
                hover:bg-gray-600 dark:hover:bg-gray-600
                text-white font-medium transition-all duration-300 ease-in-out transform
                  w-10 hover:w-56 overflow-hidden whitespace-nowrap group
                  disabled:opacity-50 disabled:cursor-not-allowed
                disabled:bg-gray-400 dark:disabled:bg-gray-700
                disabled:hover:bg-gray-400 dark:disabled:hover:bg-gray-700
                  disabled:hover:scale-100 disabled:hidden"
                :disabled="isFormValid"
                name="kind"
                value="generate"
                title="Generate Password is disabled when the form is valid">
          <span class="inline-block transition-margin duration-300 ease-in-out mr-0 group-hover:mr-2">🔑</span>
          <span class="opacity-0 transition-opacity duration-300 ease-in-out group-hover:opacity-100">Generate
            Password</span>
        </button>

        <button type="submit"
                class="text-xl flex-grow py-2 px-4 rounded
          bg-orange-600 hover:bg-orange-700 text-white
          font-bold2 disabled:opacity-50 disabled:cursor-not-allowed
          duration-300 ease-in-out transform hover:scale-105 disabled:hover:scale-100"
                name="kind"
                value="share"
                :disabled="!isFormValid">
          Create a secret link<span v-if="withAsterisk">*</span>
        </button>
      </div>

    </form>
  </div>
</template>
