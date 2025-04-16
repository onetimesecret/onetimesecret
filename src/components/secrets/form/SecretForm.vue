<!-- src/components/secrets/form/SecretForm.vue -->
<script setup lang="ts">
  import BasicFormAlerts from '@/components/BasicFormAlerts.vue';
  import OIcon from '@/components/icons/OIcon.vue';
  import SplitButton from '@/components/SplitButton.vue';
  import { useDomainDropdown } from '@/composables/useDomainDropdown';
  import { usePrivacyOptions } from '@/composables/usePrivacyOptions';
  import { useSecretConcealer } from '@/composables/useSecretConcealer';
  import { useConcealedMetadataStore } from '@/stores/concealedMetadataStore';
  import { useProductIdentity } from '@/stores/identityStore';
  import { type ConcealedMessage } from '@/types/ui/concealed-message';
  import { nanoid } from 'nanoid';
  import { computed, onMounted, ref, watch, nextTick } from 'vue';
  import { useRouter } from 'vue-router';

  import CustomDomainPreview from './../../CustomDomainPreview.vue';
  import SecretContentInputArea from './SecretContentInputArea.vue';

  export interface Props {
    enabled?: boolean;
    withRecipient?: boolean;
    withAsterisk?: boolean;
    withGenerate?: boolean;
    withExpiry?: boolean;
  }

  const props = withDefaults(defineProps<Props>(), {
    enabled: true,
    withRecipient: false,
    withAsterisk: false,
    withGenerate: false,
    withExpiry: true,
  });

  const router = useRouter();
  const productIdentity = useProductIdentity();
  const concealedMetadataStore = useConcealedMetadataStore();
  const showProTip = ref(props.withAsterisk);

  // Helper function to get validation errors
  const getError = (field: keyof typeof form) => validation.errors.get(field);

  // Generate unique IDs for form fields to ensure proper label associations
  const uniqueId = computed(() => `secret-form-${Math.random().toString(36).substring(2, 9)}`);
  const passphraseId = computed(() => `passphrase-${uniqueId.value}`);
  const passphraseErrorId = computed(() => `passphrase-error-${uniqueId.value}`);
  const lifetimeId = computed(() => `lifetime-${uniqueId.value}`);
  const lifetimeErrorId = computed(() => `lifetime-error-${uniqueId.value}`);
  const recipientId = computed(() => `recipient-${uniqueId.value}`);
  const recipientErrorId = computed(() => `recipient-error-${uniqueId.value}`);

  const { form, validation, operations, isSubmitting, submit } = useSecretConcealer({
    onSuccess: async (response) => {
      const newMessage: ConcealedMessage = {
        id: nanoid(),
        metadata_key: response.record.metadata.key,
        secret_key: response.record.secret.key,
        response,
        clientInfo: {
          hasPassphrase: !!form.passphrase,
          ttl: form.ttl,
          createdAt: new Date(),
        },
      };
      // Add the message to the store
      concealedMetadataStore.addMessage(newMessage);
      operations.reset();
      secretContentInput.value?.clearTextarea(); // Clear textarea

      // Navigate to the metadata view page
      router.push(`/receipt/${response.record.metadata.key}`);
    },
  });

  const {
    state,
    lifetimeOptions,
    updatePassphrase,
    updateTtl,
    updateRecipient,
    togglePassphraseVisibility,
  } = usePrivacyOptions(operations);

  const { availableDomains, selectedDomain, domainsEnabled, updateSelectedDomain } =
    useDomainDropdown();

  // Compute whether the form has content or not
  const hasContent = computed(() => !!form.secret && form.secret.trim().length > 0);

  // Form submission handlers
  const handleSubmit = () => {
    // Use appropriate submission type based on selected action
    if (selectedAction.value === 'generate-password') {
      return submit('generate');
    }
    return submit('conceal');
  };
  const secretContentInput = ref<{ clearTextarea: () => void } | null>(null);
  const selectedAction = ref<'create-link' | 'generate-password'>('create-link');

  // Watch for domain changes and update form
  watch(selectedDomain, (domain) => {
    operations.updateField('share_domain', domain);
  });

  // Focus management when switching between Create Link and Generate Password modes
  const generatePasswordSection = ref<HTMLElement | null>(null);
  watch(selectedAction, (newAction) => {
    // Use nextTick to wait for DOM updates
    nextTick(() => {
      if (newAction === 'generate-password' && generatePasswordSection.value) {
        // Focus the generated password section header for screen readers
        const header = generatePasswordSection.value.querySelector('#generatedPasswordHeader');
        if (header && header instanceof HTMLElement) {
          header.focus();
        }
      } else if (newAction === 'create-link') {
        // Just announce the mode change, since we don't have direct access to focus the textarea
        // Screen readers will announce the change via the aria-live region in SplitButton
        console.log('Switched to Create Link mode');
        // Clear the textarea using the available method
        if (secretContentInput.value) {
          // We know we have this method from the ref type
          secretContentInput.value.clearTextarea();
        }
      }
    });
  });

  onMounted(() => {
    operations.updateField('share_domain', selectedDomain.value);
  });
</script>

<template>
  <div class="mx-auto min-w-[320px] max-w-2xl space-y-6">
    <!-- Enhanced Alert Display -->
    <BasicFormAlerts
      :errors="Array.from(validation.errors.values())"
      class="sticky top-4 z-50" />

    <form
      ref="form1"
      @submit.prevent="handleSubmit"
      :aria-busy="isSubmitting"
      class="space-y-6">
      <!-- prettier-ignore-attribute class -->
      <div
        ref="div1"
        class="overflow-visible rounded-xl border border-gray-200
          bg-white shadow-lg dark:border-gray-700 dark:bg-slate-900">
        <!-- Main Content Section -->
        <div class="p-6">
          <!-- Secret Input Section -->
          <span v-show="selectedAction === 'create-link'">
            <label
              id="secretContentLabel"
              class="sr-only">
              <!--
                  Using sr-only (screen-reader only) for this main content area because:
                  1. The purpose of a large textarea in a secret-sharing context is visually self-evident
                  2. The placeholder text provides sufficient visual context for sighted users
                  3. Other form fields (passphrase, expiration, etc.) keep visible labels as they
                      represent configuration options that need explicit identification
                -->
              {{ $t('secret-content') || 'Secret Content' }}
            </label>

            <SecretContentInputArea
              ref="secretContentInput"
              v-model:content="form.secret"
              :disabled="isSubmitting"
              :max-height="400"
              aria-labelledby="secretContentLabel"
              @update:content="(content) => operations.updateField('secret', content)" />
          </span>

          <!-- Generate Password Text -->
          <div
            v-show="selectedAction === 'generate-password'"
            class="rounded-lg border border-gray-200 bg-gray-50
              dark:border-gray-700 dark:bg-slate-800/50"
            aria-labelledby="generatedPasswordHeader"
            aria-describedby="generatedPasswordDesc"
            role="region"
            ref="generatePasswordSection">
            <div class="space-y-4 p-4 pb-6 text-center">
              <div class="flex justify-center">
                <div class="rounded-full bg-brand-100 p-3 dark:bg-brand-900/30">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    width="24"
                    height="24"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2"
                    class="size-6 text-brand-600 dark:text-brand-400">
                    <path
                      d="M21 2l-2 2m-7.61 7.61a5.5 5.5 0 1 1-7.778 7.778 5.5 5.5 0 0 1 7.777-7.777zm0 0L15.5 7.5m0 0l3 3L22 7l-3-3m-3.5 3.5L19 4" />
                  </svg>
                </div>
              </div>

              <h4
                id="generatedPasswordHeader"
                class="text-lg font-medium text-gray-900 dark:text-white"
                tabindex="-1">
                {{ $t('web.homepage.password_generation_title') }}
              </h4>

              <p
                id="generatedPasswordDesc"
                class="mx-auto max-w-md text-gray-600 dark:text-gray-300">
                {{ $t('web.homepage.password_generation_description') }}
              </p>
            </div>
          </div>

          <!-- Form Controls Section -->
          <div class="mt-6 grid gap-6 md:grid-cols-2">
            <!-- Passphrase Field -->
            <div class="relative">
              <h3>
                <label
                  :for="passphraseId"
                  class="mb-1 block font-brand text-sm text-gray-600 dark:text-gray-300">
                  {{ $t('web.COMMON.secret_passphrase') }}
                </label>
              </h3>
              <div class="relative">
                <!-- prettier-ignore-attribute class -->
                <input
                  :type="state.passphraseVisibility ? 'text' : 'password'"
                  :value="form.passphrase"
                  :id="passphraseId"
                  name="passphrase"
                  autocomplete="off"
                  :aria-invalid="!!getError('passphrase')"
                  :aria-errormessage="getError('passphrase') ? passphraseErrorId : undefined"
                  class="w-full rounded-lg border border-gray-200 bg-white py-2.5 pl-5 pr-10
                    text-sm text-gray-900 transition-shadow duration-200 placeholder:text-gray-400
                    focus:border-blue-500 focus:outline-none focus:ring-2 focus:ring-blue-500
                    dark:border-gray-700 dark:bg-slate-800 dark:text-white dark:placeholder:text-gray-500"
                  :placeholder="$t('web.secrets.enterPassphrase')"
                  @input="(e) => updatePassphrase((e.target as HTMLInputElement).value)" />
                <!-- prettier-ignore-attribute class -->
                <button
                  type="button"
                  @click="togglePassphraseVisibility"
                  :aria-label="state.passphraseVisibility ? 'Hide passphrase' : 'Show passphrase'"
                  :aria-pressed="state.passphraseVisibility"
                  class="absolute inset-y-0 right-3 flex items-center rounded-sm
                    focus:outline-none focus:ring-2 focus:ring-blue-500">
                  <OIcon
                    collection="heroicons"
                    :name="state.passphraseVisibility ? 'solid-eye' : 'outline-eye-off'"
                    class="size-4 text-gray-400 hover:text-gray-600"
                    aria-hidden="true" />
                </button>
              </div>
            </div>
            <div
              v-if="getError('passphrase')"
              :id="passphraseErrorId"
              role="alert"
              aria-live="assertive"
              class="mt-1 text-sm font-medium text-red-600 dark:text-red-400">
              {{ getError('passphrase') }}
            </div>

            <!-- Expiry Selection -->
            <div
              v-if="props.withExpiry"
              class="relative">
              <h3>
                <label
                  :for="lifetimeId"
                  class="mb-1 block font-brand text-sm text-gray-600 dark:text-gray-300">
                  {{ $t('web.LABELS.expiration_time') || 'Secret Expiration' }}
                </label>
              </h3>
              <div class="relative">
                <!-- prettier-ignore-attribute class -->
                <select
                  :value="form.ttl"
                  :id="lifetimeId"
                  name="ttl"
                  :aria-invalid="!!getError('ttl')"
                  :aria-describedby="getError('ttl') ? lifetimeErrorId : undefined"
                  class="w-full appearance-none rounded-lg border border-gray-200
                    bg-white py-2.5 pl-5 pr-10 text-sm text-gray-600 transition-shadow duration-200
                    focus:border-blue-500 focus:outline-none focus:ring-2 focus:ring-blue-500
                    dark:border-gray-700 dark:bg-slate-800 dark:text-white"
                  @change="(e) => updateTtl(Number((e.target as HTMLSelectElement).value))">
                  <option
                    value=""
                    disabled>
                    {{ $t('web.secrets.selectDuration') }}
                  </option>
                  <template v-if="lifetimeOptions.length > 0">
                    <option
                      v-for="option in lifetimeOptions"
                      :key="option.value"
                      :value="option.value">
                      {{ $t('web.secrets.expiresIn', { duration: option.label }) }}
                    </option>
                  </template>
                  <option
                    v-else
                    value=""
                    disabled>
                    {{ $t('web.UNITS.ttl.noOptionsAvailable') }}
                  </option>
                </select>
                <div class="pointer-events-none absolute inset-y-0 right-3 flex items-center">
                  <OIcon
                    collection="heroicons"
                    name="chevron-down"
                    class="size-4 text-gray-400" />
                </div>
              </div>
            </div>
            <div
              v-if="getError('ttl')"
              :id="lifetimeErrorId"
              role="alert"
              aria-live="assertive"
              class="mt-1 text-sm font-medium text-red-600 dark:text-red-400">
              {{ getError('ttl') }}
            </div>
          </div>

          <!-- Recipient Field -->
          <div
            v-if="props.withRecipient"
            class="mt-4">
            <h3>
              <label
                :for="recipientId"
                class="mb-1 block font-brand text-sm text-gray-700 dark:text-gray-300">
                {{ $t('web.COMMON.secret_recipient_address') || 'Email Recipient' }}
              </label>
            </h3>
            <div class="relative">
              <div class="pointer-events-none absolute inset-y-0 left-3 flex items-center">
                <OIcon
                  collection="heroicons"
                  name="envelope"
                  class="size-4 text-gray-400"
                  aria-hidden="true" />
              </div>
              <!-- prettier-ignore-attribute class -->
              <input
                :value="form.recipient"
                :id="recipientId"
                type="email"
                name="recipient[]"
                :placeholder="$t('web.COMMON.email_placeholder')"
                :aria-invalid="!!getError('recipient')"
                :aria-errormessage="getError('recipient') ? recipientErrorId : undefined"
                class="w-full rounded-lg border border-gray-200
                  bg-white px-10 py-2.5 text-sm text-gray-900 placeholder:text-gray-400
                  focus:border-blue-500 focus:ring-2 focus:ring-blue-500
                  dark:border-gray-700 dark:bg-slate-800 dark:text-white dark:placeholder:text-gray-500"
                @input="(e) => updateRecipient((e.target as HTMLInputElement).value)" />
            </div>
            <div
              v-if="getError('recipient')"
              :id="recipientErrorId"
              role="alert"
              aria-live="assertive"
              class="mt-1 text-sm font-medium text-red-600 dark:text-red-400">
              {{ getError('recipient') }}
            </div>
          </div>
        </div>

        <!-- Pro tip Section -->
        <div
          v-if="showProTip"
          class="flex items-start gap-3 bg-brandcomp-50 p-4 dark:bg-brandcomp-900/20">
          <OIcon
            collection="heroicons"
            name="information-circle"
            class="mt-0.5 size-5 shrink-0 text-brandcomp-600 dark:text-brandcomp-500" />
          <p class="text-sm text-brandcomp-700 dark:text-brandcomp-300">
            {{ $t('web.homepage.protip1') }}
          </p>
        </div>

        <div class="border-t border-gray-200 dark:border-gray-700">
          <!-- Actions Container -->
          <div class="p-6">
            <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between sm:gap-4 ">
              <!-- Domain Preview (grows to fill available space) -->
              <div class="order-1 min-w-0 grow sm:order-2">
                <CustomDomainPreview
                  v-if="productIdentity.isCanonical"
                  :available-domains="availableDomains"
                  :with-domain-dropdown="domainsEnabled"
                  @update:selected-domain="updateSelectedDomain"
                  class="w-full" />
              </div>

              <!-- Action Button (full-width on mobile, normal width on desktop) -->
              <div class="order-2 shrink-0 sm:order-2">
                <div class="mb-0 mt-3 sm:mt-0">
                  <SplitButton
                    :with-generate="props.withGenerate"
                    :disabled="selectedAction === 'create-link' && !hasContent"
                    :disable-generate="selectedAction === 'create-link' && hasContent"
                    :aria-label="
                      selectedAction === 'create-link' ? 'Create Secret Link' : 'Generate Password'
                    "
                    :aria-describedby="
                      selectedAction === 'create-link'
                        ? 'create-link-desc'
                        : 'generate-password-desc'
                    "
                    @update:action="selectedAction = $event" />
                  <div
                    class="sr-only"
                    id="create-link-desc">
                    Creates a secure link to share your secret
                  </div>
                  <div
                    class="sr-only"
                    id="generate-password-desc">
                    Generates a secure random password
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </form>
  </div>
</template>
