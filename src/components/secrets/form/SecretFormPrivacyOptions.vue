<!-- src/components/secrets/form/SecretFormPrivacyOptions.vue -->

<script setup lang="ts">
import OIcon from '@/components/icons/OIcon.vue';
import { useI18n } from 'vue-i18n';
import { usePrivacyOptions } from '@/composables/usePrivacyOptions';
import SecretFormDrawer from './SecretFormDrawer.vue';
import type { SecretFormData } from '@/composables/useSecretForm';
import { computed } from 'vue';

interface Props {
  form: SecretFormData;
  validation: {
    errors: Map<keyof SecretFormData, string>;
  };
  operations: {
    updateField: <K extends keyof SecretFormData>(field: K, value: SecretFormData[K]) => void;
  };
  disabled?: boolean;
  withRecipient?: boolean;
  withPassphrase?: boolean;
  withExpiry?: boolean;
  cornerClass?: string;
}

const props = withDefaults(defineProps<Props>(), {
  disabled: false,
  withRecipient: false,
  withPassphrase: true,
  withExpiry: true,
});

const { t } = useI18n();

const {
  state,
  lifetimeOptions,
  updatePassphrase,
  updateTtl,
  updateRecipient,
  togglePassphraseVisibility,
} = usePrivacyOptions(props.operations);

const getError = (field: keyof SecretFormData) => props.validation.errors.get(field);

// Generate unique IDs for form fields to ensure proper label associations
const uniqueId = computed(() => `privacy-options-${Math.random().toString(36).substring(2, 9)}`);
const passphraseId = computed(() => `passphrase-${uniqueId.value}`);
const passphraseErrorId = computed(() => `passphrase-error-${uniqueId.value}`);
const lifetimeId = computed(() => `lifetime-${uniqueId.value}`);
const lifetimeErrorId = computed(() => `lifetime-error-${uniqueId.value}`);
const recipientId = computed(() => `recipient-${uniqueId.value}`);
const recipientErrorId = computed(() => `recipient-error-${uniqueId.value}`);
</script>

<template>
  <SecretFormDrawer :title="$t('web.secrets.privacyOptions')"
                    :corner-class="cornerClass">
    <div class="mt-4 space-y-6"
         role="group"
         aria-labelledby="privacy-options-heading">
      <div id="privacy-options-heading"
           class="sr-only">{{ $t('web.secrets.privacyOptions') }} Form</div>

      <div class="flex flex-col space-y-6 md:flex-row md:space-x-4 md:space-y-0">
        <!-- Passphrase Field -->
        <div v-if="withPassphrase"
             class="flex-1">
          <label :for="passphraseId"
                 class="mb-2 block font-brand text-sm font-medium text-gray-500 transition-colors duration-200 dark:text-gray-300">
            {{ $t('web.COMMON.secret_passphrase') }}
          </label>
          <div class="relative">
            <input :type="state.passphraseVisibility ? 'text' : 'password'"
                   :value="form.passphrase"
                   :disabled="disabled"
                   :aria-invalid="!!getError('passphrase')"
                   :aria-errormessage="getError('passphrase') ? passphraseErrorId : undefined"
                   :id="passphraseId"
                   name="passphrase"
                   autocomplete="off"
                   :placeholder="$t('enter-a-passphrase')"
                   class="w-full rounded-md border border-gray-300 px-4 py-2 transition-colors duration-200 focus:border-brandcomp-500 focus:ring-brandcomp-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white"
                   :class="[cornerClass]"
                   @input="(e) => updatePassphrase((e.target as HTMLInputElement).value)" />
            <button type="button"
                    :disabled="disabled"
                    @click="togglePassphraseVisibility"
                    aria-label="Toggle password visibility"
                    class="absolute inset-y-0 right-0 flex items-center px-3 text-gray-500 transition-colors duration-200 dark:text-gray-300">
              <OIcon collection="mdi"
                     :name="state.passphraseVisibility ? 'eye' : 'eye-off'"
                     aria-hidden="true"
                     class="size-5" />
            </button>
          </div>
          <div v-if="getError('passphrase')"
               :id="passphraseErrorId"
               role="alert"
               class="mt-1 text-sm text-red-500">
            {{ getError('passphrase') }}
          </div>
        </div>

        <!-- Lifetime Field -->
        <div v-if="withExpiry"
             class="flex-1">
          <label :for="lifetimeId"
                 class="mb-2 block font-brand text-sm font-medium text-gray-500 transition-colors duration-200 dark:text-gray-300">
            {{ t('web.LABELS.expiration_time') }}
          </label>
          <select :value="form.ttl"
                  :disabled="disabled"
                  :aria-invalid="!!getError('ttl')"
                  :aria-errormessage="getError('ttl') ? lifetimeErrorId : undefined"
                  :id="lifetimeId"
                  name="ttl"
                  :class="[cornerClass]"
                  class="w-full rounded-md border border-gray-300 px-4 py-2 transition-colors duration-200 focus:border-brandcomp-500 focus:ring-brandcomp-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white"
                  @change="(e) => updateTtl(Number((e.target as HTMLSelectElement).value))">
            <option value=""
                    disabled>
              {{ t('web.secrets.selectDuration') }}
            </option>
            <template v-if="lifetimeOptions.length > 0">
              <option v-for="option in lifetimeOptions"
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
          <div v-if="getError('ttl')"
               :id="lifetimeErrorId"
               role="alert"
               class="mt-1 text-sm text-red-500">
            {{ getError('ttl') }}
          </div>
        </div>
      </div>

      <!-- Recipient Field -->
      <div v-if="withRecipient"
           class="flex flex-col">
        <label :for="recipientId"
               class="mb-2 block font-brand text-sm font-medium text-gray-500 transition-colors duration-200 dark:text-gray-300">
          {{ $t('web.COMMON.secret_recipient_address') }}
        </label>
        <input :value="form.recipient"
               :disabled="disabled"
               :aria-invalid="!!getError('recipient')"
               :aria-errormessage="getError('recipient') ? recipientErrorId : undefined"
               type="email"
               :id="recipientId"
               name="recipient[]"
               placeholder="tom@myspace.com"
               :class="[cornerClass]"
               class="w-full rounded-md border border-gray-300 px-4 py-2 transition-colors duration-200 focus:border-brandcomp-500 focus:ring-brandcomp-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white"
               @input="(e) => updateRecipient((e.target as HTMLInputElement).value)" />
        <div v-if="getError('recipient')"
             :id="recipientErrorId"
             role="alert"
             class="mt-1 text-sm text-red-500">
          {{ getError('recipient') }}
        </div>
      </div>
    </div>
  </SecretFormDrawer>
</template>
