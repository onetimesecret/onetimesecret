<!-- src/components/modals/SecretLinkCopyFirstModal.vue -->

<script setup lang="ts">
  import OIcon from '@/components/icons/OIcon.vue';
  import CopyButton from '@/components/CopyButton.vue';
  import StatusBadge from '@/components/secrets/metadata/StatusBadge.vue';
  import {
    Dialog,
    DialogPanel,
    DialogTitle,
    TransitionChild,
    TransitionRoot,
  } from '@headlessui/vue';
  import { ref, watch, nextTick, computed } from 'vue';
  import { useI18n } from 'vue-i18n';
  import { useMetadataStore } from '@/stores/metadataStore';
  import { formatDistanceToNow, formatDistance } from 'date-fns';

  const { t } = useI18n();
  const metadataStore = useMetadataStore();

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
  const showDetails = ref(false);
  const detailsLoading = ref(false);
  const detailsId = 'secret-link-copyfirst-details-panel';

  const metadataRecord = computed(() => metadataStore.record);
  const hasMetadata = computed(() => metadataRecord.value !== null && metadataStore.details !== null);

  const createdTimeAgo = computed(() => {
    if (!metadataRecord.value?.created) return '';
    return formatDistanceToNow(metadataRecord.value.created, { addSuffix: true });
  });

  const expirationDate = computed(() => {
    if (!metadataRecord.value) return null;
    const created = metadataRecord.value.created;
    const ttl = metadataRecord.value.expiration_in_seconds ?? 0;
    return new Date(created.getTime() + ttl * 1000);
  });

  const expirationProgress = computed(() => {
    if (!metadataRecord.value || !expirationDate.value) return 0;
    const now = Date.now();
    const start = metadataRecord.value.created.getTime();
    const end = expirationDate.value.getTime();
    const total = end - start;
    if (total <= 0) return 100;
    return Math.min(100, Math.max(0, ((now - start) / total) * 100));
  });

  const expirationTimeRemaining = computed(() => {
    if (!expirationDate.value) return '';
    return formatDistance(expirationDate.value, new Date(), { addSuffix: true });
  });

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
        showDetails.value = false;
      }
    }
  );

  watch(showDetails, async (isOpen) => {
    if (isOpen && !hasMetadata.value) {
      detailsLoading.value = true;
      try {
        await metadataStore.fetch(props.metadataKey);
      } catch {
        // Fetch failure is non-critical
      } finally {
        detailsLoading.value = false;
      }
    }
  });
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
            class="w-full max-w-xl lg:max-w-3xl">
            <DialogPanel
              ref="modalRef"
              class="relative overflow-hidden rounded-2xl bg-white transition-transform duration-300 ease-out dark:bg-gray-800"
              :class="showDetails ? '-translate-y-4' : 'translate-y-0'">
              <div class="absolute left-0 top-0 h-1.5 w-full overflow-hidden">
                <div
                  class="size-full animate-gradient-x bg-200%
                    bg-gradient-to-r from-amber-400 via-amber-500 to-amber-400">
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

                <div class="mt-4 flex flex-wrap items-center gap-3 font-system text-sm text-gray-500 dark:text-gray-400">
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
                  <span class="ml-auto">
                    <button
                      type="button"
                      @click="showDetails = !showDetails"
                      :aria-expanded="showDetails"
                      :aria-controls="detailsId"
                      class="inline-flex items-center gap-1 rounded-md px-1 font-system text-sm text-brand-600
                        hover:text-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500
                        focus:ring-offset-2 dark:text-brand-400 dark:hover:text-brand-300">
                      {{ showDetails
                        ? t('web.LABELS.hide_details', 'Hide details')
                        : t('web.LABELS.view_details', 'View Details') }}
                      <OIcon
                        collection="heroicons"
                        :name="showDetails ? 'chevron-up-20-solid' : 'chevron-down-20-solid'"
                        class="size-4 transition-transform"
                        aria-hidden="true" />
                    </button>
                  </span>
                </div>

                <Transition
                  enter-active-class="transition-all duration-300 ease-out"
                  enter-from-class="max-h-0 opacity-0"
                  enter-to-class="max-h-[28rem] opacity-100"
                  leave-active-class="transition-all duration-200 ease-in"
                  leave-from-class="max-h-[28rem] opacity-100"
                  leave-to-class="max-h-0 opacity-0">
                  <div
                    v-if="showDetails"
                    :id="detailsId"
                    class="overflow-hidden">
                    <div class="mt-3 border-t border-gray-200 pt-4 font-system dark:border-gray-700">

                      <div
                        v-if="detailsLoading"
                        class="flex items-center justify-center py-4">
                        <div
                          class="size-5 animate-spin rounded-full border-2 border-gray-300
                            border-t-brand-600 dark:border-gray-600 dark:border-t-brand-400"
                          role="status"
                          :aria-label="t('web.STATUS.securing', 'Loading')"></div>
                      </div>

                      <div v-else-if="metadataRecord">
                        <div class="mb-3 flex items-center justify-between">
                          <!-- prettier-ignore-attribute class -->
                          <div
                            class="flex items-center gap-1.5 text-xs font-medium uppercase tracking-wider
                              text-gray-500 dark:text-gray-400">
                            <OIcon
                              collection="material-symbols"
                              name="timer-outline"
                              class="size-3.5"
                              aria-hidden="true" />
                            {{ t('web.LABELS.timeline') }}
                          </div>
                          <StatusBadge :record="metadataRecord" />
                        </div>

                        <div class="relative space-y-4 pl-7">
                          <!-- prettier-ignore-attribute class -->
                          <div
                            class="absolute left-[11px] top-1 h-[calc(100%-1rem)] w-px
                              bg-gradient-to-b from-brand-200 to-gray-200
                              dark:from-brand-700 dark:to-gray-700"></div>

                          <div class="relative flex gap-3">
                            <!-- prettier-ignore-attribute class -->
                            <div
                              class="absolute -left-7 z-10 flex size-6 items-center justify-center
                                rounded-full border border-brand-200 bg-brand-100
                                dark:border-brand-800 dark:bg-brand-900">
                              <OIcon
                                collection="material-symbols"
                                name="check"
                                class="size-3.5 text-brand-600 dark:text-brand-400"
                                aria-hidden="true" />
                            </div>
                            <div>
                              <p class="font-brand text-sm text-gray-900 dark:text-gray-100">
                                {{ t('web.STATUS.created') }}
                              </p>
                              <time
                                :datetime="metadataRecord.created.toISOString()"
                                class="text-xs text-gray-500 dark:text-gray-400">
                                {{ metadataRecord.created.toLocaleString() }}
                              </time>
                              <p class="text-xs text-gray-500 dark:text-gray-400">
                                {{ createdTimeAgo }}
                              </p>
                            </div>
                          </div>

                          <div
                            v-if="expirationDate"
                            class="relative flex gap-3">
                            <!-- prettier-ignore-attribute class -->
                            <div
                              class="absolute -left-7 z-10 flex size-6 items-center justify-center
                                rounded-full border border-red-200 bg-red-100
                                dark:border-red-800 dark:bg-red-900">
                              <OIcon
                                collection="material-symbols"
                                name="timer-outline"
                                class="size-3.5 text-red-600 dark:text-red-400"
                                aria-hidden="true" />
                            </div>
                            <div class="grow">
                              <p class="font-brand text-sm text-gray-900 dark:text-gray-100">
                                {{ t('web.STATUS.expires') }}
                              </p>
                              <div class="mt-1.5 h-1.5 overflow-hidden rounded-full bg-gray-200 dark:bg-gray-700">
                                <!-- prettier-ignore-attribute class -->
                                <div
                                  class="h-1.5 rounded-full bg-gradient-to-r from-red-400 to-red-500
                                    transition-[width] duration-1000 ease-linear"
                                  :style="{ width: `${expirationProgress}%` }"></div>
                              </div>
                              <time
                                :datetime="expirationDate.toISOString()"
                                class="mt-1 block text-xs text-gray-500 dark:text-gray-400">
                                {{ expirationDate.toLocaleString() }}
                              </time>
                              <p class="text-xs text-gray-500 dark:text-gray-400">
                                {{ expirationTimeRemaining }}
                              </p>
                            </div>
                          </div>
                        </div>

                        <!-- prettier-ignore-attribute class -->
                        <div
                          class="mt-3 flex items-center gap-2 border-t border-gray-100
                            pt-2.5 text-xs text-gray-500 dark:border-gray-700/50 dark:text-gray-400">
                          <OIcon
                            collection="heroicons"
                            name="arrow-top-right-on-square-20-solid"
                            class="size-3.5"
                            aria-hidden="true" />
                          <a
                            :href="`/receipt/${metadataKey}`"
                            class="text-brand-600 hover:text-brand-700 hover:underline
                              dark:text-brand-400 dark:hover:text-brand-300">
                            {{ t('web.LABELS.view_details', 'View full receipt') }}
                          </a>
                        </div>
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
