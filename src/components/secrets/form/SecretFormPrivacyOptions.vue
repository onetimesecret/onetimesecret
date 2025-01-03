<script setup lang="ts">
import { Icon } from '@iconify/vue';
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import SecretFormDrawer from './SecretFormDrawer.vue';

// TODO; Was useWindowProps(['plan', 'secret_options']);
const plan = 'basic';
const secretOptions = {
  ttl: 7200,
  recipient: '',
  passphrase: '',
  metadata_only: false,
  precomputed_burn: false
};

interface Props {
  enabled?: boolean;
  withRecipient?: boolean;
  withPassphrase?: boolean;
  withExpiry?: boolean;
}

const props = withDefaults(defineProps<Props>(), {
  enabled: true,
  withRecipient: false,
  withPassphrase: true,
  withExpiry: true,
})

const { t } = useI18n();

const showPassphrase = ref(false);
const currentPassphrase = ref('');

const selectedLifetime = ref(secretOptions.value?.default_ttl?.toString() || 604800); // Default to 7 days if not set
console.debug('Initial selectedLifetime:', selectedLifetime.value);

const lifetimeOptions = computed(() => {
  const options = secretOptions.value?.ttl_options;
  if (!Array.isArray(options)) {
    console.warn('ttl_options is not an array:', options);
    return [];
  }
  const mappedOptions = options.map(seconds => {
    const option = {
      value: seconds.toString(),
      label: formatDuration(seconds)
    };

    return option;
  });
  console.debug('Mapped lifetime options:', mappedOptions);
  return mappedOptions;
});

/**
 * Formats the duration from seconds to a human-readable string.
 * @param {number} seconds - The duration in seconds.
 * @returns {string} - The formatted duration string.
 */
const formatDuration = (seconds: number): string => {
  console.debug('Formatting duration for seconds:', seconds);
  const units = [
    { key: 'day', seconds: 86400 },
    { key: 'hour', seconds: 3600 },
    { key: 'minute', seconds: 60 },
    { key: 'second', seconds: 1 }
  ];

  for (const unit of units) {
    const quotient = Math.floor(seconds / unit.seconds);
    if (quotient >= 1) {
      const result = t('web.UNITS.ttl.duration', { count: quotient, unit: t(`web.UNITS.ttl.time.${unit.key}`, quotient) });
      console.debug('Formatted duration:', result);
      return result;
    }
  }

  const result = t('web.UNITS.ttl.duration', { count: seconds, unit: t('web.UNITS.ttl.time.second', seconds) });
  console.debug('Formatted duration:', result);
  return result;
};

const filteredLifetimeOptions = computed(() => {
  console.debug('Computing filteredLifetimeOptions');
  const planTtl = plan.value?.options?.ttl || 0;
  console.debug('Plan TTL:', planTtl);
  if (!Array.isArray(lifetimeOptions.value)) {
    console.warn('lifetimeOptions is not an array:', lifetimeOptions.value);
    return [];
  }
  const filtered = lifetimeOptions.value.filter(option => {
    const optionValue = parseFloat(option.value);
    const isValid = !isNaN(optionValue) && optionValue <= planTtl;
    console.debug('Filtering option:', option, 'Is valid:', isValid);
    return isValid;
  });
  console.debug('Final filteredLifetimeOptions:', filtered);
  return filtered;
});

const togglePassphrase = () => {
  showPassphrase.value = !showPassphrase.value;
};

</script>

<template>
  <SecretFormDrawer title="Privacy Options">
    <div class="mt-4 space-y-6">
      <div class="flex flex-col space-y-6 md:flex-row md:space-x-4 md:space-y-0">
        <!-- Passphrase Field -->
        <div
          v-if="props.withPassphrase"
          class="flex-1">
          <label
            for="currentPassphrase"
            class="sr-only">Passphrase:</label>
          <div class="relative">
            <input
              :type="showPassphrase ? 'text' : 'password'"
              tabindex="3"
              id="currentPassphrase"
              v-model="currentPassphrase"
              name="passphrase"
              autocomplete="unique-passphrase"
              placeholder="Enter a passphrase"
              aria-label="Passphrase"
              class="w-full rounded-md border border-gray-300 px-4
                   py-2 transition-colors duration-200
                   focus:border-brandcomp-500 focus:ring-brandcomp-500 dark:border-gray-600
                   dark:bg-gray-700 dark:text-white"
            />
            <button
              type="button"
              @click="togglePassphrase()"
              class="absolute inset-y-0 right-0 flex items-center px-3 text-gray-500 transition-colors
                           duration-200 dark:text-gray-300">
              <Icon
                :icon="showPassphrase ? 'mdi:eye' : 'mdi:eye-off'"
                class="size-5"
              />
            </button>
          </div>
        </div>

        <!-- Lifetime Field -->
        <div
          v-if="props.withExpiry"
          class="flex-1">
          <label
            for="lifetime"
            class="sr-only">Lifetime:</label>
          <select
            id="lifetime"
            tabindex="4"
            name="ttl"
            v-model="selectedLifetime"
            class="w-full rounded-md border border-gray-300 px-4
                  py-2 transition-colors duration-200
                  focus:border-brandcomp-500 focus:ring-brandcomp-500 dark:border-gray-600
                  dark:bg-gray-700 dark:text-white">
            <option
              value=""
              disabled>
              {{ t('web.secrets.selectDuration') }}
            </option>
            <template v-if="filteredLifetimeOptions.length > 0">
              <option
                v-for="option in filteredLifetimeOptions"
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
        </div>
      </div>

      <!-- Recipient Field (if needed) -->
      <div
        v-if="props.withRecipient"
        class="flex flex-col">
        <label
          for="recipient"
          class="mb-2 block font-brand text-sm font-medium text-gray-500 transition-colors
                      duration-200 dark:text-gray-300">
          Recipient Address
        </label>
        <input
          type="email"
          tabindex="5"
          id="recipient"
          name="recipient[]"
          placeholder="tom@myspace.com"
          class="w-full rounded-md border border-gray-300 px-4 py-2 transition-colors duration-200
                      focus:border-brandcomp-500 focus:ring-brandcomp-500 dark:border-gray-600
                      dark:bg-gray-700 dark:text-white"
        />
      </div>
    </div>
  </SecretFormDrawer>
</template>
