<script setup lang="ts">
import OIcon from '@/components/icons/OIcon.vue';
import { useI18n } from 'vue-i18n';
import { usePrivacyOptions } from '@/composables/usePrivacyOptions';
import { useSecretForm } from '@/composables/useSecretForm';
import SecretFormDrawer from './SecretFormDrawer.vue';

interface Props {
  withRecipient?: boolean;
  withPassphrase?: boolean;
  withExpiry?: boolean;
}

const props = withDefaults(defineProps<Props>(), {
  withRecipient: false,
  withPassphrase: true,
  withExpiry: true,
});

const { t } = useI18n();
const { form, handleFieldChange } = useSecretForm();
const { lifetimeOptions, passphraseVisibility, togglePassphraseVisibility } =
  usePrivacyOptions();

</script>

<template>
  <SecretFormDrawer title="Privacy Options">
    <div class="mt-4 space-y-6">
      <div class="flex flex-col space-y-6 md:flex-row md:space-x-4 md:space-y-0">
        <!-- Passphrase Field -->
        <div v-if="props.withPassphrase"
             class="flex-1">
          <label for="passphrase"
                 class="sr-only">Passphrase:</label>
          <div class="relative">
            <input :type="passphraseVisibility ? 'text' : 'password'"
                   tabindex="3"
                   id="passphrase"
                   v-model="form.passphrase"
                   name="passphrase"
                   autocomplete="unique-passphrase"
                   placeholder="Enter a passphrase"
                   aria-label="Passphrase"
                   class="w-full rounded-md border border-gray-300 px-4 py-2 transition-colors duration-200 focus:border-brandcomp-500 focus:ring-brandcomp-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white"
                   @input="handleFieldChange.passphrase($event)" />
            <button type="button"
                    @click="togglePassphraseVisibility"
                    class="absolute inset-y-0 right-0 flex items-center px-3 text-gray-500 transition-colors duration-200 dark:text-gray-300">
              <OIcon collection="mdi"
                     :name="passphraseVisibility ? 'eye' : 'eye-off'"
                     class="size-5" />
            </button>
          </div>
        </div>

        <!-- Lifetime Field -->
        <div v-if="props.withExpiry"
             class="flex-1">
          <label for="lifetime"
                 class="sr-only">Lifetime:</label>
          <select id="lifetime"
                  tabindex="4"
                  name="ttl"
                  v-model="form.ttl"
                  @change="handleFieldChange.ttl($event)"
                  class="w-full rounded-md border border-gray-300 px-4 py-2 transition-colors duration-200 focus:border-brandcomp-500 focus:ring-brandcomp-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white">
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
        </div>
      </div>

      <!-- Recipient Field -->
      <div v-if="props.withRecipient"
           class="flex flex-col">
        <label for="recipient"
               class="mb-2 block font-brand text-sm font-medium text-gray-500 transition-colors duration-200 dark:text-gray-300">
          Recipient Address
        </label>
        <input type="email"
               tabindex="5"
               id="recipient"
               v-model="form.recipient"
               name="recipient[]"
               placeholder="tom@myspace.com"
               @input="handleFieldChange.recipient($event)"
               class="w-full rounded-md border border-gray-300 px-4 py-2 transition-colors duration-200 focus:border-brandcomp-500 focus:ring-brandcomp-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white" />
      </div>
    </div>
  </SecretFormDrawer>
</template>
