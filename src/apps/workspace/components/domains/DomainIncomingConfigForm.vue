<!-- src/apps/workspace/components/domains/DomainIncomingConfigForm.vue -->

<script setup lang="ts">
/**
 * Domain Incoming Secrets Configuration Form
 *
 * Manages recipients for incoming secrets on a domain.
 *
 * Key design: dual-state architecture due to email hashing on server.
 * - serverState.recipients: read-only, hashed (digest + display_name)
 * - formState.recipients: editable, plaintext (email + name) for NEW additions
 *
 * After save, formState is cleared because we cannot recover plaintext from hashes.
 * The UI displays both lists: existing (server) as read-only + pending (form) as editable.
 */
import { useI18n } from 'vue-i18n';
import { computed, ref } from 'vue';
import { z } from 'zod';
import OIcon from '@/shared/components/icons/OIcon.vue';
import BasicFormAlerts from '@/shared/components/forms/BasicFormAlerts.vue';
import type { IncomingConfigFormState, IncomingConfigServerState } from '@/shared/composables/useIncomingConfig';

const emailSchema = z.string().email();

interface Props {
  formState: IncomingConfigFormState;
  serverState: IncomingConfigServerState;
  isLoading?: boolean;
  isSaving?: boolean;
  isDeleting?: boolean;
  hasUnsavedChanges?: boolean;
  maxRecipients?: number;
  error?: string;
}

const props = withDefaults(defineProps<Props>(), {
  isLoading: false,
  isSaving: false,
  isDeleting: false,
  hasUnsavedChanges: false,
  maxRecipients: 20,
});

const emit = defineEmits<{
  (e: 'update:formState', value: IncomingConfigFormState): void;
  (e: 'save'): void;
  (e: 'delete'): void;
  (e: 'discard'): void;
  (e: 'addRecipient', email: string, name?: string): void;
  (e: 'removeRecipient', index: number): void;
}>();

const { t } = useI18n();

// ---------------------------------------------------------------------------
// Local form state for adding new recipients
// ---------------------------------------------------------------------------

const newEmail = ref('');
const newName = ref('');
const emailError = ref<string | null>(null);

// ---------------------------------------------------------------------------
// Computed
// ---------------------------------------------------------------------------

/** Total recipients (existing on server + pending in form). */
const totalRecipientCount = computed(() =>
  props.serverState.recipients.length + props.formState.recipients.length
);

/** Whether more recipients can be added. */
const canAddMore = computed(() => totalRecipientCount.value < props.maxRecipients);

/** Whether the add form is valid. */
const isAddFormValid = computed(() => {
  const email = newEmail.value.trim();
  if (!email) return false;
  return emailSchema.safeParse(email).success;
});

/** Whether there are any recipients at all. */
const hasAnyRecipients = computed(() =>
  props.serverState.recipients.length > 0 || props.formState.recipients.length > 0
);

/** Whether there are pending recipients to save. */
const hasPendingRecipients = computed(() => props.formState.recipients.length > 0);

/** Whether saving will replace existing recipients on the server. */
const willReplaceExisting = computed(() => props.serverState.recipients.length > 0);

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

function validateEmail(email: string): string | null {
  const trimmed = email.trim();

  if (!trimmed) {
    return t('web.domains.incoming.validation_email_required');
  }

  if (!emailSchema.safeParse(trimmed).success) {
    return t('web.domains.incoming.validation_invalid_email');
  }

  // Check for duplicates in pending recipients
  const normalizedEmail = trimmed.toLowerCase();
  const isDuplicateInForm = props.formState.recipients.some(
    (r) => r.email.toLowerCase() === normalizedEmail
  );

  if (isDuplicateInForm) {
    return t('web.domains.incoming.validation_duplicate_email');
  }

  return null;
}

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

function handleAddRecipient(): void {
  const email = newEmail.value.trim();
  const name = newName.value.trim() || undefined;

  // Validate
  const validationError = validateEmail(email);
  if (validationError) {
    emailError.value = validationError;
    return;
  }

  if (!canAddMore.value) {
    emailError.value = t('web.domains.incoming.validation_max_recipients', { max: props.maxRecipients });
    return;
  }

  // Emit the add event
  emit('addRecipient', email, name);

  // Clear the form
  newEmail.value = '';
  newName.value = '';
  emailError.value = null;
}

function handleRemovePending(index: number): void {
  emit('removeRecipient', index);
}

function handleSave(): void {
  if (!hasPendingRecipients.value || props.isSaving) return;

  if (willReplaceExisting.value) {
    const confirmed = window.confirm(
      t('web.domains.incoming.save_will_replace_confirmation')
    );
    if (!confirmed) return;
  }

  emit('save');
}

function handleEmailInput(event: Event): void {
  const target = event.target as HTMLInputElement;
  newEmail.value = target.value;
  // Clear error on input
  if (emailError.value) {
    emailError.value = null;
  }
}

// Delete confirmation
const showDeleteConfirm = ref(false);

function handleDelete(): void {
  emit('delete');
  showDeleteConfirm.value = false;
}
</script>

<template>
  <form
    @submit.prevent="handleSave"
    class="space-y-6">
    <!-- Alerts -->
    <BasicFormAlerts
      v-if="error"
      :error="error" />

    <!-- Recipients Section Header -->
    <div>
      <h3 class="text-base font-semibold text-gray-900 dark:text-white">
        {{ t('web.domains.incoming.recipients_title') }}
      </h3>
      <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.domains.incoming.recipients_description') }}
      </p>
    </div>

    <!-- Existing Recipients (from server, read-only) -->
    <div
      v-if="serverState.recipients.length > 0"
      class="space-y-2">
      <h4 class="text-sm font-medium text-gray-700 dark:text-gray-300">
        {{ t('web.domains.incoming.badge_configured') }}
        <span class="ml-1 text-gray-500 dark:text-gray-400">
          ({{ serverState.recipients.length }})
        </span>
      </h4>
      <ul class="divide-y divide-gray-200 rounded-md border border-gray-200 dark:divide-gray-700 dark:border-gray-700">
        <li
          v-for="recipient in serverState.recipients"
          :key="recipient.digest"
          class="flex items-center justify-between px-4 py-3">
          <div class="flex items-center gap-3">
            <div class="flex size-8 items-center justify-center rounded-full bg-brand-100 dark:bg-brand-900/30">
              <OIcon
                collection="heroicons"
                name="user"
                class="size-4 text-brand-600 dark:text-brand-400"
                aria-hidden="true" />
            </div>
            <div>
              <p class="text-sm font-medium text-gray-900 dark:text-white">
                {{ recipient.display_name || t('web.domains.incoming.name_placeholder') }}
              </p>
              <p class="text-xs text-gray-500 dark:text-gray-400">
                {{ t('web.domains.verified') }}
              </p>
            </div>
          </div>
          <!-- Individual removal of existing recipients requires re-adding all others.
               Since emails are hashed after save, we cannot reconstruct the list.
               Users should use "Delete All" to clear recipients and re-add. -->
        </li>
      </ul>
    </div>

    <!-- Pending Recipients (in form, not yet saved) -->
    <div
      v-if="formState.recipients.length > 0"
      class="space-y-2">
      <h4 class="text-sm font-medium text-gray-700 dark:text-gray-300">
        {{ t('web.domains.pending_verification') }}
        <span class="ml-1 text-gray-500 dark:text-gray-400">
          ({{ formState.recipients.length }})
        </span>
      </h4>
      <ul class="divide-y divide-gray-200 rounded-md border border-amber-300 bg-amber-50 dark:divide-gray-700 dark:border-amber-700 dark:bg-amber-900/20">
        <li
          v-for="(recipient, index) in formState.recipients"
          :key="`pending-${index}`"
          class="flex items-center justify-between px-4 py-3">
          <div class="flex items-center gap-3">
            <div class="flex size-8 items-center justify-center rounded-full bg-amber-100 dark:bg-amber-900/30">
              <OIcon
                collection="heroicons"
                name="clock"
                class="size-4 text-amber-600 dark:text-amber-400"
                aria-hidden="true" />
            </div>
            <div>
              <p class="text-sm font-medium text-gray-900 dark:text-white">
                {{ recipient.name || recipient.email }}
              </p>
              <p class="text-xs text-gray-500 dark:text-gray-400">
                {{ recipient.email }}
              </p>
            </div>
          </div>
          <button
            type="button"
            @click="handleRemovePending(index)"
            :disabled="isSaving"
            class="inline-flex items-center gap-1 rounded px-2 py-1 text-sm text-red-600 hover:bg-red-50 disabled:cursor-not-allowed disabled:opacity-50 dark:text-red-400 dark:hover:bg-red-900/20"
            :aria-label="t('web.domains.incoming.remove_recipient')">
            <OIcon
              collection="heroicons"
              name="x-mark"
              class="size-4"
              aria-hidden="true" />
            <span class="sr-only sm:not-sr-only">
              {{ t('web.domains.incoming.remove_recipient') }}
            </span>
          </button>
        </li>
      </ul>
    </div>

    <!-- Empty State -->
    <div
      v-if="!hasAnyRecipients && !isLoading"
      class="rounded-lg border-2 border-dashed border-gray-300 p-6 text-center dark:border-gray-600">
      <OIcon
        collection="heroicons"
        name="inbox"
        class="mx-auto size-12 text-gray-400 dark:text-gray-500"
        aria-hidden="true" />
      <h3 class="mt-2 text-sm font-semibold text-gray-900 dark:text-white">
        {{ t('web.domains.incoming.empty_state') }}
      </h3>
      <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.domains.incoming.empty_state_description') }}
      </p>
    </div>

    <!-- Add Recipient Form -->
    <div
      v-if="canAddMore"
      class="rounded-lg border border-gray-200 bg-gray-50 p-4 dark:border-gray-700 dark:bg-gray-700/50">
      <h4 class="mb-4 text-sm font-medium text-gray-900 dark:text-white">
        {{ t('web.domains.incoming.add_recipient') }}
      </h4>

      <div class="grid gap-4 sm:grid-cols-2">
        <!-- Email Input -->
        <div>
          <label
            for="recipient-email"
            class="block text-sm font-medium text-gray-700 dark:text-gray-300">
            {{ t('web.domains.incoming.email_label') }}
            <span class="text-red-500" aria-hidden="true">*</span>
          </label>
          <input
            id="recipient-email"
            :value="newEmail"
            type="email"
            required
            autocomplete="off"
            :placeholder="t('web.domains.incoming.email_placeholder')"
            :aria-invalid="!!emailError"
            :aria-describedby="emailError ? 'email-error' : undefined"
            class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-400 sm:text-sm"
            :class="{ 'border-red-300 dark:border-red-600': emailError }"
            @input="handleEmailInput"
            @keydown.enter.prevent="handleAddRecipient" />
          <p
            v-if="emailError"
            id="email-error"
            class="mt-1 text-sm text-red-600 dark:text-red-400">
            {{ emailError }}
          </p>
        </div>

        <!-- Name Input -->
        <div>
          <label
            for="recipient-name"
            class="block text-sm font-medium text-gray-700 dark:text-gray-300">
            {{ t('web.domains.incoming.name_label') }}
          </label>
          <input
            id="recipient-name"
            v-model="newName"
            type="text"
            maxlength="100"
            autocomplete="off"
            :placeholder="t('web.domains.incoming.name_placeholder')"
            class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-400 sm:text-sm"
            @keydown.enter.prevent="handleAddRecipient" />
        </div>
      </div>

      <!-- Add Button -->
      <div class="mt-4 flex justify-end">
        <button
          type="button"
          @click="handleAddRecipient"
          :disabled="!isAddFormValid || isSaving"
          class="inline-flex items-center gap-2 rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-gray-600 dark:text-white dark:ring-gray-500 dark:hover:bg-gray-500">
          <OIcon
            collection="heroicons"
            name="plus"
            class="size-4"
            aria-hidden="true" />
          {{ t('web.domains.incoming.add_recipient') }}
        </button>
      </div>
    </div>

    <!-- Max Recipients Warning -->
    <p
      v-if="!canAddMore"
      class="text-sm text-amber-600 dark:text-amber-400">
      {{ t('web.domains.incoming.validation_max_recipients', { max: maxRecipients }) }}
    </p>

    <!-- Recipient Count -->
    <p
      v-if="hasAnyRecipients"
      class="text-sm text-gray-500 dark:text-gray-400">
      {{ totalRecipientCount }} / {{ maxRecipients }}
      {{ t('web.domains.incoming.recipients_title').toLowerCase() }}
    </p>

    <!-- Action Buttons -->
    <div class="flex items-center justify-between border-t border-gray-200 pt-6 dark:border-gray-700">
      <!-- Left: Delete + Discard -->
      <div class="flex items-center gap-3">
        <!-- Delete button (only when there are existing recipients) -->
        <template v-if="serverState.recipients.length > 0 && !showDeleteConfirm">
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
            {{ t('web.domains.incoming.delete_all_recipients') }}
          </button>
        </template>

        <!-- Delete confirmation -->
        <div v-if="showDeleteConfirm" class="flex items-center gap-2">
          <span class="text-sm text-gray-600 dark:text-gray-400">
            {{ t('web.domains.incoming.remove_all_confirmation') }}
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
          {{ t('web.domains.incoming.discard_changes') }}
        </button>
      </div>

      <!-- Right: Save -->
      <button
        type="submit"
        :disabled="!hasPendingRecipients || isSaving || isDeleting"
        class="inline-flex items-center gap-2 rounded-md bg-brand-600 px-4 py-2 font-brand text-sm font-semibold text-white shadow-sm hover:bg-brand-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-brand-500 dark:hover:bg-brand-400">
        <OIcon
          v-if="isSaving"
          collection="heroicons"
          name="arrow-path"
          class="size-4 animate-spin"
          aria-hidden="true" />
        <span v-if="isSaving">{{ t('web.COMMON.saving') }}</span>
        <span v-else>{{ t('web.domains.incoming.save_changes') }}</span>
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
