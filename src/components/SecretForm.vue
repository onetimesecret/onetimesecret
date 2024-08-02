<script setup lang="ts">
import { ref } from 'vue';

import SecretContentInputArea from './SecretContentInputArea.vue';
import SecretFormPrivacyOptions from './SecretFormPrivacyOptions.vue';
import CustomDomainPreview from './CustomDomainPreview.vue';

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

const availableDomains = window.custom_domains || [];
const defaultDomain = window.site_host;

// Add defaultDomain to the list of available domains if it's not already there
if (!availableDomains.includes(defaultDomain)) {
  availableDomains.push(defaultDomain);
}

// The selectedDomain is the first available domain by default
const selectedDomain = ref(availableDomains[0]);


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

      <!--
          v-model:selectedDomain is equivalent to:
            :selectedDomain="selectedDomain"
            @update:selectedDomain="selectedDomain = $event"
      -->

      <SecretContentInputArea
        :availableDomains="availableDomains"
        :initialDomain="selectedDomain"
        v-model:selectedDomain="selectedDomain"
      />

      <CustomDomainPreview :default_domain="selectedDomain" />

      <SecretFormPrivacyOptions
        :withRecipient="props.withRecipient"
        :withExpiry="true"
        :withPassphrase="true"
      />


      <button type="submit"
              class="text-xl w-full py-2 px-4 rounded mb-4
              bg-orange-600 hover:bg-orange-700 text-white
              font-bold2 "
              name="kind"
              value="share">
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
    </form>
  </div>
</template>
