<!-- src/apps/workspace/components/domains/PrivacyDefaultsModal.vue -->

<script setup lang="ts">
  import { computed, ref, watch } from 'vue';
  import { useI18n } from 'vue-i18n';
  import { z } from 'zod';
  import {
    Dialog,
    DialogPanel,
    DialogTitle,
    TransitionChild,
    TransitionRoot,
  } from '@headlessui/vue';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import type { BrandSettings } from '@/schemas/models';
  import { usePrivacyOptions } from '@/shared/composables/usePrivacyOptions';

  const { t } = useI18n();

  const props = defineProps<{
    isOpen: boolean;
    brandSettings: BrandSettings;
  }>();

  const emit = defineEmits<{
    (e: 'close'): void;
    (e: 'save', settings: Partial<BrandSettings>): Promise<void>;
  }>();

  const saveError = ref<string | null>(null);

  // Form validation schema
  const privacyDefaultsSchema = z.object({
    default_ttl: z
      .number()
      .int()
      .positive()
      .nullable()
      .optional(),
    passphrase_required: z.boolean().default(false),
    notify_enabled: z.boolean().default(false),
  });

  type PrivacyDefaults = z.infer<typeof privacyDefaultsSchema>;

  // Local form state
  const formData = ref<PrivacyDefaults>({
    default_ttl: null,
    passphrase_required: false,
    notify_enabled: false,
  });

  const formErrors = ref<Record<string, string>>({});
  const isSaving = ref(false);

  // Get lifetime options from privacy composable
  const { lifetimeOptions } = usePrivacyOptions();

  // Initialize form when modal opens
  watch(
    () => props.isOpen,
    (isOpen) => {
      if (isOpen) {
        formData.value = {
          default_ttl: props.brandSettings.default_ttl ?? null,
          passphrase_required: props.brandSettings.passphrase_required ?? false,
          notify_enabled: props.brandSettings.notify_enabled ?? false,
        };
        formErrors.value = {};
        saveError.value = null;
      }
    }
  );

  const hasChanges = computed(() => (
      formData.value.default_ttl !== (props.brandSettings.default_ttl ?? null) ||
      formData.value.passphrase_required !==
        (props.brandSettings.passphrase_required ?? false) ||
      formData.value.notify_enabled !== (props.brandSettings.notify_enabled ?? false)
    ));

  const validateForm = (): boolean => {
    try {
      privacyDefaultsSchema.parse(formData.value);
      formErrors.value = {};
      return true;
    } catch (error) {
      if (error instanceof z.ZodError) {
        formErrors.value = error.issues.reduce(
          (acc: Record<string, string>, err) => {
            if (err.path[0]) {
              acc[String(err.path[0])] = err.message;
            }
            return acc;
          },
          {} as Record<string, string>
        );
      }
      return false;
    }
  };

  const handleSave = async () => {
    if (!validateForm()) return;

    isSaving.value = true;
    saveError.value = null;
    try {
      await emit('save', formData.value);
      emit('close');
    } catch (error) {
      // Network or server error - keep modal open so user can retry
      saveError.value =
        error instanceof Error ? error.message : 'Failed to save settings. Please try again.';
    } finally {
      isSaving.value = false;
    }
  };

  const handleCancel = () => {
    emit('close');
  };
</script>

<template>
  <TransitionRoot
    as="template"
    :show="isOpen">
    <Dialog
      class="relative z-50"
      @close="handleCancel">
      <TransitionChild
        as="template"
        enter="ease-out duration-300"
        enter-from="opacity-0"
        enter-to="opacity-100"
        leave="ease-in duration-200"
        leave-from="opacity-100"
        leave-to="opacity-0">
        <div class="fixed inset-0 bg-gray-500/75 transition-opacity dark:bg-gray-900/75"></div>
      </TransitionChild>

      <div class="fixed inset-0 z-10 w-screen overflow-y-auto">
        <div
          class="flex min-h-full items-end justify-center p-4 text-center sm:items-center sm:p-0">
          <TransitionChild
            as="template"
            enter="ease-out duration-300"
            enter-from="opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"
            enter-to="opacity-100 translate-y-0 sm:scale-100"
            leave="ease-in duration-200"
            leave-from="opacity-100 translate-y-0 sm:scale-100"
            leave-to="opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95">
            <DialogPanel
              class="relative overflow-hidden rounded-lg bg-white px-4 pb-4 pt-5 text-left shadow-xl transition-all dark:bg-gray-800 sm:my-8 sm:w-full sm:max-w-lg sm:p-6">
              <!-- Header -->
              <div class="mb-4 flex items-start justify-between">
                <div class="flex items-center gap-3">
                  <div
                    class="flex size-10 shrink-0 items-center justify-center rounded-full bg-brand-100 dark:bg-brand-900/50">
                    <OIcon
                      collection="mdi"
                      name="shield-lock"
                      class="size-5 text-brand-600 dark:text-brand-400"
                      aria-hidden="true" />
                  </div>
                  <DialogTitle
                    as="h3"
                    class="text-lg font-semibold leading-6 text-gray-900 dark:text-gray-100">
                    {{ t('web.domains.privacy_defaults_title') }}
                  </DialogTitle>
                </div>
                <button
                  type="button"
                  class="rounded-md text-gray-400 hover:text-gray-500 focus:outline-none focus:ring-2 focus:ring-brand-500 dark:text-gray-500 dark:hover:text-gray-400"
                  @click="handleCancel">
                  <span class="sr-only">{{ t('web.LABELS.close') }}</span>
                  <OIcon
                    collection="mdi"
                    name="close"
                    class="size-5"
                    aria-hidden="true" />
                </button>
              </div>

              <!-- Description -->
              <p class="mb-6 text-sm text-gray-600 dark:text-gray-400">
                {{ t('web.domains.privacy_defaults_description') }}
              </p>

              <!-- Form -->
              <form
                @submit.prevent="handleSave"
                class="space-y-6">
                <!-- Default TTL -->
                <div>
                  <label
                    for="default_ttl"
                    class="block text-sm font-medium text-gray-900 dark:text-gray-100">
                    {{ t('web.domains.default_ttl_label') }}
                  </label>
                  <select
                    id="default_ttl"
                    v-model="formData.default_ttl"
                    class="mt-2 block w-full rounded-md border-gray-300 shadow-sm focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-700 dark:text-gray-100 sm:text-sm">
                    <option :value="null">
                      {{ t('web.domains.use_global_default') }}
                    </option>
                    <option
                      v-for="option in lifetimeOptions"
                      :key="option.value"
                      :value="option.value">
                      {{ option.label }}
                    </option>
                  </select>
                  <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
                    {{ t('web.domains.default_ttl_hint') }}
                  </p>
                  <p
                    v-if="formErrors.default_ttl"
                    class="mt-1 text-xs text-red-600 dark:text-red-400">
                    {{ formErrors.default_ttl }}
                  </p>
                </div>

                <!-- Passphrase Required -->
                <div class="flex items-start">
                  <div class="flex h-6 items-center">
                    <input
                      id="passphrase_required"
                      v-model="formData.passphrase_required"
                      type="checkbox"
                      class="size-4 rounded border-gray-300 text-brand-600 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-700" />
                  </div>
                  <div class="ml-3">
                    <label
                      for="passphrase_required"
                      class="text-sm font-medium text-gray-900 dark:text-gray-100">
                      {{ t('web.domains.passphrase_required_label') }}
                    </label>
                    <p class="text-xs text-gray-500 dark:text-gray-400">
                      {{ t('web.domains.passphrase_required_hint') }}
                    </p>
                  </div>
                </div>

                <!-- Notify Enabled -->
                <div class="flex items-start">
                  <div class="flex h-6 items-center">
                    <input
                      id="notify_enabled"
                      v-model="formData.notify_enabled"
                      type="checkbox"
                      class="size-4 rounded border-gray-300 text-brand-600 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-700" />
                  </div>
                  <div class="ml-3">
                    <label
                      for="notify_enabled"
                      class="text-sm font-medium text-gray-900 dark:text-gray-100">
                      {{ t('web.domains.notify_enabled_label') }}
                    </label>
                    <p class="text-xs text-gray-500 dark:text-gray-400">
                      {{ t('web.domains.notify_enabled_hint') }}
                    </p>
                  </div>
                </div>

                <!-- Error Message -->
                <div
                  v-if="saveError"
                  class="rounded-md bg-red-50 p-3 dark:bg-red-900/30">
                  <div class="flex items-center gap-2">
                    <OIcon
                      collection="mdi"
                      name="alert-circle-outline"
                      class="size-5 text-red-500 dark:text-red-400"
                      aria-hidden="true" />
                    <p class="text-sm text-red-700 dark:text-red-300">
                      {{ saveError }}
                    </p>
                  </div>
                </div>

                <!-- Actions -->
                <div class="mt-6 flex flex-col-reverse gap-3 sm:flex-row sm:justify-end">
                  <button
                    type="button"
                    class="inline-flex w-full justify-center rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 dark:bg-gray-700 dark:text-gray-100 dark:ring-gray-600 dark:hover:bg-gray-600 sm:w-auto"
                    @click="handleCancel">
                    {{ t('web.COMMON.word_cancel') }}
                  </button>
                  <button
                    type="submit"
                    :disabled="!hasChanges || isSaving"
                    class="inline-flex w-full justify-center rounded-md bg-brand-600 px-3 py-2 font-brand text-sm font-semibold text-white shadow-sm hover:bg-brand-500 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 dark:focus:ring-offset-gray-800 sm:w-auto">
                    <OIcon
                      v-if="isSaving"
                      collection="mdi"
                      name="loading"
                      class="-ml-0.5 mr-2 size-4 animate-spin" />
                    <OIcon
                      v-else
                      collection="mdi"
                      name="content-save"
                      class="-ml-0.5 mr-2 size-4" />
                    {{ isSaving ? t('web.LABELS.saving') : t('web.LABELS.save') }}
                  </button>
                </div>
              </form>
            </DialogPanel>
          </TransitionChild>
        </div>
      </div>
    </Dialog>
  </TransitionRoot>
</template>
