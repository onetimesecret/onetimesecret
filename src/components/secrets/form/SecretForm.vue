<!-- src/components/secrets/form/SecretForm.vue -->

<script setup lang="ts">
  import BasicFormAlerts from '@/components/BasicFormAlerts.vue';
  import OIcon from '@/components/icons/OIcon.vue';
  import SplitButton from '@/components/SplitButton.vue';
  import { useDomainDropdown } from '@/composables/useDomainDropdown';
  import { usePrivacyOptions } from '@/composables/usePrivacyOptions';
  import { useSecretConcealer } from '@/composables/useSecretConcealer';
  import { WindowService } from '@/services/window.service';
  import { useConcealedMetadataStore } from '@/stores/concealedMetadataStore';
  import {
    DEFAULT_BUTTON_TEXT_LIGHT,
    DEFAULT_CORNER_CLASS,
    DEFAULT_PRIMARY_COLOR,
    useProductIdentity,
  } from '@/stores/identityStore';
  import { type ConcealedMessage } from '@/types/ui/concealed-message';
  import { nanoid } from 'nanoid';
  import { computed, onMounted, ref, watch } from 'vue';
  import { useRouter } from 'vue-router';

  import CustomDomainPreview from './../../CustomDomainPreview.vue';
  import SecretContentInputArea from './SecretContentInputArea.vue';

  export interface Props {
    enabled?: boolean;
    withRecipient?: boolean;
    withAsterisk?: boolean;
    withGenerate?: boolean;
    withExpiry?: boolean;
    cornerClass?: string;
    primaryColor?: string;
    buttonTextLight?: boolean;
  }

  const props = withDefaults(defineProps<Props>(), {
    enabled: true,
    withRecipient: false,
    withAsterisk: false,
    withGenerate: false,
    withExpiry: true,
    cornerClass: DEFAULT_CORNER_CLASS,
    primaryColor: DEFAULT_PRIMARY_COLOR,
    buttonTextLight: DEFAULT_BUTTON_TEXT_LIGHT,
  });

  const router = useRouter();
  const productIdentity = useProductIdentity();
  const concealedMetadataStore = useConcealedMetadataStore();
  const showProTip = ref(props.withAsterisk);

  // Get passphrase configuration for UI hints
  const secretOptions = computed(() => {
    return WindowService.get('secret_options');
  });

  const passphraseConfig = computed(() => secretOptions.value?.passphrase);
  const isPassphraseRequired = computed(() => passphraseConfig.value?.required || false);

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
      if (!response) throw 'Response is missing';
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

  onMounted(() => {
    operations.updateField('share_domain', selectedDomain.value);
  });
</script>

<template>
  <div class="mx-auto min-w-[320px] max-w-2xl space-y-8">
    <!-- Enhanced Alert Display -->
    <BasicFormAlerts
      :errors="Array.from(validation.errors.values())"
      class="sticky top-4 z-50" />

    <form
      ref="form1"
      @submit.prevent="handleSubmit"
      :aria-busy="isSubmitting"
      class="space-y-8">
      <!-- prettier-ignore-attribute class -->
      <div
        ref="div1"
        :class="[cornerClass]"
        class="group relative overflow-visible border border-gray-200/50
          bg-gradient-to-br from-white via-white to-gray-50/30
          shadow-[0_8px_30px_rgb(0,0,0,0.04),0_2px_8px_rgb(0,0,0,0.02)]
          transition-all duration-300 hover:shadow-[0_12px_40px_rgb(0,0,0,0.06),0_4px_12px_rgb(0,0,0,0.03)]
          dark:border-gray-700/50 dark:from-slate-900 dark:via-slate-900 dark:to-slate-800/30
          dark:shadow-[0_8px_30px_rgb(0,0,0,0.3),0_2px_8px_rgb(0,0,0,0.2)]">
        <!-- Subtle gradient overlay for depth -->
        <div class="pointer-events-none absolute inset-0 bg-gradient-to-b from-transparent via-transparent to-blue-500/[0.02] dark:to-blue-400/[0.03]"></div>

        <!-- Main Content Section -->
        <div class="relative p-8">
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
              :corner-class="cornerClass"
              aria-labelledby="secretContentLabel"
              @update:content="(content) => operations.updateField('secret', content)" />
          </span>

          <!-- Generate Password Text -->
          <div
            v-show="selectedAction === 'generate-password'"
            :class="[cornerClass]"
            class="group/generate relative overflow-hidden rounded-2xl border-2 border-brand-200/60 bg-gradient-to-br from-brand-50/80 via-white to-brand-50/50
              dark:border-brand-700/40 dark:from-brand-900/20 dark:via-slate-800/50 dark:to-brand-800/10"
            aria-labelledby="generatedPasswordHeader"
            aria-describedby="generatedPasswordDesc"
            role="region"
            ref="generatePasswordSection">
            <!-- Animated gradient orbs -->
            <div class="pointer-events-none absolute -left-16 -top-16 size-40 rounded-full bg-brand-200/20 blur-3xl dark:bg-brand-600/10"></div>
            <div class="pointer-events-none absolute -bottom-16 -right-16 size-40 rounded-full bg-blue-200/20 blur-3xl dark:bg-blue-600/10"></div>

            <div class="relative space-y-5 p-8 pb-10 text-center">
              <div class="flex justify-center">
                <div class="relative">
                  <!-- Pulsing ring animation -->
                  <div class="absolute inset-0 animate-pulse rounded-full bg-brand-400/20 blur-lg dark:bg-brand-500/20"></div>
                  <div class="relative rounded-2xl bg-gradient-to-br from-brand-100 to-brand-200 p-4 shadow-lg ring-4 ring-brand-300/30 dark:from-brand-800/50 dark:to-brand-900/50 dark:ring-brand-600/20">
                    <svg
                      xmlns="http://www.w3.org/2000/svg"
                      width="24"
                      height="24"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      stroke-width="2"
                      class="size-7 text-brand-700 dark:text-brand-300">
                      <path
                        d="M21 2l-2 2m-7.61 7.61a5.5 5.5 0 1 1-7.778 7.778 5.5 5.5 0 0 1 7.777-7.777zm0 0L15.5 7.5m0 0l3 3L22 7l-3-3m-3.5 3.5L19 4" />
                    </svg>
                  </div>
                </div>
              </div>

              <h4
                id="generatedPasswordHeader"
                class="text-xl font-semibold text-gray-900 dark:text-white"
                tabindex="-1">
                {{ $t('web.homepage.password_generation_title') }}
              </h4>

              <p
                id="generatedPasswordDesc"
                class="mx-auto max-w-md text-sm leading-relaxed text-gray-600 dark:text-gray-300">
                {{ $t('web.homepage.password_generation_description') }}
              </p>
            </div>
          </div>

          <!-- Form Controls Section -->
          <div class="mt-8 grid gap-6 md:grid-cols-2 md:items-start">
            <!-- Passphrase Field -->
            <div class="relative">
              <h3>
                <label
                  :for="passphraseId"
                  class="mb-2 block font-brand text-sm font-medium text-gray-700 dark:text-gray-300">
                  {{ $t('web.COMMON.secret_passphrase') }}
                  <span
                    v-if="isPassphraseRequired"
                    class="ml-1 text-red-500"
                    aria-label="Required"
                    >*</span
                  >
                </label>
              </h3>
              <!-- Fixed height container for hints to prevent layout shifts -->
              <div class="mb-2.5 min-h-[1rem]">
                <div
                  v-if="passphraseConfig"
                  class="text-xs text-gray-500 dark:text-gray-400">
                  <span v-if="passphraseConfig.minimum_length">
                    {{ $t('web.secrets.passphraseMinimumLength', { length: passphraseConfig.minimum_length }) }}
                  </span>
                  <span v-if="passphraseConfig.minimum_length && passphraseConfig.enforce_complexity">
                    •
                  </span>
                  <span v-if="passphraseConfig.enforce_complexity">
                    {{ $t('web.secrets.passphraseComplexityRequired') }}
                  </span>
                </div>
              </div>
              <div class="group/input relative">
                <!-- prettier-ignore-attribute class -->
                <input
                  :type="state.passphraseVisibility ? 'text' : 'password'"
                  :value="form.passphrase"
                  :id="passphraseId"
                  name="passphrase"
                  autocomplete="off"
                  :aria-invalid="!!getError('passphrase')"
                  :aria-errormessage="getError('passphrase') ? passphraseErrorId : undefined"
                  :class="[cornerClass, getError('passphrase') ? 'border-red-400 focus:border-red-500 focus:ring-red-500/20' : 'focus:border-blue-500 focus:ring-blue-500/20']"
                  class="w-full border border-gray-300/60 bg-white/50 py-3 pl-5 pr-11
                    text-sm text-gray-900 backdrop-blur-sm transition-all duration-200 placeholder:text-gray-400
                    hover:border-gray-400/60 hover:bg-white/80
                    focus:bg-white focus:outline-none focus:ring-4
                    dark:border-gray-600/60 dark:bg-slate-800/50 dark:text-white dark:placeholder:text-gray-500
                    dark:hover:border-gray-500/60 dark:hover:bg-slate-800/80
                    dark:focus:bg-slate-800"
                  :placeholder="$t('web.secrets.enterPassphrase')"
                  @input="(e) => updatePassphrase((e.target as HTMLInputElement).value)" />
                <!-- prettier-ignore-attribute class -->
                <button
                  type="button"
                  @click="togglePassphraseVisibility"
                  :aria-label="state.passphraseVisibility ? 'Hide passphrase' : 'Show passphrase'"
                  :aria-pressed="state.passphraseVisibility"
                  class="absolute inset-y-0 right-3 flex items-center rounded-md
                    transition-colors duration-200
                    focus:outline-none focus:ring-2 focus:ring-blue-500/50">
                  <OIcon
                    collection="heroicons"
                    :name="state.passphraseVisibility ? 'solid-eye' : 'outline-eye-off'"
                    class="size-5 text-gray-400 transition-colors duration-200 hover:text-gray-600 dark:hover:text-gray-300"
                    aria-hidden="true" />
                </button>
              </div>
            </div>

            <!-- Expiry Selection -->
            <div
              v-if="props.withExpiry"
              class="relative">
              <h3>
                <label
                  :for="lifetimeId"
                  class="mb-2 block font-brand text-sm font-medium text-gray-700 dark:text-gray-300">
                  {{ $t('web.LABELS.expiration_time') || 'Secret Expiration' }}
                </label>
              </h3>
              <!-- Empty spacer to match passphrase field hint area -->
              <div class="mb-2.5 min-h-[1rem]"></div>
              <div class="group/select relative">
                <!-- prettier-ignore-attribute class -->
                <select
                  :value="form.ttl"
                  :id="lifetimeId"
                  name="ttl"
                  :aria-invalid="!!getError('ttl')"
                  :aria-describedby="getError('ttl') ? lifetimeErrorId : undefined"
                  :class="[cornerClass, getError('ttl') ? 'border-red-400 focus:border-red-500 focus:ring-red-500/20' : 'focus:border-blue-500 focus:ring-blue-500/20']"
                  class="w-full appearance-none border border-gray-300/60
                    bg-white/50 py-3 pl-5 pr-10 text-sm text-gray-700 backdrop-blur-sm transition-all duration-200
                    hover:border-gray-400/60 hover:bg-white/80
                    focus:bg-white focus:outline-none focus:ring-4
                    dark:border-gray-600/60 dark:bg-slate-800/50 dark:text-white
                    dark:hover:border-gray-500/60 dark:hover:bg-slate-800/80
                    dark:focus:bg-slate-800"
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
                <!-- Custom dropdown icon -->
                <div class="pointer-events-none absolute inset-y-0 right-3 flex items-center">
                  <svg class="size-5 text-gray-400 transition-colors duration-200 group-hover/select:text-gray-600 dark:group-hover/select:text-gray-300" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
                  </svg>
                </div>
              </div>
            </div>
          </div>

          <!-- Recipient Field -->
          <div
            v-if="props.withRecipient"
            class="mt-8">
            <h3>
              <label
                :for="recipientId"
                class="mb-2 block font-brand text-sm font-medium text-gray-700 dark:text-gray-300">
                {{ $t('web.COMMON.secret_recipient_address') || 'Email Recipient' }}
              </label>
            </h3>
            <div class="relative">
              <div class="pointer-events-none absolute inset-y-0 left-4 flex items-center">
                <OIcon
                  collection="heroicons"
                  name="envelope"
                  class="size-5 text-gray-400"
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
                :class="[cornerClass, getError('recipient') ? 'border-red-400 focus:border-red-500 focus:ring-red-500/20' : 'focus:border-blue-500 focus:ring-blue-500/20']"
                class="w-full border border-gray-300/60
                  bg-white/50 px-12 py-3 text-sm text-gray-900 backdrop-blur-sm transition-all duration-200 placeholder:text-gray-400
                  hover:border-gray-400/60 hover:bg-white/80
                  focus:bg-white focus:outline-none focus:ring-4
                  dark:border-gray-600/60 dark:bg-slate-800/50 dark:text-white dark:placeholder:text-gray-500
                  dark:hover:border-gray-500/60 dark:hover:bg-slate-800/80
                  dark:focus:bg-slate-800"
                @input="(e) => updateRecipient((e.target as HTMLInputElement).value)" />
            </div>
          </div>
        </div>

        <!-- Pro tip Section -->
        <div
          v-if="showProTip"
          class="relative flex items-start gap-4 overflow-hidden bg-gradient-to-br from-brandcomp-50 via-brandcomp-50/80 to-brandcomp-100/50 p-6
            dark:from-brandcomp-900/30 dark:via-brandcomp-900/20 dark:to-brandcomp-800/20">
          <!-- Decorative gradient orb -->
          <div class="pointer-events-none absolute -right-10 -top-10 size-32 rounded-full bg-brandcomp-200/30 blur-2xl dark:bg-brandcomp-700/20"></div>
          <div class="relative shrink-0">
            <div class="rounded-full bg-brandcomp-100 p-2 ring-4 ring-brandcomp-200/50 dark:bg-brandcomp-800/50 dark:ring-brandcomp-700/30">
              <OIcon
                collection="heroicons"
                name="information-circle"
                class="size-5 text-brandcomp-600 dark:text-brandcomp-400" />
            </div>
          </div>
          <p class="relative text-sm leading-relaxed text-brandcomp-800 dark:text-brandcomp-200">
            {{ $t('web.homepage.protip1') }}
          </p>
        </div>

        <div class="relative border-t border-gray-200/50 bg-gradient-to-b from-transparent to-gray-50/30 dark:border-gray-700/50 dark:to-slate-800/30">
          <!-- Actions Container -->
          <div class="p-8">
            <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
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
                <SplitButton
                  :with-generate="props.withGenerate"
                  :corner-class="cornerClass"
                  :primary-color="primaryColor"
                  :button-text-light="buttonTextLight"
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
    </form>
  </div>
</template>
