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
  import { useDomainScope } from '@/shared/composables/useDomainScope';
  import { useSecretConcealer } from '@/shared/composables/useSecretConcealer';
  import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
  import { useConcealedMetadataStore } from '@/shared/stores/concealedMetadataStore';
  import { storeToRefs } from 'pinia';
  import {
    DEFAULT_CORNER_CLASS,
    DEFAULT_PRIMARY_COLOR,
    DEFAULT_BUTTON_TEXT_LIGHT,
  } from '@/shared/stores/identityStore';
  import { type ConcealedMessage } from '@/types/ui/concealed-message';
  import { useMagicKeys, whenever } from '@vueuse/core';
  import { nanoid } from 'nanoid';
  import { computed, watch } from 'vue';
  import { useRouter } from 'vue-router';
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

  const props = withDefaults(defineProps<Props>(), {
    cornerClass: DEFAULT_CORNER_CLASS,
    primaryColor: DEFAULT_PRIMARY_COLOR,
    buttonTextLight: DEFAULT_BUTTON_TEXT_LIGHT,
  });

  const emit = defineEmits<{
    /** Emitted after successful secret creation with the response data */
    (e: 'created', response: ConcealedMessage): void;
  }>();

  const concealedMetadataStore = useConcealedMetadataStore();

  // Get global defaults
  const bootstrapStore = useBootstrapStore();
  const { secret_options } = storeToRefs(bootstrapStore);
  const defaultTtl = computed(() => secret_options.value?.default_ttl ?? 604800);

  const { currentScope, isScopeActive } = useDomainScope();

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
        if (!response) throw 'Response is missing';
        const newMessage: ConcealedMessage = {
          id: nanoid(),
          metadata_identifier: response.record.metadata.identifier,
          secret_identifier: response.record.secret.identifier,
          response,
          clientInfo: {
            hasPassphrase: !!form.passphrase,
            ttl: form.ttl as number,
            createdAt: new Date(),
          },
        };
        // Add the message to the store
        concealedMetadataStore.addMessage(newMessage);

        // Preserve TTL before reset (sticky setting)
        const preservedTtl = form.ttl;

        operations.reset();
        clearTextarea();

        // Restore TTL to previous value (sticky across submissions)
        operations.updateField('ttl', preservedTtl as number);

        // Emit event for parent components
        emit('created', newMessage);

        // Navigate to receipt page if workspace mode is off
        if (!concealedMetadataStore.workspaceMode) {
          router.push(`/private/${newMessage.metadata_identifier}`);
        }
      },
    });

  // Initialize TTL with default on mount
  operations.updateField('ttl', defaultTtl.value);

  // Sync content with form
  watch(content, (newContent) => {
    operations.updateField('secret', newContent);
  });

  // Watch for domain scope changes and update form
  watch(
    () => currentScope.value.domain,
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

  // Form submission
  const handleSubmit = () => submit('conceal');

  // Keyboard shortcut: Cmd+Enter (Mac) or Ctrl+Enter (Windows/Linux)
  const keys = useMagicKeys();
  const submitShortcut = computed(
    () => keys['Meta+Enter'].value || keys['Control+Enter'].value
  );

  whenever(submitShortcut, () => {
    if (hasContent.value && !isSubmitting.value) {
      handleSubmit();
    }
  });

  // Detect Mac for keyboard shortcut hint
  const isMac = computed(() =>
    typeof navigator !== 'undefined' && /Mac|iPod|iPhone|iPad/.test(navigator.platform)
  );
  const shortcutHint = computed(() => (isMac.value ? '⌘ Enter' : 'Ctrl Enter'));

  // Dynamic button styles based on brand color
  const buttonStyles = computed(() => {
    const color = props.primaryColor || DEFAULT_PRIMARY_COLOR;
    return {
      backgroundColor: color,
      color: props.buttonTextLight ? '#ffffff' : '#1f2937',
    };
  });

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
        class="overflow-visible border border-gray-200/50
          bg-gradient-to-br from-white to-gray-50/30
          shadow-[0_8px_30px_rgb(0,0,0,0.12),0_2px_8px_rgb(0,0,0,0.08)]
          backdrop-blur-sm
          dark:border-gray-700/50 dark:from-slate-900 dark:to-slate-800/30
          dark:shadow-[0_8px_30px_rgb(0,0,0,0.4),0_2px_8px_rgb(0,0,0,0.3)]">
        <!-- Textarea Section -->
        <div class="p-6">
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
                rounded-lg border border-gray-200/60 p-5
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

        <!-- Actions Footer -->
        <div class="border-t border-gray-200/50 dark:border-gray-700/50">
          <div class="p-6">
            <div
              class="flex flex-col gap-4 sm:flex-row sm:items-center
                sm:justify-between">
              <!-- Domain Scope Indicator -->
              <div
                v-if="isScopeActive"
                class="flex items-center gap-2 text-base font-brand">
                <span class="text-gray-600 dark:text-gray-400">
                  {{ t('web.LABELS.creating_links_for') }}
                </span>
                <div
                  class="inline-flex items-center gap-1.5 rounded-full px-3
                    py-1.5 text-base font-medium transition-all duration-150"
                  :class="
                    currentScope.isCanonical
                      ? 'bg-gray-100 text-gray-700 dark:bg-gray-700 dark:text-gray-300'
                      : 'bg-brand-50 text-brand-700 dark:bg-brand-900/30 dark:text-brand-300'
                  "
                  role="status"
                  :aria-label="
                    t('web.LABELS.scope_indicator', {
                      domain: currentScope.displayName,
                    })
                  ">
                  <OIcon
                    collection="heroicons"
                    :name="
                      currentScope.isCanonical
                        ? 'user-circle'
                        : 'building-office'
                    "
                    class="size-4"
                    aria-hidden="true" />
                  <span class="max-w-[180px] truncate">
                    {{ currentScope.displayName }}
                  </span>
                </div>
              </div>

              <!-- Submit Button -->
              <button
                type="submit"
                :disabled="!hasContent || isSubmitting"
                :style="buttonStyles"
                :class="[cornerClass]"
                class="inline-flex items-center justify-center gap-2 px-6 py-3
                  text-base font-semibold shadow-lg transition-all duration-200
                  hover:opacity-90 hover:shadow-xl
                  focus:outline-none focus:ring-4 focus:ring-brand-500/20
                  disabled:cursor-not-allowed disabled:opacity-50
                  disabled:shadow-none">
                <OIcon
                  v-if="isSubmitting"
                  collection="heroicons"
                  name="arrow-path"
                  class="size-4 animate-spin"
                  aria-hidden="true" />
                <OIcon
                  v-else
                  collection="heroicons"
                  name="lock-closed"
                  class="size-4"
                  aria-hidden="true" />
                <span>
                  {{
                    isSubmitting
                      ? t('web.COMMON.submitting')
                      : t('web.LABELS.create_link_short')
                  }}
                </span>
                <kbd
                  v-if="!isSubmitting"
                  class="ml-1.5 hidden rounded bg-white/20 px-1.5 py-0.5
                    text-xs font-normal opacity-70 sm:inline-block">
                  {{ shortcutHint }}
                </kbd>
              </button>
            </div>
          </div>
        </div>
      </div>
    </form>
  </div>
</template>
