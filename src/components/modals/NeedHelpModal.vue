<!-- src/components/modals/NeedHelpModal.vue -->

<script setup lang="ts">
  import OIcon from '@/components/icons/OIcon.vue';
  import {
    Dialog,
    DialogPanel,
    DialogTitle,
    TransitionChild,
    TransitionRoot,
  } from '@headlessui/vue';
  import { ref } from 'vue';
  const showHelp = ref(false);

  interface Props {};

  defineProps<Props>();
</script>

<template>
  <div>
    <button
      type="button"
      @click="showHelp = !showHelp"
      class="flex items-center gap-2 rounded-md p-1
        text-sm text-gray-500 hover:text-gray-700
        focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2
        dark:hover:text-gray-300">
      <OIcon
        collection="mdi"
        name="information"
        class="size-5"
        aria-hidden="true" />
      <span>{{ $t('web.LABELS.need_help') }}</span>
    </button>

    <TransitionRoot
      appear
      :show="showHelp"
      as="template">
      <Dialog
        as="div"
        @close="showHelp = false"
        class="relative z-50">
        <!-- Backdrop -->
        <TransitionChild
          enter="ease-out duration-300"
          enter-from="opacity-0"
          enter-to="opacity-100"
          leave="ease-in duration-200"
          leave-from="opacity-100"
          leave-to="opacity-0">
          <div class="fixed inset-0 bg-black/25"></div>
        </TransitionChild>

        <!-- Content -->
        <div class="fixed inset-0 overflow-y-auto">
          <div class="flex min-h-full items-center justify-center p-4">
            <TransitionChild
              enter="ease-out duration-300"
              enter-from="opacity-0 scale-95"
              enter-to="opacity-100 scale-100"
              leave="ease-in duration-200"
              leave-from="opacity-100 scale-100"
              leave-to="opacity-0 scale-95">
              <DialogPanel
                class="w-full max-w-md transform overflow-hidden rounded-2xl bg-white p-6 dark:bg-gray-800">
                <!-- Header with close button -->
                <div class="flex justify-between items-center mb-4">
                  <DialogTitle
                    class="text-lg font-medium text-gray-900 dark:text-gray-100">
                    {{ $t('web.LABELS.help_section') }}
                  </DialogTitle>
                  <button
                    type="button"
                    @click="showHelp = false"
                    class="rounded-md text-gray-400 hover:text-gray-500 focus:outline-none focus:ring-2 focus:ring-brand-500">
                    <span class="sr-only">{{ $t('web.LABELS.close') }}</span>
                    <OIcon
                      collection="mdi"
                      name="close"
                      class="h-6 w-6"
                      aria-hidden="true" />
                  </button>
                </div>

                <!-- Content -->
                <slot name="content">
                  {{ $t('help-content-goes-here') }}
                </slot>

                <!-- Footer with close button -->
                <div class="mt-6 flex justify-end">
                  <button
                    type="button"
                    @click="showHelp = false"
                    class="inline-flex justify-center rounded-md border border-transparent bg-brand-100 px-4 py-2 text-sm font-medium text-brand-900 hover:bg-brand-200 focus:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 focus-visible:ring-offset-2">
                    {{ $t('web.LABELS.close') }}
                  </button>
                </div>
              </DialogPanel>
            </TransitionChild>
          </div>
        </div>
      </Dialog>
    </TransitionRoot>
  </div>
</template>
