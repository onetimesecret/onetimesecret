<script setup lang="ts">
import { Secret, SecretDetails } from '@/schemas/models';
import { useSecretsStore } from '@/stores/secretsStore';
import { ref } from 'vue';

interface Props {
  secretKey: string;
  record: Secret | null;
  details: SecretDetails | null;
}

const props = defineProps<Props>();
const emit = defineEmits(['secret-loaded']);
const secretStore = useSecretsStore();
const passphrase = ref('');
const isSubmitting = ref(false);

const submitForm = async () => {
  if (isSubmitting.value) return;

  isSubmitting.value = true;
  try {
    const response = await secretStore.revealSecret(props.secretKey, passphrase.value);
    // Announce success to screen readers
    const announcement = document.createElement('div');
    announcement.setAttribute('role', 'status');
    announcement.setAttribute('aria-live', 'polite');
    announcement.textContent = 'Secret revealed successfully';
    document.body.appendChild(announcement);
    setTimeout(() => announcement.remove(), 1000);

    // Emit the secret-loaded event with the response data
    emit('secret-loaded', {
      record: response.record,
      details: response.details
    });
  } catch {
    // Error handling done by store
  } finally {
    isSubmitting.value = false;
  }
};
</script>

<template>
  <div
    :class="[
      'w-full',
      'rounded-lg bg-white p-8 dark:bg-gray-800'
    ]"
    role="region"
    aria-label="Secret confirmation">
    <p
      v-if="record?.verification && !record?.has_passphrase"
      class="text-base text-gray-600 dark:text-gray-400"
      role="status"
      aria-live="polite">
      {{ $t('web.COMMON.click_to_verify') }}
    </p>

    <h2
      v-if="record?.has_passphrase"
      class="text-xl font-bold text-gray-800 dark:text-gray-200"
      id="passphrase-heading">
      {{ $t('web.shared.requires_passphrase') }}
    </h2>

    <form
      @submit.prevent="submitForm"
      class="space-y-4"
      aria-labelledby="passphrase-heading"
      :aria-describedby="record?.has_passphrase ? 'passphrase-description' : undefined">
      <!-- Hidden honeypot field for bots -->
      <input
        name="shrimp"
        type="hidden"
        :value="1"
        aria-hidden="true"
        tabindex="-1"
      />
      <input
        name="continue"
        type="hidden"
        value="true"
        aria-hidden="true"
        tabindex="-1"
      />

      <div v-if="record?.has_passphrase" class="space-y-2">
        <label
          :for="'passphrase-' + secretKey"
          class="sr-only">
          {{ $t('web.COMMON.enter_passphrase_here') }}
        </label>
        <input
          v-model="passphrase"
          :id="'passphrase-' + secretKey"
          type="password"
          name="passphrase"
          class="w-full rounded-md border border-gray-300 px-3 py-2
            focus:outline-none focus:ring-2 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white"
          autocomplete="current-password"
          :aria-label="$t('web.COMMON.enter_passphrase_here')"
          :placeholder="$t('web.COMMON.enter_passphrase_here')"
          aria-required="true"
        />
        <p
          id="passphrase-description"
          class="text-sm text-gray-500 dark:text-gray-400">
          {{ $t('web.COMMON.careful_only_see_once') }}
        </p>
      </div>

      <button
        type="submit"
        :disabled="isSubmitting"
        :class="[
          'w-full rounded-md bg-brand-500 px-6 py-3 text-3xl font-semibold text-white transition duration-150 ease-in-out hover:bg-brand-600 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 dark:focus:ring-offset-gray-800',
          'mt-4'
        ]"
        aria-live="polite">
        <span class="sr-only">{{ isSubmitting ? 'Submitting...' : 'Click to continue' }}</span>
        {{ isSubmitting ? $t('web.COMMON.submitting') : $t('web.COMMON.click_to_continue') }}
      </button>
    </form>

    <div class="mt-4 text-right">
      <p
        class="text-sm italic text-gray-500 dark:text-gray-400"
        role="alert"
        aria-live="polite">
        {{ $t('web.COMMON.careful_only_see_once') }}
      </p>
    </div>
  </div>
</template>

<style scoped>
/* Ensure focus outline is visible in all color schemes */
:focus {
  outline: 2px solid currentColor;
  outline-offset: 2px;
}

/* Improve color contrast for dark mode */
.dark .text-gray-400 {
  color: #9CA3AF;
}

.dark .text-gray-500 {
  color: #D1D5DB;
}

/* Ensure sufficient contrast for the submit button */
.bg-brand-500 {
  background-color: #2563EB; /* Ensure this meets WCAG contrast requirements */
}

.hover\:bg-brand-600:hover {
  background-color: #1D4ED8; /* Ensure this meets WCAG contrast requirements */
}

/* Ensure disabled state maintains sufficient contrast */
.disabled\:opacity-50:disabled {
  opacity: 0.75; /* Increased from 0.5 for better contrast */
}
</style>
