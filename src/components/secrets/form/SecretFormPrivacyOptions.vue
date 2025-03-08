<!-- src/components/secrets/form/SecretFormPrivacyOptions.vue -->

<script setup lang="ts">
import OIcon from '@/components/icons/OIcon.vue';
import { useI18n } from 'vue-i18n';
import { usePrivacyOptions } from '@/composables/usePrivacyOptions';
import SecretFormDrawer from './SecretFormDrawer.vue';
import type { SecretFormData } from '@/composables/useSecretForm';

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
</script>

<template>
  <SecretFormDrawer
    :title="$t('web.secrets.privacyOptions')"
    :corner-class="cornerClass">
    <div class="mt-4 space-y-6">
      <div class="flex flex-col space-y-6 md:flex-row md:space-x-4 md:space-y-0">
        <!-- Passphrase Field -->
        <div v-if="withPassphrase"
             class="flex-1">
          <label for="passphrase"
                 class="sr-only">Passphrase:</label>
          <div class="relative">
            <input :type="state.passphraseVisibility ? 'text' : 'password'"
                   :value="form.passphrase"
                   :disabled="disabled"
                   :aria-invalid="!!getError('passphrase')"
                   :aria-errormessage="getError('passphrase')"
                   tabindex="0"
                   id="passphrase"
                   name="passphrase"
                   autocomplete="unique-passphrase"
                   :placeholder="$t('enter-a-passphrase')"
                   :aria-label="$t('web.COMMON.secret_passphrase')"
                   class="w-full rounded-md border border-gray-300 px-4 py-2 transition-colors duration-200 focus:border-brandcomp-500 focus:ring-brandcomp-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white"
                   :class="[cornerClass]"
                   @input="(e) => updatePassphrase((e.target as HTMLInputElement).value)" />
                   <button type="button"
                           :disabled="disabled"
                           @click="togglePassphraseVisibility"
                           @keydown.enter="togglePassphraseVisibility"
                           aria-label="Toggle password visibility"
                           tabindex="0"
                    class="absolute inset-y-0 right-0 flex items-center px-3 text-gray-500 transition-colors duration-200 dark:text-gray-300">
                    <OIcon collection="mdi"
                           :name="state.passphraseVisibility ? 'eye' : 'eye-off'"
                           aria-hidden="true"
                           class="size-5" />
            </button>
          </div>
          <span v-if="getError('passphrase')"
                class="text-sm text-red-500">
            {{ getError('passphrase') }}
          </span>
        </div>

        <!-- Lifetime Field -->
        <div v-if="withExpiry"
             class="flex-1">
          <label for="lifetime"
                 class="sr-only">Lifetime:</label>
          <select :value="form.ttl"
                  :disabled="disabled"
                  :aria-invalid="!!getError('ttl')"
                  :aria-errormessage="getError('ttl')"
                  id="lifetime"
                  tabindex="0"
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
          <span v-if="getError('ttl')"
                class="text-sm text-red-500">
            {{ getError('ttl') }}
          </span>
        </div>
      </div>

      <!-- Recipient Field -->
      <div v-if="withRecipient"
           class="flex flex-col">
        <label for="recipient"
               class="mb-2 block font-brand text-sm font-medium text-gray-500 transition-colors duration-200 dark:text-gray-300">
          {{ $t('web.COMMON.secret_recipient_address') }}
        </label>
        <input :value="form.recipient"
               :disabled="disabled"
               :aria-invalid="!!getError('recipient')"
               :aria-errormessage="getError('recipient')"
               type="email"
               tabindex="0"
               id="recipient"
               name="recipient[]"
               placeholder="tom@myspace.com"
               :class="[cornerClass]"
               class="w-full rounded-md border border-gray-300 px-4 py-2 transition-colors duration-200 focus:border-brandcomp-500 focus:ring-brandcomp-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white"
               @input="(e) => updateRecipient((e.target as HTMLInputElement).value)" />
        <span v-if="getError('recipient')"
              class="text-sm text-red-500">
          {{ getError('recipient') }}
        </span>
      </div>
    </div>
  </SecretFormDrawer>
</template>
