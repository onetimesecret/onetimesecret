<!-- src/apps/admin/components/kit/DetailDrawer.vue -->

<script setup lang="ts">
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import {
    Dialog,
    DialogPanel,
    DialogTitle,
    TransitionChild,
    TransitionRoot,
  } from '@headlessui/vue';
  import { useI18n } from 'vue-i18n';

  /**
   * Right-hand slide-over for inspecting a single record (ticket #11).
   *
   * Built on headlessui `Dialog` for focus-trapping, Escape-to-close and scroll
   * locking — the same primitives the shared modals use — so it stays accessible
   * without re-implementing any of it. The body is a default slot; `header` and
   * `footer` slots let a view add a sticky title area / action bar. Closing (via
   * the button, the backdrop or Escape) emits both `update:open` (for
   * `v-model:open`) and `close`.
   */
  withDefaults(
    defineProps<{
      /** Whether the drawer is shown (use with `v-model:open`). */
      open: boolean;
      /** Title rendered in the sticky header (already translated). */
      title?: string;
      /** Optional secondary line under the title. */
      subtitle?: string;
      /** Panel width utility class. Defaults to a comfortable reading width. */
      widthClass?: string;
      /** Test id applied to the panel. */
      testid?: string;
    }>(),
    {
      title: undefined,
      subtitle: undefined,
      widthClass: 'max-w-md',
      testid: undefined,
    }
  );

  const emit = defineEmits<{
    'update:open': [value: boolean];
    close: [];
  }>();

  const { t } = useI18n();

  function close(): void {
    emit('update:open', false);
    emit('close');
  }
</script>

<template>
  <TransitionRoot
    as="template"
    :show="open">
    <Dialog
      class="relative z-50"
      @close="close">
      <!-- Backdrop -->
      <TransitionChild
        as="template"
        enter="ease-out duration-300"
        enter-from="opacity-0"
        enter-to="opacity-100"
        leave="ease-in duration-200"
        leave-from="opacity-100"
        leave-to="opacity-0">
        <div
          class="fixed inset-0 bg-gray-500/75 transition-opacity dark:bg-gray-900/80"
          aria-hidden="true"></div>
      </TransitionChild>

      <div class="fixed inset-0 overflow-hidden">
        <div class="absolute inset-0 overflow-hidden">
          <div class="pointer-events-none fixed inset-y-0 right-0 flex max-w-full pl-10">
            <TransitionChild
              as="template"
              enter="transform transition ease-in-out duration-300"
              enter-from="translate-x-full"
              enter-to="translate-x-0"
              leave="transform transition ease-in-out duration-200"
              leave-from="translate-x-0"
              leave-to="translate-x-full">
              <DialogPanel
                :data-testid="testid"
                :class="widthClass"
                class="pointer-events-auto flex h-full w-screen flex-col bg-white shadow-xl dark:bg-gray-900">
                <!-- Sticky header. The subtitle is treated as key material
                     (public id / identifier) — monospace + tabular, the
                     console's redaction-field convention for verifiable values. -->
                <div
                  class="flex items-start justify-between gap-4 border-b-2 border-gray-900 px-4 py-4 sm:px-6 dark:border-gray-100">
                  <div class="min-w-0">
                    <slot name="header">
                      <DialogTitle
                        v-if="title"
                        as="h2"
                        class="truncate font-brand text-lg font-bold text-gray-900 dark:text-white">
                        {{ title }}
                      </DialogTitle>
                      <p
                        v-if="subtitle"
                        class="mt-1 truncate font-mono text-xs text-gray-500 tabular-nums dark:text-gray-400">
                        {{ subtitle }}
                      </p>
                    </slot>
                  </div>
                  <button
                    type="button"
                    class="-m-2 shrink-0 rounded-md p-2 text-gray-400 hover:text-gray-600 focus:ring-2 focus:ring-brand-500 focus:outline-none dark:hover:text-gray-200"
                    :aria-label="t('web.LABELS.close')"
                    @click="close">
                    <OIcon
                      collection="heroicons"
                      name="x-mark"
                      size="6" />
                  </button>
                </div>

                <!-- Scrollable body -->
                <div class="min-h-0 flex-1 overflow-y-auto px-4 py-5 sm:px-6">
                  <slot></slot>
                </div>

                <!-- Optional sticky footer -->
                <div
                  v-if="$slots.footer"
                  class="border-t border-gray-200 px-4 py-4 sm:px-6 dark:border-gray-800">
                  <slot name="footer"></slot>
                </div>
              </DialogPanel>
            </TransitionChild>
          </div>
        </div>
      </div>
    </Dialog>
  </TransitionRoot>
</template>
