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

      <button type="submit" tabindex="6"
              class="text-xl w-full py-2 px-4 rounded mb-4
              bg-orange-600 hover:bg-orange-700 text-white
              font-bold2 disabled:opacity-50 disabled:cursor-not-allowed
              duration-300 ease-in-out transform hover:scale-105"
              name="kind"
              value="share"
              :disabled="!isFormValid">
        Create a secret link<span v-if="withAsterisk">*</span>
      </button>

      <!--
        To adjust the width and centering of the <hr> and button elements:

        1. For the <hr> element:
          - Use the `w-2/3` class to set the width to 2/3 of its container.
          - Use the `mx-auto` class to center it horizontally.
          - Example: <hr class="w-2/3 my-4 border-gray-200 mx-auto">

        2. For the button element:
          - Use the `w-2/3` class to set the width to 2/3 of its container.
          - Use the `mx-auto` class to center it horizontally.
          - Use the `block` class to ensure it behaves as a block-level element.
          - Example:
            <button type="submit"
                    v-if="props.withGenerate"
                    class="w-2/3 py-2 px-4 rounded mb-4
                    text-base
                    bg-gray-100 hover:bg-gray-400 text-gray-800
                    dark:bg-gray-700 dark:hover:bg-gray-600 dark:text-gray-200
                    mx-auto block"
                    name="kind"
                    value="generate">
              Or generate a random password
            </button>
      -->
      <hr class="w-1/4 my-4 border-gray-200 mx-auto">
      <button type="submit" tabindex="7"
              v-if="props.withGenerate"
              class="w-2/3 py-2 px-4 rounded mb-4
              text-base
              bg-gray-100 hover:bg-gray-400 text-gray-800
              dark:bg-gray-700 dark:hover:bg-gray-600 dark:text-gray-200
              mx-auto block
              duration-300 ease-in-out transform hover:scale-105"
              name="kind"
              value="generate">
        Or generate a random password
      </button>
    </form>
  </div>
</template>
