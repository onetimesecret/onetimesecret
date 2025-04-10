<!-- src/components/secrets/form/SecretForm.vue -->
<script setup lang="ts">
  import { computed, onMounted, ref, watch } from 'vue';
  import BasicFormAlerts from '@/components/BasicFormAlerts.vue';
  import OIcon from '@/components/icons/OIcon.vue';
  import SplitButton from '@/components/SplitButton.vue';
  import { useDomainDropdown } from '@/composables/useDomainDropdown';
  import { usePrivacyOptions } from '@/composables/usePrivacyOptions';
  import { useSecretConcealer } from '@/composables/useSecretConcealer';
  import { useProductIdentity } from '@/stores/identityStore';
  import { type ConcealedMessage } from '@/types/ui/concealed-message';
  import { nanoid } from 'nanoid';
  import HomepageLinksPlaceholder from '../HomepageLinksPlaceholder.vue';
  import SecretLinksTable from '../SecretLinksTable.vue';
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

  const productIdentity = useProductIdentity();
  const showFinalNotice = ref(false);
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

  const concealedMessages = ref<ConcealedMessage[]>([]);

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
      concealedMessages.value.unshift(newMessage);
      operations.reset();
      secretContentInput.value?.clearTextarea(); // Clear textarea
    },
  });

  const {
    state,
    lifetimeOptions,
    updatePassphrase,
    updateTtl,
    updateRecipient,
    togglePassphraseVisibility
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

  onMounted(() => {
    operations.updateField('share_domain', selectedDomain.value);
  });
</script>

<template>
  <div class="min-w-[320px] max-w-2xl mx-auto space-y-6">
    <!-- Enhanced Alert Display -->
    <BasicFormAlerts
      :errors="Array.from(validation.errors.values())"
      class="sticky top-4 z-50" />

    <form
      ref="form1"
      @submit.prevent="handleSubmit"
      class="space-y-6">
      <div
        ref="div1"
        class="overflow-visible rounded-xl border border-gray-200 bg-white shadow-lg dark:border-gray-700 dark:bg-slate-900">
        <!-- Main Content Section -->
        <div class="p-6 space-y-6">
          <!-- Secret Input Section -->
          <SecretContentInputArea
            v-show="selectedAction === 'create-link'"
            ref="secretContentInput"
            v-model:content="form.secret"
            :disabled="isSubmitting"
            :min-height="'200px'"
            :max-height="400"
            class="bg-gray-50 dark:bg-slate-800/50 transition-colors focus-within:bg-white dark:focus-within:bg-slate-800"
            @update:content="(content) => operations.updateField('secret', content)" />
          <div
            v-show="selectedAction === 'generate-password'"
            class="rounded-lg border border-gray-200 p-4 bg-gray-50 dark:bg-slate-800/50 dark:border-gray-700 text-center">
            <p class="text-gray-500 dark:text-gray-400 py-10">
              {{ $t('web.homepage.passwordGenerationMode') }}
            </p>
          </div>

          <!-- Form Controls Section -->
          <div class="grid gap-6 md:grid-cols-2">
            <!-- Passphrase Field -->
            <div class="relative">
              <div class="pointer-events-none absolute inset-y-0 left-3 flex items-center">
                <OIcon
                  collection="heroicons"
                  name="key"
                  class="h-4 w-4 text-gray-400" />
              </div>
              <input
                :type="state.passphraseVisibility ? 'text' : 'password'"
                :value="form.passphrase"
                :id="passphraseId"
                name="passphrase"
                autocomplete="off"
                :aria-invalid="!!getError('passphrase')"
                :aria-errormessage="getError('passphrase') ? passphraseErrorId : undefined"
                class="w-full rounded-lg border border-gray-200 bg-white pl-10 pr-10 py-2.5 text-sm text-gray-900 placeholder:text-gray-400 focus:border-blue-500 focus:ring-2 focus:ring-blue-500 dark:border-gray-700 dark:bg-slate-800 dark:text-white dark:placeholder:text-gray-500"
                :placeholder="$t('web.secrets.enterPassphrase')"
                @input="(e) => updatePassphrase((e.target as HTMLInputElement).value)" />
              <button
                type="button"
                @click="togglePassphraseVisibility"
                class="absolute inset-y-0 right-3 flex items-center">
                <OIcon
                  collection="heroicons"
                  :name="state.passphraseVisibility ? 'solid-eye' : 'outline-eye-off'"
                  class="h-4 w-4 text-gray-400 hover:text-gray-600" />
              </button>
            </div>
            <div v-if="getError('passphrase')"
                 :id="passphraseErrorId"
                 role="alert"
                 class="mt-1 text-sm text-red-500">
              {{ getError('passphrase') }}
            </div>

            <!-- Expiry Selection -->
            <div v-if="props.withExpiry" class="relative">
              <div class="pointer-events-none absolute inset-y-0 left-3 flex items-center">
                <OIcon
                  collection="heroicons"
                  name="fire"
                  class="h-4 w-4 text-gray-400" />
              </div>
              <select
                :value="form.ttl"
                :id="lifetimeId"
                name="ttl"
                :aria-invalid="!!getError('ttl')"
                :aria-errormessage="getError('ttl') ? lifetimeErrorId : undefined"
                class="w-full appearance-none rounded-lg border border-gray-200 bg-white pl-10 pr-10 py-2.5 text-sm text-gray-900 focus:border-blue-500 focus:ring-2 focus:ring-blue-500 dark:border-gray-700 dark:bg-slate-800 dark:text-white"
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
                <option v-else
                  value=""
                  disabled>
                  {{ $t('web.UNITS.ttl.noOptionsAvailable') }}
                </option>
              </select>
              <div class="pointer-events-none absolute inset-y-0 right-3 flex items-center">
                <OIcon
                  collection="heroicons"
                  name="chevron-down"
                  class="h-4 w-4 text-gray-400" />
              </div>
            </div>
            <div v-if="getError('ttl')"
                 :id="lifetimeErrorId"
                 role="alert"
                 class="mt-1 text-sm text-red-500">
              {{ getError('ttl') }}
            </div>
          </div>

          <!-- Recipient Field -->
          <div v-if="props.withRecipient" class="mt-4">
            <div class="relative">
              <div class="pointer-events-none absolute inset-y-0 left-3 flex items-center">
                <OIcon
                  collection="heroicons"
                  name="envelope"
                  class="h-4 w-4 text-gray-400" />
              </div>
              <input
                :value="form.recipient"
                :id="recipientId"
                type="email"
                name="recipient[]"
                placeholder="tom@myspace.com"
                :aria-invalid="!!getError('recipient')"
                :aria-errormessage="getError('recipient') ? recipientErrorId : undefined"
                class="w-full rounded-lg border border-gray-200 bg-white pl-10 pr-10 py-2.5 text-sm text-gray-900 placeholder:text-gray-400 focus:border-blue-500 focus:ring-2 focus:ring-blue-500 dark:border-gray-700 dark:bg-slate-800 dark:text-white dark:placeholder:text-gray-500"
                @input="(e) => updateRecipient((e.target as HTMLInputElement).value)" />
            </div>
            <div v-if="getError('recipient')"
                 :id="recipientErrorId"
                 role="alert"
                 class="mt-1 text-sm text-red-500">
              {{ getError('recipient') }}
            </div>
          </div>
        </div>

        <!-- Pro tip Section -->
        <div
          v-if="showProTip"
          class="flex items-start gap-3 p-4 bg-brandcomp-50 dark:bg-brandcomp-900/20">
          <OIcon
            collection="heroicons"
            name="information-circle"
            class="mt-0.5 h-5 w-5 flex-shrink-0 text-brandcomp-600 dark:text-brandcomp-500" />
          <p class="text-sm text-brandcomp-700 dark:text-brandcomp-300">
            {{ $t('web.homepage.protip1') }}
          </p>
        </div>

        <!-- Footer Section -->
        <div class="border-t border-gray-200 dark:border-gray-700">
          <!-- Actions Container -->
          <div class="px-6 py-4">
            <div class="flex flex-col sm:gap-4 sm:flex-row sm:items-center sm:justify-between">
              <!-- Domain Preview (grows to fill available space) -->
              <div class="order-1 sm:order-2 flex-grow min-w-0">
                <CustomDomainPreview
                  v-if="productIdentity.isCanonical"
                  :available-domains="availableDomains"
                  :with-domain-dropdown="domainsEnabled"
                  @update:selected-domain="updateSelectedDomain"
                  class="w-full" />
              </div>

              <!-- Action Button (maintains consistent width) -->
              <div class="order-2 sm:order-2 flex-shrink-0">
                <div class="mb-2">
                  <SplitButton
                    :with-generate="props.withGenerate"
                    :disabled="selectedAction === 'create-link' && !hasContent"
                    :disable-generate="selectedAction === 'create-link' && hasContent"
                    @update:action="selectedAction = $event" />
                </div>
              </div>
            </div>

            <!-- Final Notice Section -->
            <div
              v-if="showFinalNotice"
              class="border-t border-gray-200 dark:border-gray-700">
              <div class="flex items-start gap-3 p-4 bg-brandcomp-50 dark:bg-brandcomp-900/20">
                <OIcon
                  collection="heroicons"
                  name="information-circle"
                  class="mt-0.5 h-5 w-5 flex-shrink-0 text-brandcomp-600 dark:text-brandcomp-500" />
                <p class="text-sm text-brandcomp-700 dark:text-brandcomp-300"> </p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </form>

    <template v-if="concealedMessages.length > 0">
      <SecretLinksTable :concealedMessages="concealedMessages" />
    </template>
    <template v-else>
      <HomepageLinksPlaceholder
        title="No secrets yet"
        description="Create a secret above to get started." />
    </template>
  </div>
</template>
