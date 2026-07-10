<!-- src/apps/admin/components/kit/AdminModal.vue -->

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
   * General-purpose centred modal for the admin console.
   *
   * The kit already ships two focused dialogs — {@link AdminConfirmDialog} (the
   * typed-confirmation gate) and {@link DetailDrawer} (a read-only slide-over) —
   * but nothing for an interactive *form* modal (pick a record, fill a field).
   * This is that missing primitive: the same headlessui `Dialog` base the other
   * two use (focus-trap, Escape-to-close, scroll-lock, backdrop) with a
   * header/body/footer slot layout and the console's heavy-rule header
   * convention. Content is entirely caller-supplied — this owns chrome and
   * dismissal only, never a submit action.
   *
   * Closing (button, backdrop, or Escape) emits both `update:open` (for
   * `v-model:open`) and `close`. A caller that must block dismissal while a
   * mutation is in flight can pass `:dismissable="false"`.
   */
  withDefaults(
    defineProps<{
      /** Whether the modal is shown (use with `v-model:open`). */
      open: boolean;
      /** Heading rendered in the header (already translated). */
      title?: string;
      /** Optional secondary line under the title (rendered as key material). */
      subtitle?: string;
      /** Panel max-width utility class. */
      widthClass?: string;
      /** When false, backdrop/Escape/close-button do not dismiss (e.g. mid-submit). */
      dismissable?: boolean;
      /** Test id applied to the panel. */
      testid?: string;
    }>(),
    {
      title: undefined,
      subtitle: undefined,
      widthClass: 'max-w-lg',
      dismissable: true,
      testid: undefined,
    }
  );

  const emit = defineEmits<{
    'update:open': [value: boolean];
    close: [];
  }>();

  const { t } = useI18n();

  function requestClose(): void {
    emit('update:open', false);
    emit('close');
  }

  /** headlessui `@close` fires on backdrop/Escape — respect `dismissable`. */
  function onDialogClose(dismissable: boolean): void {
    if (dismissable) requestClose();
  }
</script>

<template>
  <TransitionRoot
    as="template"
    :show="open">
    <Dialog
      class="relative z-50"
      @close="onDialogClose(dismissable)">
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
              :data-testid="testid"
              :class="widthClass"
              class="relative w-full overflow-hidden rounded-lg bg-white text-left shadow-xl transition-all sm:my-8 dark:bg-gray-900">
              <!-- Header: heavy rule + brand title, matching the console header
                   convention. The subtitle is treated as key material (public
                   id / identifier) — monospace + tabular. -->
              <div
                v-if="title || subtitle || $slots.header"
                class="flex items-start justify-between gap-4 border-b-2 border-gray-900 p-4 sm:px-6 dark:border-gray-100">
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
                  @click="requestClose">
                  <OIcon
                    collection="heroicons"
                    name="x-mark"
                    size="6" />
                </button>
              </div>

              <!-- Body -->
              <div class="px-4 py-5 sm:px-6">
                <slot></slot>
              </div>

              <!-- Optional footer (action bar) -->
              <div
                v-if="$slots.footer"
                class="border-t border-gray-200 p-4 sm:px-6 dark:border-gray-800">
                <slot name="footer"></slot>
              </div>
            </DialogPanel>
          </TransitionChild>
        </div>
      </div>
    </Dialog>
  </TransitionRoot>
</template>
