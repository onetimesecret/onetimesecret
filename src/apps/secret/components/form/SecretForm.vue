<!-- src/apps/secret/components/form/SecretForm.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import BasicFormAlerts from '@/shared/components/forms/BasicFormAlerts.vue';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import SplitButton from '@/shared/components/ui/SplitButton.vue';
  import { useDomainContext } from '@/shared/composables/useDomainContext';
  import { usePrivacyOptions } from '@/shared/composables/usePrivacyOptions';
  import { useSecretConcealer } from '@/shared/composables/useSecretConcealer';
  import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
  import { useConcealedReceiptStore } from '@/shared/stores/concealedReceiptStore';
  import {
    DEFAULT_BUTTON_TEXT_LIGHT,
    DEFAULT_CORNER_CLASS,
    DEFAULT_PRIMARY_COLOR,
  } from '@/shared/stores/identityStore';
  import { type LocalReceipt } from '@/types/ui/local-receipt';
  import { nanoid } from 'nanoid';
  import { storeToRefs } from 'pinia';
  import { computed, ref, watch } from 'vue';
  import { useRouter } from 'vue-router';
  import { useMediaQuery } from '@vueuse/core';

  const { t } = useI18n();

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
    /** When true, form stays on page after creation instead of navigating to receipt */
    workspaceMode?: boolean;
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
    workspaceMode: false,
  });

  const emit = defineEmits<{
    /** Emitted after successful secret creation with the response data */
    (e: 'created', response: LocalReceipt): void;
  }>();

  const router = useRouter();
  const concealedReceiptStore = useConcealedReceiptStore();
  const showProTip = ref(props.withAsterisk);

  // Get passphrase configuration for UI hints
  const bootstrapStore = useBootstrapStore();
  const { secret_options: secretOptions } = storeToRefs(bootstrapStore);

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
      const newMessage: LocalReceipt = {
        id: nanoid(),
        receiptExtid: response.record.receipt.identifier,
        receiptShortid: response.record.receipt.shortid,
        secretExtid: response.record.secret.identifier,
        secretShortid: response.record.secret.shortid,
        shareDomain: response.record.share_domain,
        hasPassphrase: !!form.passphrase,
        ttl: form.ttl as number,
        createdAt: Date.now(),
      };
      // Add the message to the store
      concealedReceiptStore.addMessage(newMessage);
      operations.reset();
      secretContentInput.value?.clearTextarea(); // Clear textarea

      // Emit event for parent components
      emit('created', newMessage);

      // In workspace mode, stay on page; otherwise navigate to receipt
      if (!props.workspaceMode) {
        router.push(`/receipt/${response.record.receipt.identifier}`);
      }
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

  const { currentContext, isContextActive } = useDomainContext();

  // Compute whether the form has content or not
  const hasContent = computed(() => !!form.secret && (form.secret as string).trim().length > 0);

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

  // Platform detection for keyboard hint (desktop only)
  const isDesktop = useMediaQuery('(min-width: 640px)');
  const isMac = computed(() =>
    typeof navigator !== 'undefined' && /Mac|iPod|iPhone|iPad/.test(navigator.platform)
  );
  const shortcutHint = computed(() => (isMac.value ? '⌘ Enter' : 'Ctrl Enter'));

  // Watch for domain context changes and update form
  // Use immediate: true to ensure the initial value is captured
  watch(
    () => currentContext.value.domain,
    (domain) => {
      if (domain) {
        operations.updateField('share_domain', domain);
      }
    },
    { immediate: true }
  );

  // Focus management when switching between Create Link and Generate Password modes
  const generatePasswordSection = ref<HTMLElement | null>(null);
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
        :class="[cornerClass]"
        class="overflow-visible border border-gray-200/50
          bg-gradient-to-br from-white to-gray-50/30
          shadow-[0_8px_30px_rgb(0,0,0,0.12),0_2px_8px_rgb(0,0,0,0.08)]
          backdrop-blur-sm
          dark:border-gray-700/50 dark:from-slate-900 dark:to-slate-800/30
          dark:shadow-[0_8px_30px_rgb(0,0,0,0.4),0_2px_8px_rgb(0,0,0,0.3)]">
        <!-- Main Content Section -->
        <div class="p-8">
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
              {{ t('web.secrets.secret_content') || 'Secret Content' }}
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
            class="relative overflow-hidden rounded-lg border border-brand-200/50 bg-gradient-to-br from-brand-50/80 to-purple-50/40 shadow-[0_4px_20px_rgb(0,0,0,0.08)] backdrop-blur-sm dark:border-brand-700/50 dark:from-brand-900/30 dark:to-purple-900/20 dark:shadow-[0_4px_20px_rgb(0,0,0,0.3)]"
            aria-labelledby="generatedPasswordHeader"
            aria-describedby="generatedPasswordDesc"
            role="region"
            ref="generatePasswordSection">
            <!-- Decorative blur orbs -->
            <div
              class="pointer-events-none absolute -left-12 -top-12 size-32 rounded-full bg-gradient-to-br from-brand-300/30 to-purple-300/20 blur-3xl"
              aria-hidden="true"></div>
            <div
              class="pointer-events-none absolute -bottom-12 -right-12 size-32 rounded-full bg-gradient-to-br from-purple-300/30 to-brand-300/20 blur-3xl"
              aria-hidden="true"></div>

            <div class="relative z-10 space-y-4 p-6 pb-8 text-center">
              <div class="flex justify-center">
                <div
                  class="animate-[pulse_2s_ease-in-out_infinite] rounded-full bg-gradient-to-br from-brand-100 to-purple-100 p-4 shadow-[0_0_0_0_rgba(var(--color-brand-500),0.5)] dark:from-brand-900/50 dark:to-purple-900/50">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    width="24"
                    height="24"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2"
                    class="size-7 text-brand-600 dark:text-brand-400">
                    <path
                      d="M21 2l-2 2m-7.61 7.61a5.5 5.5 0 1 1-7.778 7.778 5.5 5.5 0 0 1 7.777-7.777zm0 0L15.5 7.5m0 0l3 3L22 7l-3-3m-3.5 3.5L19 4" />
                  </svg>
                </div>
              </div>

              <h4
                id="generatedPasswordHeader"
                class="text-lg font-medium text-gray-900 dark:text-white"
                tabindex="-1">
                {{ t('web.homepage.password_generation_title') }}
              </h4>

              <p
                id="generatedPasswordDesc"
                class="mx-auto max-w-md text-gray-600 dark:text-gray-300">
                {{ t('web.homepage.password_generation_description') }}
              </p>
            </div>
          </div>

          <!-- Form Controls Section -->
          <div class="mt-6 grid gap-6 md:grid-cols-2 md:items-start">
            <!-- Passphrase Field -->
            <div class="relative">
              <h3>
                <label
                  :for="passphraseId"
                  class="mb-1 block font-brand text-sm text-gray-600 dark:text-gray-300">
                  {{ t('web.COMMON.secret_passphrase') }}
                  <span
                    v-if="isPassphraseRequired"
                    class="ml-1 text-red-500"
                    aria-label="Required"
                    >*</span
                  >
                </label>
              </h3>
              <!-- Fixed height container for hints to prevent layout shifts -->
              <div class="mb-2 min-h-4">
                <div
                  v-if="passphraseConfig"
                  class="text-xs text-gray-500 dark:text-gray-400">
                  <span v-if="passphraseConfig.minimum_length">
                    {{
                      t('web.secrets.passphraseMinimumLength', {
                        length: passphraseConfig.minimum_length,
                      })
                    }}
                  </span>
                  <span
                    v-if="passphraseConfig.minimum_length && passphraseConfig.enforce_complexity">
                    •
                  </span>
                  <span v-if="passphraseConfig.enforce_complexity">
                    {{ t('web.secrets.passphraseComplexityRequired') }}
                  </span>
                </div>
              </div>
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
                  :class="[
                    cornerClass,
                    getError('passphrase')
                      ? 'border-red-500/50 focus:border-red-500 focus:ring-red-500/20'
                      : '',
                  ]"
                  class="w-full border border-gray-200/60 bg-white/80 backdrop-blur-sm py-2.5 pl-5 pr-10
                    text-sm text-gray-900 transition-all duration-300 placeholder:text-gray-400
                    hover:border-gray-300/80 hover:bg-white/90
                    focus:border-blue-500/80 focus:bg-white focus:outline-none focus:ring-4 focus:ring-blue-500/20
                    dark:border-gray-700/60 dark:bg-slate-800/80 dark:text-white dark:placeholder:text-gray-500
                    dark:hover:border-gray-600/80 dark:hover:bg-slate-800/90
                    dark:focus:border-blue-400/80 dark:focus:bg-slate-800 dark:focus:ring-blue-400/20"
                  :placeholder="t('web.secrets.enterPassphrase')"
                  @input="(e) => updatePassphrase((e.target as HTMLInputElement).value)" />
                <!-- prettier-ignore-attribute class -->
                <button
                  type="button"
                  @click="togglePassphraseVisibility"
                  :aria-label="state.passphraseVisibility ? 'Hide passphrase' : 'Show passphrase'"
                  :aria-pressed="state.passphraseVisibility"
                  class="absolute inset-y-0 right-3 flex items-center
                    focus:outline-none focus:ring-2 focus:ring-blue-500">
                  <OIcon
                    collection="heroicons"
                    :name="state.passphraseVisibility ? 'solid-eye' : 'outline-eye-off'"
                    class="size-4 text-gray-400 hover:text-gray-600"
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
                  class="mb-1 block font-brand text-sm text-gray-600 dark:text-gray-300">
                  {{ t('web.LABELS.expiration_time') || 'Secret Expiration' }}
                </label>
              </h3>
              <!-- Empty spacer to match passphrase field hint area -->
              <div class="mb-2 min-h-4"></div>
              <div class="relative">
                <!-- prettier-ignore-attribute class -->
                <select
                  :value="form.ttl"
                  :id="lifetimeId"
                  name="ttl"
                  :aria-invalid="!!getError('ttl')"
                  :aria-describedby="getError('ttl') ? lifetimeErrorId : undefined"
                  :class="[
                    cornerClass,
                    getError('ttl')
                      ? 'border-red-500/50 focus:border-red-500 focus:ring-red-500/20'
                      : '',
                  ]"
                  class="w-full appearance-none border border-gray-200/60
                    bg-white/80 backdrop-blur-sm py-2.5 pl-5 pr-10 text-sm text-gray-600 transition-all duration-300
                    hover:border-gray-300/80 hover:bg-white/90
                    focus:border-blue-500/80 focus:bg-white focus:outline-none focus:ring-4 focus:ring-blue-500/20
                    dark:border-gray-700/60 dark:bg-slate-800/80 dark:text-white
                    dark:hover:border-gray-600/80 dark:hover:bg-slate-800/90
                    dark:focus:border-blue-400/80 dark:focus:bg-slate-800 dark:focus:ring-blue-400/20"
                  @change="(e) => updateTtl(Number((e.target as HTMLSelectElement).value))">
                  <option
                    value=""
                    disabled>
                    {{ t('web.secrets.selectDuration') }}
                  </option>
                  <template v-if="lifetimeOptions.length > 0">
                    <option
                      v-for="option in lifetimeOptions"
                      :key="option.value"
                      :value="option.value">
                      {{ t('web.secrets.expiresIn', { duration: option.label }) }}
                    </option>
                  </template>
                  <option
                    v-else
                    value=""
                    disabled>
                    {{ t('web.UNITS.ttl.noOptionsAvailable') }}
                  </option>
                </select>
              </div>
            </div>
          </div>

          <!-- Recipient Field -->
          <div
            v-if="props.withRecipient"
            class="mt-6">
            <h3>
              <label
                :for="recipientId"
                class="mb-1 block font-brand text-sm text-gray-700 dark:text-gray-300">
                {{ t('web.COMMON.secret_recipient_address') || 'Email Recipient' }}
              </label>
            </h3>
            <div class="relative">
              <div class="pointer-events-none absolute inset-y-0 left-3 flex items-center">
                <OIcon
                  collection="heroicons"
                  name="envelope"
                  size="5"
                  class="text-gray-500 dark:text-gray-400"
                  aria-hidden="true" />
              </div>
              <!-- prettier-ignore-attribute class -->
              <input
                :id="recipientId"
                :value="form.recipient"
                type="email"
                name="recipient[]"
                autocomplete="email"
                :placeholder="t('web.COMMON.email_placeholder')"
                :aria-invalid="!!getError('recipient')"
                :aria-errormessage="getError('recipient') ? recipientErrorId : undefined"
                :class="[
                  cornerClass,
                  getError('recipient')
                    ? 'border-red-500/50 focus:border-red-500 focus:ring-red-500/20'
                    : '',
                ]"
                class="w-full border border-gray-200/60 bg-white/80 backdrop-blur-sm
                  py-2.5 pl-10 pr-4 text-sm text-gray-900 placeholder:text-gray-400
                  transition-colors duration-200
                  hover:border-gray-300/80 hover:bg-white/90
                  focus:border-blue-500/80 focus:bg-white focus:outline-none focus:ring-4 focus:ring-blue-500/20
                  dark:border-gray-700/60 dark:bg-slate-800/80 dark:text-white dark:placeholder:text-gray-500
                  dark:hover:border-gray-600/80 dark:hover:bg-slate-800/90
                  dark:focus:border-blue-400/80 dark:focus:bg-slate-800 dark:focus:ring-blue-400/20"
                @input="(e) => updateRecipient((e.target as HTMLInputElement).value)" />
            </div>
          </div>
        </div>

        <!-- Pro tip Section -->
        <div
          v-if="showProTip"
          class="relative flex items-start gap-3 overflow-hidden bg-gradient-to-r from-brandcomp-50/90 to-brandcomp-100/60 p-5 backdrop-blur-sm dark:from-brandcomp-900/30 dark:to-brandcomp-800/20">
          <!-- Decorative blur orb -->
          <div
            class="pointer-events-none absolute -bottom-8 -right-8 size-24 rounded-full bg-brandcomp-200/40 blur-2xl dark:bg-brandcomp-700/30"
            aria-hidden="true"></div>
          <OIcon
            collection="heroicons"
            name="information-circle"
            class="relative z-10 mt-0.5 size-5 shrink-0 text-brandcomp-600 dark:text-brandcomp-500" />
          <p class="relative z-10 text-sm text-brandcomp-700 dark:text-brandcomp-300">
            {{ t('web.homepage.protip1') }}
          </p>
        </div>

        <div class="border-t border-gray-200/50 dark:border-gray-700/50">
          <!-- Actions Container -->
          <div class="p-8">
            <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between sm:gap-4">
              <!-- Domain Context Indicator -->
              <div
                v-if="isContextActive"
                class="order-1 flex items-center gap-2 text-sm sm:order-1">
                <span class="text-gray-600 dark:text-gray-400">
                  {{ t('web.LABELS.creating_links_for') }}
                </span>
                <div
                  class="inline-flex items-center gap-1.5 rounded-full px-3 py-1.5 text-sm font-medium transition-all duration-150"
                  :class="
                    currentContext.isCanonical
                      ? 'bg-gray-100 text-gray-700 dark:bg-gray-700 dark:text-gray-300'
                      : 'bg-brand-50 text-brand-700 dark:bg-brand-900/30 dark:text-brand-300'
                  "
                  role="status"
                  :aria-label="
                    t('web.LABELS.scope_indicator', { domain: currentContext.displayName })
                  ">
                  <OIcon
                    collection="heroicons"
                    :name="currentContext.isCanonical ? 'user-circle' : 'building-office'"
                    class="size-4"
                    aria-hidden="true" />
                  <span class="max-w-[180px] truncate">{{ currentContext.displayName }}</span>
                </div>
              </div>

              <!-- Action Button (full-width on mobile, normal width on desktop) -->
              <div class="order-2 shrink-0 sm:order-2">
                <div class="mb-0 mt-3 sm:mt-0">
                  <SplitButton
                    :with-generate="props.withGenerate"
                    :corner-class="cornerClass"
                    :primary-color="primaryColor"
                    :button-text-light="buttonTextLight"
                    :disabled="selectedAction === 'create-link' && !hasContent"
                    :disable-generate="selectedAction === 'create-link' && hasContent"
                    :keyboard-shortcut-enabled="true"
                    :show-keyboard-hint="false"
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

            <!-- Keyboard hint row (desktop only) -->
            <div
              v-if="isDesktop"
              class="mt-3 flex justify-end">
              <span class="text-xs text-gray-500 dark:text-gray-400">
                {{ shortcutHint }}
              </span>
            </div>
          </div>
        </div>
      </div>
    </form>
  </div>
</template>
