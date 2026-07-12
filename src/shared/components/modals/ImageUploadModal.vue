<!-- src/shared/components/modals/ImageUploadModal.vue -->

<script setup lang="ts">
  /**
   * Reusable staged image-upload dialog. The user picks (or drags) an image and
   * previews it locally; nothing is persisted until they confirm — the commit is
   * the caller's `onSave`/`onRemove`. So this modal is image-agnostic (the brand
   * logo today; favicon or other images later) and knows nothing about endpoints,
   * entitlements, or dirtiness — it only stages a File and hands it back.
   *
   * Success/failure contract: `onSave`/`onRemove` follow the app's async-handler
   * convention (useAsyncHandler.wrap) — they never reject; they resolve to a
   * truthy value on success and a falsy value on failure, having already surfaced
   * the specific error via a toast. So this dialog closes on a truthy result and,
   * on a falsy/thrown result, stays open with the staged file intact for retry.
   */
  import type { ImageProps } from '@/schemas/shapes/v3/custom-domain';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { fileToDataUrl, useLogoImage } from '@/shared/composables/useLogoImage';
  import {
    Dialog,
    DialogPanel,
    DialogTitle,
    TransitionChild,
    TransitionRoot,
  } from '@headlessui/vue';
  import { computed, ref, watch } from 'vue';
  import { useI18n } from 'vue-i18n';

  const DEFAULT_MAX_BYTES = 1024 * 1024; // 1MB

  const { t } = useI18n();

  const props = withDefaults(
    defineProps<{
      isOpen: boolean;
      /** Variable, caller-supplied strings (already translated) — keeps the modal i18n-agnostic. */
      title: string;
      saveLabel: string;
      currentImage?: ImageProps | null;
      hint?: string;
      /** Omit to hide the remove affordance (e.g. a required image). */
      removeLabel?: string;
      accept?: string;
      maxSizeBytes?: number;
      onSave: (file: File) => Promise<unknown>;
      onRemove?: () => Promise<unknown>;
    }>(),
    {
      currentImage: null,
      hint: '',
      removeLabel: '',
      accept: 'image/*',
      maxSizeBytes: DEFAULT_MAX_BYTES,
      onRemove: undefined,
    }
  );

  const emit = defineEmits<{ (e: 'close'): void }>();

  // Baseline (already-persisted) image derivation, shared with the in-form
  // (BrandLogoField) and preview (SecretPreview) entry points so the three can't
  // drift on validity / data-URL shape.
  const { isValidLogo: hasCurrentImage, logoSrc: currentSrc } = useLogoImage(
    () => props.currentImage
  );

  const pendingFile = ref<File | null>(null);
  const pendingSrc = ref('');
  const pendingRemoval = ref(false);
  const validationError = ref<string | null>(null);
  const saveError = ref<string | null>(null);
  const isSaving = ref(false);

  // Reset all staging whenever the dialog (re)opens so a prior session's picked
  // file / error never leaks into the next open.
  watch(
    () => props.isOpen,
    (open) => {
      if (!open) return;
      pendingFile.value = null;
      pendingSrc.value = '';
      pendingRemoval.value = false;
      validationError.value = null;
      saveError.value = null;
      isSaving.value = false;
    }
  );

  // Precedence: a freshly picked file, else a staged removal (empty), else the
  // persisted image, else empty.
  const previewSrc = computed(() => {
    if (pendingFile.value) return pendingSrc.value;
    if (pendingRemoval.value) return '';
    return hasCurrentImage.value ? currentSrc.value : '';
  });
  const hasPreview = computed(() => Boolean(previewSrc.value));

  // Something is staged to commit: a new file, or removal of the current image.
  const canConfirm = computed(() => pendingFile.value !== null || pendingRemoval.value);
  // Offer removal only when there's a persisted image, removal is supported, and
  // we're not already staging a replacement or removal.
  const canRemove = computed(
    () =>
      Boolean(props.onRemove) &&
      Boolean(props.removeLabel) &&
      hasCurrentImage.value &&
      !pendingFile.value &&
      !pendingRemoval.value
  );

  const humanMaxSize = computed(() => {
    const mb = props.maxSizeBytes / (1024 * 1024);
    return Number.isInteger(mb) ? `${mb}MB` : `${Math.round(props.maxSizeBytes / 1024)}KB`;
  });

  const stageFile = async (file: File | undefined) => {
    if (!file) return;
    validationError.value = null;
    saveError.value = null;
    if (!file.type.startsWith('image/')) {
      validationError.value = t('web.branding.image_invalid_type');
      return;
    }
    if (file.size > props.maxSizeBytes) {
      validationError.value = t('web.branding.image_too_large', { max: humanMaxSize.value });
      return;
    }
    pendingRemoval.value = false;
    pendingFile.value = file;
    pendingSrc.value = await fileToDataUrl(file);
  };

  const onFilePick = (event: Event) => {
    const input = event.target as HTMLInputElement;
    void stageFile(input.files?.[0]);
    input.value = ''; // allow re-picking the same file
  };

  const onDrop = (event: DragEvent) => {
    void stageFile(event.dataTransfer?.files?.[0]);
  };

  const stageRemoval = () => {
    pendingFile.value = null;
    pendingSrc.value = '';
    validationError.value = null;
    saveError.value = null;
    pendingRemoval.value = true;
  };

  const undoStaged = () => {
    pendingFile.value = null;
    pendingSrc.value = '';
    pendingRemoval.value = false;
    validationError.value = null;
    saveError.value = null;
  };

  const close = () => {
    if (isSaving.value) return;
    emit('close');
  };

  const confirm = async () => {
    if (!canConfirm.value || isSaving.value) return;
    isSaving.value = true;
    saveError.value = null;
    try {
      const ok = pendingRemoval.value
        ? await props.onRemove?.()
        : await props.onSave(pendingFile.value as File);
      if (ok) {
        emit('close');
      } else {
        // Wrapped handlers toast the specific error and resolve falsy; keep the
        // dialog open (staged file intact) and explain why it didn't close.
        saveError.value = t('web.branding.image_upload_failed');
      }
    } catch {
      // A caller whose handler rejects instead of resolving falsy.
      saveError.value = t('web.branding.image_upload_failed');
    } finally {
      isSaving.value = false;
    }
  };

  const confirmLabel = computed(() => (pendingRemoval.value ? props.removeLabel : props.saveLabel));
</script>

<template>
  <TransitionRoot
    as="template"
    :show="isOpen">
    <Dialog
      class="relative z-50"
      @close="close">
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
              class="relative overflow-hidden rounded-lg bg-white px-4 pt-5 pb-4 text-left shadow-xl transition-all sm:my-8 sm:w-full sm:max-w-lg sm:p-6 dark:bg-gray-800">
              <!-- Header -->
              <div class="mb-4 flex items-start justify-between">
                <div class="flex items-center gap-3">
                  <div
                    class="flex size-10 shrink-0 items-center justify-center rounded-full bg-brand-100 dark:bg-brand-900/50">
                    <OIcon
                      collection="mdi"
                      name="image-outline"
                      class="size-5 text-brand-600 dark:text-brand-400"
                      aria-hidden="true" />
                  </div>
                  <DialogTitle
                    as="h3"
                    class="text-lg leading-6 font-semibold text-gray-900 dark:text-gray-100">
                    {{ title }}
                  </DialogTitle>
                </div>
                <button
                  type="button"
                  class="rounded-md text-gray-400 hover:text-gray-500 focus:ring-2 focus:ring-brand-500 focus:outline-none dark:text-gray-500 dark:hover:text-gray-400"
                  @click="close">
                  <span class="sr-only">{{ t('web.LABELS.close') }}</span>
                  <OIcon
                    collection="mdi"
                    name="close"
                    class="size-5"
                    aria-hidden="true" />
                </button>
              </div>

              <div class="space-y-4">
                <!-- Pick / drop area (whole box is the file picker; also accepts drops) -->
                <label
                  class="flex cursor-pointer flex-col items-center justify-center gap-3 rounded-xl border-2 border-dashed border-gray-300 bg-gray-50 px-6 py-8 text-center transition-colors hover:border-brand-400 dark:border-gray-600 dark:bg-gray-900/40"
                  @dragover.prevent
                  @drop.prevent="onDrop">
                  <div
                    class="flex size-20 items-center justify-center overflow-hidden rounded-lg border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
                    <img
                      v-if="hasPreview"
                      :src="previewSrc"
                      alt=""
                      class="size-full object-contain" />
                    <OIcon
                      v-else
                      collection="mdi"
                      name="image-outline"
                      class="size-8 text-gray-400 dark:text-gray-500"
                      aria-hidden="true" />
                  </div>
                  <div class="flex flex-wrap justify-center gap-1 text-sm">
                    <span class="font-semibold text-brand-600 dark:text-brand-400">{{
                      t('web.branding.image_upload_choose')
                    }}</span>
                    <span class="text-gray-500 dark:text-gray-400">
                      {{ t('web.branding.image_upload_drag_hint') }}</span>
                  </div>
                  <span
                    v-if="hint"
                    class="text-xs text-gray-400 dark:text-gray-500">{{ hint }}</span>
                  <input
                    type="file"
                    class="sr-only"
                    :accept="accept"
                    @change="onFilePick" />
                </label>

                <!-- Staged-removal notice -->
                <p
                  v-if="pendingRemoval"
                  class="flex items-center gap-1.5 text-sm text-amber-700 dark:text-amber-400">
                  <OIcon
                    collection="mdi"
                    name="alert-circle-outline"
                    class="size-4 shrink-0"
                    aria-hidden="true" />
                  {{ t('web.branding.image_will_be_removed') }}
                </p>

                <!-- Pick-time validation error -->
                <p
                  v-if="validationError"
                  class="flex items-center gap-1.5 text-sm text-red-600 dark:text-red-400"
                  role="alert">
                  <OIcon
                    collection="mdi"
                    name="alert-circle-outline"
                    class="size-4 shrink-0"
                    aria-hidden="true" />
                  {{ validationError }}
                </p>

                <!-- Commit-time error (dialog stays open for retry) -->
                <p
                  v-if="saveError"
                  class="flex items-center gap-1.5 text-sm text-red-600 dark:text-red-400"
                  role="alert">
                  <OIcon
                    collection="mdi"
                    name="alert-circle-outline"
                    class="size-4 shrink-0"
                    aria-hidden="true" />
                  {{ saveError }}
                </p>

                <!-- Secondary actions: remove the persisted image, or undo staging -->
                <div
                  v-if="canRemove || canConfirm"
                  class="flex items-center gap-4 text-sm">
                  <button
                    v-if="canRemove"
                    type="button"
                    class="font-medium text-red-600 hover:text-red-500 dark:text-red-400"
                    @click="stageRemoval">
                    {{ removeLabel }}
                  </button>
                  <button
                    v-if="canConfirm"
                    type="button"
                    class="font-medium text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200"
                    @click="undoStaged">
                    {{ t('web.branding.undo') }}
                  </button>
                </div>
              </div>

              <!-- Footer -->
              <div class="mt-6 flex flex-row-reverse gap-3">
                <button
                  type="button"
                  :disabled="!canConfirm || isSaving"
                  class="inline-flex items-center justify-center gap-2 rounded-md px-4 py-2 text-sm font-semibold text-white shadow-sm focus:ring-2 focus:ring-offset-2 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50"
                  :class="pendingRemoval
                    ? 'bg-red-600 hover:bg-red-500 focus:ring-red-500'
                    : 'bg-brand-600 hover:bg-brand-500 focus:ring-brand-500'"
                  @click="confirm">
                  <OIcon
                    v-if="isSaving"
                    collection="mdi"
                    name="loading"
                    class="size-4 animate-spin"
                    aria-hidden="true" />
                  {{ confirmLabel }}
                </button>
                <button
                  type="button"
                  :disabled="isSaving"
                  class="inline-flex justify-center rounded-md bg-white px-4 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-gray-300 ring-inset hover:bg-gray-50 disabled:opacity-50 dark:bg-gray-700 dark:text-gray-100 dark:ring-gray-600 dark:hover:bg-gray-600"
                  @click="close">
                  {{ t('web.COMMON.word_cancel') }}
                </button>
              </div>
            </DialogPanel>
          </TransitionChild>
        </div>
      </div>
    </Dialog>
  </TransitionRoot>
</template>
