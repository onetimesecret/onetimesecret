<!-- src/apps/workspace/components/forms/WorkspaceSecretForm.vue -->

<script setup lang="ts">
  /**
   * Workspace Secret Form
   *
   * A streamlined secret creation form for the workspace dashboard.
   * Privacy controls (TTL, passphrase) are managed via the parent's
   * PrivacyOptionsBar chips, not inline form fields.
   *
   * Key differences from SecretForm:
   * - Larger textarea for content
   * - Privacy inputs controlled externally via props
   * - Respects workspace mode toggle (stays on page or navigates to receipt)
   */
  import { useI18n } from 'vue-i18n';
  import BasicFormAlerts from '@/shared/components/forms/BasicFormAlerts.vue';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import SplitButton from '@/shared/components/ui/SplitButton.vue';
  import { useDomainContext } from '@/shared/composables/useDomainContext';
  import { useSecretConcealer } from '@/shared/composables/useSecretConcealer';
  import { loggingService } from '@/services/logging.service';
  import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
  import { useConcealedReceiptStore } from '@/shared/stores/concealedReceiptStore';
  import { storeToRefs } from 'pinia';
  import {
    DEFAULT_CORNER_CLASS,
    DEFAULT_PRIMARY_COLOR,
    DEFAULT_BUTTON_TEXT_LIGHT,
  } from '@/shared/stores/identityStore';
  import { type LocalReceipt } from '@/types/ui/local-receipt';
  import { nanoid } from 'nanoid';
  import { computed, ref, watch } from 'vue';
  import { useRouter } from 'vue-router';
  import { useMediaQuery } from '@vueuse/core';
  import { useCharCounter } from '@/shared/composables/useCharCounter';
  import { useTextarea } from '@/shared/composables/useTextarea';

  const { t } = useI18n();
  const router = useRouter();

  export interface Props {
    /** Corner styling class */
    cornerClass?: string;
    /** Primary brand color */
    primaryColor?: string;
    /** Whether button text should be light */
    buttonTextLight?: boolean;
  }

  // Props not destructured - accessed via template bindings or unprefixed in script
  withDefaults(defineProps<Props>(), {
    cornerClass: DEFAULT_CORNER_CLASS,
    primaryColor: DEFAULT_PRIMARY_COLOR,
    buttonTextLight: DEFAULT_BUTTON_TEXT_LIGHT,
  });

  const emit = defineEmits<{
    /** Emitted after successful secret creation with the response data */
    (e: 'created', response: LocalReceipt): void;
  }>();

  const concealedReceiptStore = useConcealedReceiptStore();

  // Get global defaults
  const bootstrapStore = useBootstrapStore();
  const { secret_options } = storeToRefs(bootstrapStore);
  const defaultTtl = computed(() => secret_options.value?.default_ttl ?? 604800);

  const { currentContext, isContextActive } = useDomainContext();

  // Textarea setup with larger dimensions for workspace
  const maxLength = 10000;
  const {
    content,
    charCount,
    textareaRef,
    checkContentLength,
    clearTextarea,
  } = useTextarea({
    maxLength,
    initialContent: '',
    maxHeight: 500,
    onContentChange: () => {},
  });

  const { isHovering, formatNumber } = useCharCounter();

  // Computed properties for character counter
  const showCounter = computed(
    () => isHovering.value || charCount.value > maxLength / 2
  );
  const formattedCharCount = computed(() => formatNumber(charCount.value));
  const formattedMaxLength = computed(() => formatNumber(maxLength));
  const statusColor = computed(() => {
    const percentage = charCount.value / maxLength;
    if (percentage < 0.8) return 'bg-emerald-400 dark:bg-emerald-500';
    if (percentage < 0.95) return 'bg-amber-400 dark:bg-amber-500';
    return 'bg-red-400 dark:bg-red-500';
  });

  // Secret concealer with workspace mode behavior
  const { form, validation, operations, isSubmitting, submit } =
    useSecretConcealer({
      onSuccess: async (response) => {
        const timestamp = Date.now();
        loggingService.debug('[DEBUG:WorkspaceSecretForm] onSuccess started', {
          timestamp,
          receiptId: response?.record?.receipt?.identifier,
          receiptShortid: response?.record?.receipt?.shortid,
          workspaceMode: concealedReceiptStore.workspaceMode,
        });

        if (!response) throw 'Response is missing';
        const newMessage: LocalReceipt = {
          id: nanoid(),
          receiptExtid: response.record.receipt.identifier,
          receiptShortid: response.record.receipt.shortid,
          secretExtid: response.record.secret.identifier,
          secretShortid: response.record.secret.shortid,
          shareDomain: response.record.share_domain,
          hasPassphrase: !!form.passphrase,
          ttl: form.ttl as number,
          createdAt: Date.now(),
        };
        // Add the message to the store
        concealedReceiptStore.addMessage(newMessage);

        // Preserve TTL before reset (sticky setting)
        const preservedTtl = form.ttl;

        operations.reset();
        clearTextarea();

        // Restore TTL to previous value (sticky across submissions)
        operations.updateField('ttl', preservedTtl as number);

        // Emit event for parent components
        loggingService.debug('[DEBUG:WorkspaceSecretForm] Emitting created event', {
          timestamp,
          receiptShortid: newMessage.receiptShortid,
        });
        emit('created', newMessage);

        // Navigate to receipt page if workspace mode is off OR if generating password
        // (generated passwords must be viewed on receipt page since they're only shown once)
        if (!concealedReceiptStore.workspaceMode || selectedAction.value === 'generate-password') {
          router.push(`/receipt/${newMessage.receiptExtid}`);
        } else {
          loggingService.debug('[DEBUG:WorkspaceSecretForm] Staying on page (workspace mode)', {
            timestamp,
          });
        }
      },
    });

  // Initialize TTL with default on mount
  operations.updateField('ttl', defaultTtl.value);

  // Sync content with form
  watch(content, (newContent) => {
    operations.updateField('secret', newContent);
  });

  // Watch for domain context changes and update form
  watch(
    () => currentContext.value.domain,
    (domain) => {
      if (domain) {
        operations.updateField('share_domain', domain);
      }
    },
    { immediate: true }
  );

  // Compute whether the form has content
  const hasContent = computed(
    () => !!content.value && content.value.trim().length > 0
  );

  // Track selected action from SplitButton
  const selectedAction = ref<'create-link' | 'generate-password'>('create-link');

  // Platform detection for keyboard hint (desktop only)
  const isDesktop = useMediaQuery('(min-width: 640px)');
  const isMac = computed(() =>
    typeof navigator !== 'undefined' && /Mac|iPod|iPhone|iPad/.test(navigator.platform)
  );
  const shortcutHint = computed(() => (isMac.value ? '⌘ Enter' : 'Ctrl Enter'));

  // Form submission handlers
  const handleSubmit = () => {
    // Use appropriate submission type based on selected action
    if (selectedAction.value === 'generate-password') {
      return submit('generate');
    }
    return submit('conceal');
  };

  // Expose form state and operations for parent component
  const currentTtl = computed(() => form.ttl as number);
  const currentPassphrase = computed(() => form.passphrase as string);

  const updateTtl = (value: number) => {
    operations.updateField('ttl', value);
  };

  const updatePassphrase = (value: string) => {
    operations.updateField('passphrase', value);
  };

  defineExpose({
    currentTtl,
    currentPassphrase,
    updateTtl,
    updatePassphrase,
    isSubmitting,
  });
</script>

<template>
  <div class="mx-auto min-w-[320px] max-w-full space-y-6">
    <!-- Alert Display -->
    <BasicFormAlerts
      :errors="Array.from(validation.errors.values())"
      class="sticky top-4 z-50" />

    <form
      @submit.prevent="handleSubmit"
      :aria-busy="isSubmitting"
      class="space-y-6">
      <!-- Main Content Card -->
      <div
        :class="[cornerClass]"
        class="overflow-visible border border-gray-200/60
          bg-gradient-to-br from-white to-gray-50/30
          shadow-[0_4px_16px_rgb(0,0,0,0.08),0_1px_4px_rgb(0,0,0,0.06)]
          backdrop-blur-sm
          dark:border-gray-700/60 dark:from-slate-900 dark:to-slate-800/30
          dark:shadow-[0_4px_16px_rgb(0,0,0,0.3),0_1px_4px_rgb(0,0,0,0.2)]">
        <!-- Content Section -->
        <div class="p-6">
          <!-- Textarea for Create Link mode -->
          <div v-show="selectedAction === 'create-link'">
            <label
              id="workspaceSecretLabel"
              class="sr-only">
              {{ t('web.secrets.secret_content') || 'Secret Content' }}
            </label>

            <div class="relative">
              <textarea
                ref="textareaRef"
                v-model="content"
                :disabled="isSubmitting"
                @input="checkContentLength"
                :maxlength="maxLength"
                :class="[cornerClass]"
                style="min-height: 280px; max-height: 500px"
                class="block w-full resize-none
                  rounded-lg border border-gray-200/60 p-4
                  font-mono text-base leading-relaxed
                  text-gray-900 transition-all
                  duration-300 placeholder:text-gray-400
                  bg-white/80 backdrop-blur-sm
                  hover:border-gray-300/80 hover:bg-white/90
                  focus:border-blue-500/80 focus:bg-white
                  focus:ring-4 focus:ring-blue-500/20
                  disabled:bg-gray-50/80 disabled:text-gray-500
                  dark:border-gray-700/60 dark:bg-slate-800/80
                  dark:text-white dark:placeholder:text-gray-500
                  dark:hover:border-gray-600/80 dark:hover:bg-slate-800/90
                  dark:focus:border-blue-400/80 dark:focus:bg-slate-800
                  dark:focus:ring-blue-400/20
                  dark:disabled:bg-slate-900/50"
                :placeholder="t('web.COMMON.secret_placeholder')"
                aria-labelledby="workspaceSecretLabel">
              </textarea>

              <!-- Character Counter -->
              <div
                v-if="showCounter"
                class="pointer-events-none absolute bottom-4 right-4 flex
                  select-none items-center gap-2
                  rounded-full bg-white/95 px-3.5 py-1.5 text-sm
                  shadow-[0_4px_12px_rgba(0,0,0,0.1),0_1px_3px_rgba(0,0,0,0.08)]
                  backdrop-blur-md transition-all duration-300
                  border border-gray-200/40
                  dark:bg-gray-800/95 dark:border-gray-700/40
                  dark:shadow-[0_4px_12px_rgba(0,0,0,0.3),0_1px_3px_rgba(0,0,0,0.2)]">
                <span
                  :class="[statusColor, 'size-2.5 rounded-full shadow-sm']"
                  aria-hidden="true" ></span>
                <span
                  class="font-semibold text-gray-700 dark:text-gray-300 tabular-nums">
                  {{ formattedCharCount }} / {{ formattedMaxLength }}
                </span>
              </div>
            </div>
          </div>

          <!-- Generate Password display for Generate mode -->
          <div
            v-show="selectedAction === 'generate-password'"
            :class="[cornerClass]"
            class="relative overflow-hidden rounded-lg border border-brand-200/50
              bg-gradient-to-br from-brand-50/80 to-purple-50/40
              shadow-[0_4px_20px_rgb(0,0,0,0.08)] backdrop-blur-sm
              dark:border-brand-700/50 dark:from-brand-900/30 dark:to-purple-900/20
              dark:shadow-[0_4px_20px_rgb(0,0,0,0.3)]"
            style="min-height: 280px"
            aria-labelledby="generatedPasswordHeader"
            aria-describedby="generatedPasswordDesc"
            role="region">
            <!-- Decorative blur orbs -->
            <div
              class="pointer-events-none absolute -left-12 -top-12 size-32
                rounded-full bg-gradient-to-br from-brand-300/30 to-purple-300/20 blur-3xl"
              aria-hidden="true"></div>
            <div
              class="pointer-events-none absolute -bottom-12 -right-12 size-32
                rounded-full bg-gradient-to-br from-purple-300/30 to-brand-300/20 blur-3xl"
              aria-hidden="true"></div>

            <div class="relative z-10 flex h-full min-h-[280px] flex-col items-center justify-center space-y-4 p-6 text-center">
              <div class="flex justify-center">
                <div
                  class="animate-[pulse_2s_ease-in-out_infinite] rounded-full
                    bg-gradient-to-br from-brand-100 to-purple-100 p-4
                    shadow-[0_0_0_0_rgba(var(--color-brand-500),0.5)]
                    dark:from-brand-900/50 dark:to-purple-900/50">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    width="24"
                    height="24"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2"
                    class="size-7 text-brand-600 dark:text-brand-400">
                    <path
                      d="M21 2l-2 2m-7.61 7.61a5.5 5.5 0 1 1-7.778 7.778 5.5 5.5 0 0 1 7.777-7.777zm0 0L15.5 7.5m0 0l3 3L22 7l-3-3m-3.5 3.5L19 4" />
                  </svg>
                </div>
              </div>

              <h4
                id="generatedPasswordHeader"
                class="text-lg font-medium text-gray-900 dark:text-white"
                tabindex="-1">
                {{ t('web.homepage.password_generation_title') }}
              </h4>

              <p
                id="generatedPasswordDesc"
                class="mx-auto max-w-md text-gray-600 dark:text-gray-300">
                {{ t('web.homepage.password_generation_description') }}
              </p>
            </div>
          </div>
        </div>

        <!-- Actions Footer -->
        <div class="border-t border-gray-200/50 dark:border-gray-700/50">
          <div class="p-4 sm:p-6">
            <!-- Main action row -->
            <div
              class="flex items-center justify-between gap-4">
              <!-- Domain Context Indicator (hidden on mobile - redundant with header) -->
              <div
                v-if="isContextActive"
                class="hidden items-center gap-2 text-base font-brand sm:flex">
                <span class="text-gray-600 dark:text-gray-400">
                  {{ t('web.LABELS.creating_links_for') }}
                </span>
                <div
                  class="inline-flex items-center gap-1.5 rounded-full px-3
                    py-1.5 text-base font-medium transition-all duration-150"
                  :class="
                    currentContext.isCanonical
                      ? 'bg-gray-100 text-gray-700 dark:bg-gray-700 dark:text-gray-300'
                      : 'bg-brand-50 text-brand-700 dark:bg-brand-900/30 dark:text-brand-300'
                  "
                  role="status"
                  :aria-label="
                    t('web.LABELS.scope_indicator', {
                      domain: currentContext.displayName,
                    })
                  ">
                  <OIcon
                    collection="heroicons"
                    :name="
                      currentContext.isCanonical
                        ? 'user-circle'
                        : 'building-office'
                    "
                    class="size-4"
                    aria-hidden="true" />
                  <span class="max-w-[180px] truncate">
                    {{ currentContext.displayName }}
                  </span>
                </div>
              </div>

              <!-- Submit Area with Stay on Page toggle (always right-aligned) -->
              <div class="ml-auto flex items-center gap-2.5">
                <!-- Stay on Page Toggle (refined, compact) -->
                <!-- Disabled when generating password since user must see the receipt to view the generated password -->
                <button
                  type="button"
                  :disabled="isSubmitting || selectedAction === 'generate-password'"
                  @click="concealedReceiptStore.toggleWorkspaceMode()"
                  :title="selectedAction === 'generate-password'
                    ? t('web.secrets.workspace_mode_disabled_for_generate')
                    : t('web.secrets.workspace_mode_description')"
                  class="inline-flex items-center gap-1 rounded px-2 py-1.5 text-xs
                    font-medium ring-1 ring-inset transition-all
                    focus:outline-none focus:ring-2 focus:ring-brand-500/50
                    disabled:opacity-50 disabled:cursor-not-allowed"
                  :class="
                    concealedReceiptStore.workspaceMode && selectedAction !== 'generate-password'
                      ? 'bg-brand-50/80 text-brand-600 ring-brand-500/25 hover:bg-brand-100/80 dark:bg-brand-900/20 dark:text-brand-400 dark:ring-brand-400/20 dark:hover:bg-brand-900/30'
                      : 'bg-gray-50/80 text-gray-500 ring-gray-400/20 hover:bg-gray-100/80 hover:text-gray-600 dark:bg-gray-800/50 dark:text-gray-400 dark:ring-gray-600/20 dark:hover:bg-gray-700/50'
                  ">
                  <OIcon
                    collection="mdi"
                    :name="concealedReceiptStore.workspaceMode && selectedAction !== 'generate-password' ? 'pin' : 'pin-off'"
                    class="size-3.5"
                    aria-hidden="true" />
                  <span>{{ t('web.secrets.workspace_mode') }}</span>
                </button>

                <!-- Submit Button -->
                <SplitButton
                  :with-generate="true"
                  :corner-class="cornerClass"
                  :primary-color="primaryColor"
                  :button-text-light="buttonTextLight"
                  :disabled="selectedAction === 'create-link' && !hasContent"
                  :disable-generate="selectedAction === 'create-link' && hasContent"
                  :keyboard-shortcut-enabled="true"
                  :show-keyboard-hint="false"
                  @update:action="selectedAction = $event" />
              </div>
            </div>

            <!-- Keyboard hint row (desktop only) -->
            <div
              v-if="isDesktop"
              class="mt-2 flex justify-end">
              <span class="text-xs text-gray-500 dark:text-gray-400">
                {{ shortcutHint }}
              </span>
            </div>
          </div>
        </div>
      </div>
    </form>
  </div>
</template>
