<!-- src/components/modals/SecretLinkTwoStepModal.vue -->

<script setup lang="ts">
  import OIcon from '@/components/icons/OIcon.vue';
  import CopyButton from '@/components/CopyButton.vue';
  import {
    Dialog,
    DialogPanel,
    DialogTitle,
    TransitionChild,
    TransitionRoot,
  } from '@headlessui/vue';
  import { ref, watch, nextTick } from 'vue';
  import { useI18n } from 'vue-i18n';

  const { t } = useI18n();

  interface Props {
    show: boolean;
    shareUrl: string;
    naturalExpiration: string;
    hasPassphrase: boolean;
    metadataKey: string;
    secretShortkey: string;
  }

  const props = defineProps<Props>();
  const emit = defineEmits<{ close: [] }>();

  const modalRef = ref<HTMLDivElement | null>(null);
  const currentStep = ref<1 | 2>(1);
  const detailsId = 'secret-link-details-panel';

  watch(
    () => props.show,
    (newVal) => {
      if (newVal) {
        nextTick(() => {
          const panelElement = modalRef.value;
          if (panelElement instanceof HTMLElement) {
            const firstFocusable = panelElement.querySelector<HTMLElement>(
              'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
            );
            if (firstFocusable) {
              firstFocusable.focus();
            }
          }
        });
      } else {
        currentStep.value = 1;
      }
    }
  );
</script>

<template>
  <TransitionRoot
    appear
    :show="show"
    as="template">
    <Dialog
      as="div"
      @close="emit('close')"
      class="relative z-50"
      role="dialog"
      aria-modal="true"
      aria-labelledby="secret-link-modal-title">
      <TransitionChild
        enter="ease-out duration-300"
        enter-from="opacity-0"
        enter-to="opacity-100"
        leave="ease-in duration-200"
        leave-from="opacity-100"
        leave-to="opacity-0">
        <div class="fixed inset-0 bg-black/50"></div>
      </TransitionChild>

      <div class="fixed inset-0 overflow-y-auto">
        <div class="flex min-h-full items-center justify-center p-4">
          <TransitionChild
            enter="ease-out duration-300"
            enter-from="opacity-0 scale-95"
            enter-to="opacity-100 scale-100"
            leave="ease-in duration-200"
            leave-from="opacity-100 scale-100"
            leave-to="opacity-0 scale-95"
            class="w-full max-w-xl">
            <DialogPanel
              ref="modalRef"
              class="relative overflow-hidden rounded-2xl bg-white dark:bg-gray-800">
              <div class="absolute left-0 top-0 h-1.5 w-full overflow-hidden">
                <div
                  class="size-full animate-gradient-x bg-200%
                    bg-gradient-to-r from-green-400 via-green-500 to-green-400">
                </div>
              </div>

              <button
                type="button"
                @click="emit('close')"
                class="absolute right-3 top-3 rounded-md p-1 text-gray-400 hover:text-gray-500
                  dark:hover:text-gray-300
                  focus:outline-none focus:ring-2 focus:ring-brand-500"
                :aria-label="t('web.LABELS.close')">
                <span class="sr-only">{{ t('web.LABELS.close') }}</span>
                <OIcon
                  collection="mdi"
                  name="close"
                  class="size-6"
                  aria-hidden="true" />
              </button>

              <div class="p-6 pt-8">
                <div class="relative mb-4 pl-7">
                  <OIcon
                    collection="mdi"
                    name="check-circle"
                    class="absolute left-0 top-px size-5 text-green-600 dark:text-green-400"
                    aria-hidden="true" />
                  <DialogTitle
                    id="secret-link-modal-title"
                    class="font-brand text-base uppercase text-gray-900 dark:text-gray-100">
                    {{ t('web.private.created_success') }}
                  </DialogTitle>
                </div>

                <div class="mb-1 flex items-center gap-2 font-mono text-sm tracking-wide text-gray-500">
                  <OIcon
                    collection="material-symbols"
                    name="key-vertical"
                    class="size-4"
                    aria-hidden="true" />
                  <span>{{ secretShortkey }}</span>
                </div>

                <div class="flex items-start gap-3">
                  <div class="min-w-0 grow">
                    <textarea
                      readonly
                      :value="shareUrl"
                      rows="2"
                      class="w-full resize-none rounded-xl
                        border border-gray-200 bg-gray-50 px-3 py-2.5 font-mono text-sm text-gray-900
                        focus:border-brandcomp-500 focus:ring-2 focus:ring-brandcomp-500 focus:outline-none
                        dark:border-gray-700 dark:bg-gray-900 dark:text-gray-100 sm:text-base"
                      :aria-label="t('web.LABELS.secret_link')"></textarea>
                  </div>
                  <div class="shrink-0 pt-2">
                    <CopyButton
                      :text="shareUrl"
                      class="transition-transform hover:scale-105" />
                  </div>
                </div>

                <!-- prettier-ignore-attribute class -->
                <div
                  class="-mx-6 mt-3 border-t border-gray-200
                    bg-gray-50 px-4 py-2.5 dark:border-gray-700 dark:bg-gray-900/50">
                  <div class="flex items-center text-xs text-gray-500 dark:text-gray-400">
                    <OIcon
                      collection="material-symbols"
                      name="shield-outline"
                      class="mr-2 size-4 text-brand-500 dark:text-brand-400"
                      aria-hidden="true" />
                    <span>{{ t('web.COMMON.share_link_securely') }}</span>
                  </div>
                </div>

                <button
                  type="button"
                  @click="currentStep = currentStep === 1 ? 2 : 1"
                  :aria-expanded="currentStep === 2"
                  :aria-controls="detailsId"
                  class="mt-4 inline-flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700
                    focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 rounded-md px-1
                    dark:text-gray-400 dark:hover:text-gray-300">
                  <span>{{ currentStep === 1
                    ? t('web.LABELS.show_details', 'Show details')
                    : t('web.LABELS.hide_details', 'Hide details') }}</span>
                  <OIcon
                    collection="heroicons"
                    :name="currentStep === 1 ? 'chevron-down-20-solid' : 'chevron-up-20-solid'"
                    class="size-4 transition-transform"
                    aria-hidden="true" />
                </button>

                <Transition
                  enter-active-class="transition-all duration-300 ease-out"
                  enter-from-class="max-h-0 opacity-0"
                  enter-to-class="max-h-64 opacity-100"
                  leave-active-class="transition-all duration-200 ease-in"
                  leave-from-class="max-h-64 opacity-100"
                  leave-to-class="max-h-0 opacity-0">
                  <div
                    v-if="currentStep === 2"
                    :id="detailsId"
                    class="overflow-hidden">
                    <div class="mt-3 border-t border-gray-200 pt-3 dark:border-gray-700">
                      <div class="flex flex-wrap items-center gap-3 text-sm text-gray-500 dark:text-gray-400">
                        <span>{{ t('web.LABELS.expires_in', { time: naturalExpiration }) }}</span>
                        <!-- prettier-ignore-attribute class -->
                        <span
                          v-if="hasPassphrase"
                          class="inline-flex items-center gap-1 rounded-full
                            border border-amber-100 bg-amber-50 px-2 py-0.5
                            text-xs font-medium text-amber-600
                            dark:border-amber-800/50 dark:bg-amber-900/30 dark:text-amber-400">
                          <OIcon
                            collection="mdi"
                            name="lock"
                            class="size-3.5" />
                          {{ t('web.LABELS.passphrase_protected') }}
                        </span>
                      </div>

                      <div class="mt-2 flex items-center gap-2 text-sm text-gray-500 dark:text-gray-400">
                        <OIcon
                          collection="heroicons"
                          name="document-text-20-solid"
                          class="size-4"
                          aria-hidden="true" />
                        <a
                          :href="`/receipt/${metadataKey}`"
                          class="text-brand-600 hover:text-brand-700
                            dark:text-brand-400 dark:hover:text-brand-300">
                          {{ t('web.LABELS.view_details', 'View Details') }}
                        </a>
                      </div>
                    </div>
                  </div>
                </Transition>
              </div>
            </DialogPanel>
          </TransitionChild>
        </div>
      </div>
    </Dialog>
  </TransitionRoot>
</template>

<style scoped>
  .animate-gradient-x {
    animation: gradient-x 10s linear infinite;
  }

  @keyframes gradient-x {
    0% {
      background-position: 0% 0;
    }
    100% {
      background-position: 200% 0;
    }
  }
</style>
