<!-- src/apps/workspace/components/domains/SsoCredentialsModal.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import {
    Dialog,
    DialogPanel,
    DialogTitle,
    TransitionChild,
    TransitionRoot,
  } from '@headlessui/vue';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import DomainSsoConfigForm from '@/apps/workspace/components/domains/DomainSsoConfigForm.vue';
  import type { SsoConfigFormState } from '@/shared/composables/useSsoConfig';
  import type { CustomDomainSsoConfig } from '@/schemas/shapes/domains/sso-config';
  import type { TestSsoConnectionResponse } from '@/services/sso.service';

  const { t } = useI18n();

  defineProps<{
    isOpen: boolean;
    domainExtId: string;
    domainHost: string;
    orgId: string;
    formState: SsoConfigFormState;
    ssoConfig: CustomDomainSsoConfig | null;
    isLoading: boolean;
    isSaving: boolean;
    isDeleting: boolean;
    isTesting: boolean;
    hasUnsavedChanges: boolean;
    isConfigured: boolean;
    clientSecretMasked: string | null;
    testResult: TestSsoConnectionResponse | null;
    testError: string;
  }>();

  const emit = defineEmits<{
    (e: 'close'): void;
    (e: 'save'): void;
    (e: 'delete'): void;
    (e: 'test'): void;
    (e: 'discard'): void;
    (e: 'update:formState', value: SsoConfigFormState): void;
  }>();

  const handleClose = () => {
    emit('close');
  };
</script>

<template>
  <TransitionRoot
    as="template"
    :show="isOpen">
    <Dialog
      class="relative z-50"
      @close="handleClose">
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
              class="relative overflow-hidden rounded-lg bg-white px-4 pb-4 pt-5 text-left shadow-xl transition-all dark:bg-gray-800 sm:my-8 sm:w-full sm:max-w-2xl sm:p-6">
              <!-- Header -->
              <div class="mb-4 flex items-start justify-between">
                <div class="flex items-center gap-3">
                  <div
                    class="flex size-10 shrink-0 items-center justify-center rounded-full bg-brand-100 dark:bg-brand-900/50">
                    <OIcon
                      collection="heroicons"
                      name="shield-check"
                      class="size-5 text-brand-600 dark:text-brand-400"
                      aria-hidden="true" />
                  </div>
                  <DialogTitle
                    as="h3"
                    class="text-lg font-semibold leading-6 text-gray-900 dark:text-gray-100">
                    {{ t('web.domains.sso.title') }}
                  </DialogTitle>
                </div>
                <button
                  type="button"
                  class="rounded-md text-gray-400 hover:text-gray-500 focus:outline-none focus:ring-2 focus:ring-brand-500 dark:text-gray-500 dark:hover:text-gray-400"
                  @click="handleClose">
                  <span class="sr-only">{{ t('web.LABELS.close') }}</span>
                  <OIcon
                    collection="mdi"
                    name="close"
                    class="size-5"
                    aria-hidden="true" />
                </button>
              </div>

              <!-- SSO Config Form -->
              <DomainSsoConfigForm
                :domain-ext-id="domainExtId"
                :org-id="orgId"
                :domain-host="domainHost"
                :form-state="formState"
                @update:form-state="emit('update:formState', $event)"
                :sso-config="ssoConfig"
                :is-loading="isLoading"
                :is-saving="isSaving"
                :is-deleting="isDeleting"
                :is-testing="isTesting"
                :has-unsaved-changes="hasUnsavedChanges"
                :is-configured="isConfigured"
                :client-secret-masked="clientSecretMasked"
                :test-result="testResult"
                :test-error="testError"
                @save="emit('save')"
                @delete="emit('delete')"
                @test="emit('test')"
                @discard="emit('discard')" />
            </DialogPanel>
          </TransitionChild>
        </div>
      </div>
    </Dialog>
  </TransitionRoot>
</template>
