<!-- src/components/secrets/form/SecretForm.vue -->

<script setup lang="ts">
import { computed, watch, onMounted } from 'vue';
import BasicFormAlerts from '@/components/BasicFormAlerts.vue';
import CustomDomainPreview from './../../CustomDomainPreview.vue';
import ConcealButton from './ConcealButton.vue';
import GenerateButton from './GenerateButton.vue';
import SecretContentInputArea from './SecretContentInputArea.vue';
import SecretFormPrivacyOptions from './SecretFormPrivacyOptions.vue';
import { useSecretConcealer } from '@/composables/useSecretConcealer';
import { useDomainDropdown } from '@/composables/useDomainDropdown';
import { useProductIdentity } from '@/stores/identityStore';
import { useRouter } from 'vue-router';

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

const router = useRouter();
const productIdentity = useProductIdentity();

const {
  form,
  validation,
  operations,
  isSubmitting,
  submit
} = useSecretConcealer({
  onSuccess: async (response) => {
    await router.push({
      name: 'Metadata link',
      params: { metadataKey: response.record.metadata.key }
    });
    operations.reset();
  }
});

const {
  availableDomains,
  selectedDomain,
  domainsEnabled,
  updateSelectedDomain
} = useDomainDropdown();

const hasContent = computed(() => form.secret.length > 0);

// Form submission handlers
const handleConceal = () => submit('conceal');
const handleGenerate = () => submit('generate');

// Watch for domain changes and update form
watch(selectedDomain, (domain) => {
  operations.updateField('share_domain', domain);
});

onMounted(() => {
  operations.updateField('share_domain', selectedDomain.value);
});
</script>

<template>
  <div class="min-w-[320px]">
    <BasicFormAlerts :errors="Array.from(validation.errors.values())" />

    <form @submit.prevent="handleConceal">
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
      <SecretContentInputArea :content="form.secret"
                              :share-domain="form.share_domain"
                              :available-domains="availableDomains"
                              :initial-domain="selectedDomain"
                              :with-domain-dropdown="domainsEnabled"
                              :disabled="isSubmitting"
                              :corner-class="productIdentity.cornerClass"
                              @update:selected-domain="updateSelectedDomain"
                              @update:content="(content) => operations.updateField('secret', content)" />

      <CustomDomainPreview v-if="productIdentity.isCanonical"
                           :default_domain="selectedDomain"
                           data-testid="custom-domain-preview" />

      <SecretFormPrivacyOptions :form="form"
                                :with-recipient="props.withRecipient"
                                :with-expiry="true"
                                :with-passphrase="true"
                                :validation="validation"
                                :operations="operations"
                                :corner-class="productIdentity.cornerClass"
                                :disabled="isSubmitting" />

      <div class="mb-4 flex w-full space-x-2">
        <Suspense v-if="props.withGenerate">
          <GenerateButton :disabled="hasContent || isSubmitting"
                          @click="handleGenerate" />
        </Suspense>

        <ConcealButton :disabled="!hasContent || isSubmitting"
                       :with-asterisk="withAsterisk"
                       :primary-color="productIdentity.primaryColor"
                       :corner-class="productIdentity.cornerClass"
                       @click="handleConceal" />
      </div>
    </form>
  </div>
</template>
