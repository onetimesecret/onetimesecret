<!-- src/apps/workspace/components/domains/DomainEmailConfigForm.vue -->

<script setup lang="ts">
/**
 * Domain Email Configuration Form
 *
 * Provides email provider selection and sender identity fields.
 * Mirrors the DomainSsoConfigForm pattern with provider-specific guidance,
 * auto PUT/PATCH selection, and delete support.
 */
import { useI18n } from 'vue-i18n';
import { computed, ref } from 'vue';
import { z } from 'zod';
import OIcon from '@/shared/components/icons/OIcon.vue';
import BasicFormAlerts from '@/shared/components/forms/BasicFormAlerts.vue';
import type { EmailConfigFormState } from '@/shared/composables/useEmailConfig';
import type { TestEmailConfigResponse } from '@/schemas/api/domains/responses/test-email-config';

const emailSchema = z.string().email();

interface Props {
  formState: EmailConfigFormState;
  isConfigured: boolean;
  isSaving: boolean;
  isDeleting: boolean;
  isTesting: boolean;
  hasUnsavedChanges: boolean;
  provider?: string;
  testResult?: TestEmailConfigResponse | null;
  testError?: string;
  error?: string;
  displayDomain?: string;
  flexibleFromDomain?: boolean;
}

const props = defineProps<Props>();

const emit = defineEmits<{
  (e: 'update:formState', value: EmailConfigFormState): void;
  (e: 'save'): void;
  (e: 'discard'): void;
  (e: 'delete'): void;
  (e: 'test'): void;
}>();

const { t } = useI18n();

// Local proxy for form state so we can emit updates
const localForm = computed({
  get: () => props.formState,
  set: (value: EmailConfigFormState) => emit('update:formState', value),
});

const updateField = <K extends keyof EmailConfigFormState>(
  key: K,
  value: EmailConfigFormState[K]
) => {
  emit('update:formState', { ...props.formState, [key]: value });
};

// Individual field models for v-model binding (handles autocomplete reliably)
const fromName = computed({
  get: () => props.formState.from_name,
  set: (value: string) => updateField('from_name', value),
});

const fromAddress = computed({
  get: () => props.formState.from_address,
  set: (value: string) => updateField('from_address', value),
});

const replyTo = computed({
  get: () => props.formState.reply_to,
  set: (value: string) => updateField('reply_to', value),
});

// Split input mode: local part editable, domain fixed to custom domain
const showSplitInput = computed(() =>
  !props.flexibleFromDomain && !!props.displayDomain
);

/**
 * Split-input local part: editable prefix with a fixed @displayDomain suffix.
 * Getter takes the first segment before '@', so malformed values like
 * "bad@part@example.com" normalize to "bad" rather than being rejected.
 * Setter reconstructs the full address as `${localPart}@${displayDomain}`.
 */
const fromAddressLocalPart = computed({
  get: () => {
    if (!showSplitInput.value) return '';
    const full = props.formState.from_address;
    return full.split('@')[0] || '';
  },
  set: (localPart: string) => {
    const domain = props.displayDomain || '';
    const fullEmail = localPart ? `${localPart}@${domain}` : '';
    emit('update:formState', { ...props.formState, from_address: fullEmail });
  },
});

// Form validation
const isFormValid = computed(() => {
  if (!localForm.value.from_name.trim()) return false;

  if (showSplitInput.value) {
    // Split mode: validate the composed address so invalid local parts are caught client-side
    const localPart = fromAddressLocalPart.value.trim();
    if (!localPart) return false;
    const composed = `${localPart}@${props.displayDomain}`;
    if (!emailSchema.safeParse(composed).success) return false;
  } else {
    // Full email mode
    if (!localForm.value.from_address.trim()) return false;
    if (!emailSchema.safeParse(localForm.value.from_address.trim()).success) return false;
  }

  // reply_to is optional but must be valid if provided
  if (localForm.value.reply_to.trim() && !emailSchema.safeParse(localForm.value.reply_to.trim()).success) {
    return false;
  }

  return true;
});

// Delete confirmation
const showDeleteConfirm = ref(false);

const handleSave = () => {
  if (!isFormValid.value || props.isSaving) return;
  emit('save');
};

const handleDelete = () => {
  emit('delete');
  showDeleteConfirm.value = false;
};

const handleTestEmail = () => {
  if (props.isTesting || props.isSaving) return;
  emit('test');
};

/** Test email requires a saved config but not form validity or unsaved changes. */
const canTestEmail = computed(() =>
  props.isConfigured && !props.isTesting && !props.isSaving && !props.isDeleting
);

const providerDisplayName = computed(() => {
  const map: Record<string, string> = {
    ses: 'Amazon SES',
    sendgrid: 'SendGrid',
    lettermint: 'Lettermint',
    inherit: '',
  };
  return props.provider ? (map[props.provider] ?? '') : '';
});
</script>

<template>
  <form
    @submit.prevent="handleSave"
    class="space-y-6">
    <!-- Alerts -->
    <BasicFormAlerts
      v-if="error"
      :error="error" />

    <!-- Form Fields Container -->
    <div>
      <!-- From Name -->
      <div>
        <label
          for="email-from-name"
          class="block text-sm font-medium text-gray-700 dark:text-gray-300">
          {{ t('web.domains.email.from_name_label') }}
          <span class="text-red-500" aria-hidden="true">*</span>
        </label>
        <input
          id="email-from-name"
          v-model="fromName"
          type="text"
          required
          maxlength="100"
          :placeholder="t('web.domains.email.from_name_placeholder')"
          class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-brand-500 focus:ring-brand-500 disabled:cursor-not-allowed disabled:bg-gray-100 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-400 dark:disabled:bg-gray-800 sm:text-sm" />
      </div>

      <!-- From Address -->
      <div class="mt-6">
        <label
          for="email-from-address"
          class="block text-sm font-medium text-gray-700 dark:text-gray-300">
          {{ t('web.domains.email.from_address_label') }}
          <span class="text-red-500" aria-hidden="true">*</span>
        </label>

        <!-- Split input: local part + fixed domain -->
        <div v-if="showSplitInput" class="mt-1 flex">
          <input
            id="email-from-address"
            :value="fromAddressLocalPart"
            type="text"
            required
            autocomplete="off"
            placeholder="noreply"
            class="block w-full min-w-0 flex-1 rounded-l-md border-gray-300 shadow-sm focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-400 sm:text-sm"
            @input="fromAddressLocalPart = ($event.target as HTMLInputElement).value" />
          <span
            class="inline-flex items-center rounded-r-md border border-l-0 border-gray-300 bg-gray-50 px-3 text-sm text-gray-500 dark:border-gray-600 dark:bg-gray-600 dark:text-gray-300">
            @{{ displayDomain }}
          </span>
        </div>

        <!-- Full email input (flexible mode) -->
        <input
          v-else
          id="email-from-address"
          :value="fromAddress"
          type="email"
          required
          autocomplete="off"
          :placeholder="t('web.domains.email.from_address_placeholder')"
          class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-brand-500 focus:ring-brand-500 disabled:cursor-not-allowed disabled:bg-gray-100 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-400 dark:disabled:bg-gray-800 sm:text-sm"
          @input="fromAddress = ($event.target as HTMLInputElement).value" />
      </div>

      <!-- Reply-To Address -->
      <div class="mt-6">
        <label
          for="email-reply-to"
          class="block text-sm font-medium text-gray-700 dark:text-gray-300">
          {{ t('web.domains.email.reply_to_label') }}
        </label>
        <input
          id="email-reply-to"
          :value="replyTo"
          type="email"
          autocomplete="off"
          :placeholder="t('web.domains.email.reply_to_placeholder')"
          class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-brand-500 focus:ring-brand-500 disabled:cursor-not-allowed disabled:bg-gray-100 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-400 dark:disabled:bg-gray-800 sm:text-sm"
          @input="replyTo = ($event.target as HTMLInputElement).value" />
      </div>
    </div>

    <!-- Test Email -->
    <div class="rounded-lg border border-gray-200 bg-gray-50 p-4 dark:border-gray-700 dark:bg-gray-700/50">
      <div class="flex items-start justify-between">
        <div class="flex-1">
          <h4 class="text-sm font-medium text-gray-900 dark:text-white">
            {{ t('web.domains.email.test_email_title') }}
          </h4>
          <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
            {{ t('web.domains.email.test_email_hint') }}
          </p>
        </div>
        <button
          type="button"
          @click="handleTestEmail"
          :disabled="!canTestEmail"
          class="ml-4 inline-flex items-center gap-2 rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-gray-600 dark:text-gray-100 dark:ring-gray-500 dark:hover:bg-gray-500">
          <OIcon
            v-if="isTesting"
            collection="heroicons"
            name="arrow-path"
            class="size-4 animate-spin"
            aria-hidden="true" />
          <OIcon
            v-else
            collection="heroicons"
            name="paper-airplane"
            class="size-4"
            aria-hidden="true" />
          {{ isTesting ? t('web.COMMON.processing') : t('web.domains.email.send_test') }}
        </button>
      </div>

      <!-- Test Result -->
      <div v-if="testResult || testError" class="mt-4">
        <!-- Success -->
        <div
          v-if="testResult?.success"
          role="status"
          aria-live="polite"
          class="rounded-md bg-green-50 p-4 dark:bg-green-900/20">
          <div class="flex">
            <OIcon
              collection="heroicons"
              name="check-circle-solid"
              class="size-5 text-green-400"
              aria-hidden="true" />
            <div class="ml-3">
              <h5 class="text-sm font-medium text-green-800 dark:text-green-200">
                {{ testResult.message }}
              </h5>
              <p v-if="testResult.details?.sent_to" class="mt-1 text-sm text-green-700 dark:text-green-300">
                {{ t('web.domains.email.test_email_sent_to', { email: testResult.details.sent_to }) }}
              </p>
            </div>
          </div>
        </div>

        <!-- Failure -->
        <div
          v-else-if="testResult && !testResult.success"
          role="alert"
          aria-live="assertive"
          class="rounded-md bg-red-50 p-4 dark:bg-red-900/20">
          <div class="flex">
            <OIcon
              collection="heroicons"
              name="x-circle-solid"
              class="size-5 text-red-400"
              aria-hidden="true" />
            <div class="ml-3">
              <h5 class="text-sm font-medium text-red-800 dark:text-red-200">
                {{ testResult.message }}
              </h5>
              <p v-if="testResult.details?.description" class="mt-2 text-sm text-red-700 dark:text-red-300">
                {{ testResult.details.description }}
              </p>
            </div>
          </div>
        </div>

        <!-- Error (exception) -->
        <div
          v-else-if="testError"
          class="rounded-md bg-red-50 p-4 dark:bg-red-900/20">
          <div class="flex">
            <OIcon
              collection="heroicons"
              name="exclamation-triangle-solid"
              class="size-5 text-red-400"
              aria-hidden="true" />
            <div class="ml-3">
              <p class="text-sm font-medium text-red-800 dark:text-red-200">
                {{ testError }}
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Enabled Toggle -->
    <div class="flex items-center justify-between rounded-lg border border-gray-200 bg-gray-50 p-4 dark:border-gray-700 dark:bg-gray-700/50">
      <div>
        <label
          for="email-enabled"
          class="text-sm font-medium text-gray-900 dark:text-white">
          {{ t('web.domains.enabled') }}
        </label>
        <p
          id="email-enabled-hint"
          class="mt-1 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.domains.email.config_description') }}
        </p>
      </div>
      <button
        id="email-enabled"
        type="button"
        role="switch"
        :aria-checked="localForm.enabled"
        aria-describedby="email-enabled-hint"
        @click="updateField('enabled', !localForm.enabled)"
        :class="[
          'relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:focus:ring-offset-gray-800',
          localForm.enabled ? 'bg-brand-600' : 'bg-gray-200 dark:bg-gray-600',
        ]">
        <span class="sr-only">{{ t('web.domains.enabled') }}</span>
        <span
          :class="[
            'pointer-events-none relative inline-block size-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out',
            localForm.enabled ? 'translate-x-5' : 'translate-x-0',
          ]">
          <span
            :class="[
              'absolute inset-0 flex h-full w-full items-center justify-center transition-opacity',
              localForm.enabled ? 'opacity-0 duration-100 ease-out' : 'opacity-100 duration-200 ease-in',
            ]"
            aria-hidden="true">
            <OIcon
              collection="heroicons"
              name="x-mark"
              class="size-3 text-gray-400" />
          </span>
          <span
            :class="[
              'absolute inset-0 flex h-full w-full items-center justify-center transition-opacity',
              localForm.enabled ? 'opacity-100 duration-200 ease-in' : 'opacity-0 duration-100 ease-out',
            ]"
            aria-hidden="true">
            <OIcon
              collection="heroicons"
              name="check"
              class="size-3 text-brand-600" />
          </span>
        </span>
      </button>
    </div>

    <!-- Provider indicator -->
    <p
      v-if="providerDisplayName"
      class="text-center text-xs text-gray-400 dark:text-gray-500">
      {{ t('web.domains.email.delivered_via', { provider: providerDisplayName }) }}
    </p>

    <!-- Action Buttons -->
    <div class="flex items-center justify-between border-t border-gray-200 pt-6 dark:border-gray-700">
      <!-- Left: Delete + Discard -->
      <div class="flex items-center gap-3">
        <!-- Delete button (only when editing existing config) -->
        <template v-if="isConfigured && !showDeleteConfirm">
          <button
            type="button"
            @click="showDeleteConfirm = true"
            :disabled="isDeleting || isSaving"
            class="inline-flex items-center gap-2 rounded-md bg-white px-3 py-2 text-sm font-semibold text-red-600 shadow-sm ring-1 ring-inset ring-red-300 hover:bg-red-50 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-gray-700 dark:text-red-400 dark:ring-red-700 dark:hover:bg-red-900/20">
            <OIcon
              collection="heroicons"
              name="trash"
              class="size-4"
              aria-hidden="true" />
            {{ t('web.COMMON.remove') }}
          </button>
        </template>

        <!-- Delete confirmation -->
        <div v-if="showDeleteConfirm" class="flex items-center gap-2">
          <span class="text-sm text-gray-600 dark:text-gray-400">
            {{ t('web.domains.are_you_sure_you_want_to_remove_this_domain') }}
          </span>
          <button
            type="button"
            @click="handleDelete"
            :disabled="isDeleting"
            class="inline-flex items-center rounded-md bg-red-600 px-3 py-1.5 text-sm font-semibold text-white shadow-sm hover:bg-red-500 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-red-500 dark:hover:bg-red-400">
            {{ isDeleting ? t('web.COMMON.processing') : t('web.COMMON.yes_delete') }}
          </button>
          <button
            type="button"
            @click="showDeleteConfirm = false"
            :disabled="isDeleting"
            class="inline-flex items-center rounded-md bg-white px-3 py-1.5 text-sm font-semibold text-gray-700 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-gray-700 dark:text-gray-200 dark:ring-gray-600 dark:hover:bg-gray-600">
            {{ t('web.COMMON.word_cancel') }}
          </button>
        </div>

        <!-- Discard button -->
        <button
          v-if="hasUnsavedChanges && !showDeleteConfirm"
          type="button"
          @click="emit('discard')"
          :disabled="isSaving"
          class="inline-flex items-center gap-2 rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-700 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-gray-700 dark:text-gray-200 dark:ring-gray-600 dark:hover:bg-gray-600">
          {{ t('web.domains.email.discard_changes') }}
        </button>
      </div>

      <!-- Right: Save -->
      <button
        type="submit"
        :disabled="!isFormValid || isSaving || isDeleting || !hasUnsavedChanges"
        class="inline-flex items-center gap-2 rounded-md bg-brand-600 px-4 py-2 font-brand text-sm font-semibold text-white shadow-sm hover:bg-brand-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-brand-500 dark:hover:bg-brand-400">
        <OIcon
          v-if="isSaving"
          collection="heroicons"
          name="arrow-path"
          class="size-4 animate-spin"
          aria-hidden="true" />
        <span v-if="isSaving">{{ t('web.COMMON.saving') }}</span>
        <span v-else>{{ t('web.domains.email.save_changes') }}</span>
      </button>
    </div>
  </form>

  <!-- Live region for status announcements -->
  <div
    aria-live="polite"
    aria-atomic="true"
    class="sr-only">
    <span v-if="error">{{ error }}</span>
  </div>
</template>
