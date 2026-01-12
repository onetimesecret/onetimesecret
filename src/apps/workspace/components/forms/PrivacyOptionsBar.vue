<!-- src/apps/workspace/components/forms/PrivacyOptionsBar.vue -->

<script setup lang="ts">
  /**
   * Privacy Options Bar
   *
   * Interactive privacy controls for the workspace secret form.
   * Provides TTL selection and passphrase input as clickable chips
   * that expand to show controls - achieving parity with SecretForm
   * but in a more compact chip-based UI.
   */
  import { computed, nextTick, ref } from 'vue';
  import { useI18n } from 'vue-i18n';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { usePrivacyOptions } from '@/shared/composables/usePrivacyOptions';
  import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
  import { useConcealedReceiptStore } from '@/shared/stores/concealedReceiptStore';
  import { storeToRefs } from 'pinia';

  const { t } = useI18n();
  const concealedReceiptStore = useConcealedReceiptStore();

  // Disable auto attribute inheritance since we have multiple root nodes (main div + Teleport)
  // and manually bind $attrs to the main container
  defineOptions({
    inheritAttrs: false,
  });

  const props = withDefaults(
    defineProps<{
      /** Current TTL value in seconds */
      currentTtl: number;
      /** Current passphrase value */
      currentPassphrase: string;
      /** Whether form is submitting */
      isSubmitting?: boolean;
    }>(),
    {
      isSubmitting: false,
    }
  );

  const emit = defineEmits<{
    (e: 'update:ttl', value: number): void;
    (e: 'update:passphrase', value: string): void;
  }>();

  const { formatDuration, lifetimeOptions } = usePrivacyOptions();

  // Get passphrase config for validation hints
  const bootstrapStore = useBootstrapStore();
  const { secret_options } = storeToRefs(bootstrapStore);
  const passphraseConfig = computed(() => secret_options.value?.passphrase);

  // UI State
  const showTtlDropdown = ref(false);
  const showPassphraseInput = ref(false);
  const passphraseInputRef = ref<HTMLInputElement | null>(null);
  const passphraseVisible = ref(false);

  // Display values
  const ttlDisplay = computed(() => formatDuration(props.currentTtl));

  // Passphrase chip just shows "Passphrase" - visual styling indicates state
  const passphraseDisplay = computed(() => t('web.COMMON.secret_passphrase'));

  const hasPassphrase = computed(() => !!props.currentPassphrase);

  // Passphrase validation - checks minimum length from config
  const minPassphraseLength = computed(
    () => passphraseConfig.value?.minimum_length || 0
  );
  const isPassphraseValid = computed(() => {
    // Empty is valid (passphrase is optional unless required)
    if (!props.currentPassphrase) return true;
    // If there's a minimum length, check it
    if (minPassphraseLength.value > 0) {
      return props.currentPassphrase.length >= minPassphraseLength.value;
    }
    return true;
  });
  const passphraseValidationError = computed(() => {
    if (!props.currentPassphrase || isPassphraseValid.value) return '';
    return t('web.secrets.passphraseMinimumLength', {
      length: minPassphraseLength.value,
    });
  });

  // Handlers
  const toggleTtlDropdown = () => {
    showTtlDropdown.value = !showTtlDropdown.value;
    showPassphraseInput.value = false;
  };

  const selectTtl = (value: number) => {
    emit('update:ttl', value);
    showTtlDropdown.value = false;
  };

  const togglePassphraseInput = async () => {
    showPassphraseInput.value = !showPassphraseInput.value;
    showTtlDropdown.value = false;
    if (showPassphraseInput.value) {
      await nextTick();
      passphraseInputRef.value?.focus();
    }
  };

  const updatePassphrase = (event: Event) => {
    const value = (event.target as HTMLInputElement).value;
    emit('update:passphrase', value);
  };

  const togglePassphraseVisibility = () => {
    passphraseVisible.value = !passphraseVisible.value;
  };

  const clearPassphrase = () => {
    emit('update:passphrase', '');
  };

  // Close dropdowns when clicking outside
  const closeDropdowns = () => {
    showTtlDropdown.value = false;
    showPassphraseInput.value = false;
  };
</script>

<template>
  <div
    v-bind="$attrs"
    class="border-b border-gray-200 bg-white px-4 py-3 dark:border-gray-700 dark:bg-gray-800 sm:px-6">
    <div class="flex flex-wrap items-center gap-4">
      <!-- Privacy Options Label -->
      <div class="flex items-center gap-2">
        <OIcon
          collection="material-symbols"
          name="shield-outline"
          class="size-5 text-gray-500 dark:text-gray-400"
          aria-hidden="true" />
        <span class="text-sm font-medium font-brand text-gray-700 dark:text-gray-300">
          {{ t('web.COMMON.secret_privacy_options') }}
        </span>
      </div>

      <!-- Interactive Chips -->
      <div class="flex flex-wrap items-center gap-2">
        <!-- TTL Chip with Dropdown -->
        <div class="relative">
          <button
            type="button"
            :disabled="isSubmitting"
            @click="toggleTtlDropdown"
            class="inline-flex items-center gap-1.5 rounded-md px-2.5 py-1 text-xs
              font-medium ring-1 ring-inset transition-all
              bg-brand-50 text-brand-700 ring-brand-600/20
              hover:bg-brand-100 hover:ring-brand-600/30
              focus:outline-none focus:ring-2 focus:ring-brand-500
              dark:bg-brand-900/30 dark:text-brand-300 dark:ring-brand-400/30
              dark:hover:bg-brand-900/50
              disabled:opacity-50 disabled:cursor-not-allowed">
            <OIcon
              collection="mdi"
              name="timer-outline"
              class="size-3.5"
              aria-hidden="true" />
            <span>{{ ttlDisplay }}</span>
            <OIcon
              collection="heroicons"
              :name="showTtlDropdown ? 'chevron-up' : 'chevron-down'"
              class="size-3"
              aria-hidden="true" />
          </button>

          <!-- TTL Dropdown -->
          <Transition
            enter-active-class="transition ease-out duration-100"
            enter-from-class="transform opacity-0 scale-95"
            enter-to-class="transform opacity-100 scale-100"
            leave-active-class="transition ease-in duration-75"
            leave-from-class="transform opacity-100 scale-100"
            leave-to-class="transform opacity-0 scale-95">
            <div
              v-if="showTtlDropdown"
              class="absolute left-0 top-full z-50 mt-1 w-48 origin-top-left
                rounded-md bg-white py-1 shadow-lg ring-1 ring-black/5
                dark:bg-gray-800 dark:ring-gray-700">
              <button
                v-for="option in lifetimeOptions"
                :key="option.value"
                type="button"
                @click="selectTtl(option.value)"
                class="block w-full px-4 py-2 text-left text-sm transition-colors
                  hover:bg-gray-100 dark:hover:bg-gray-700"
                :class="
                  option.value === currentTtl
                    ? 'bg-brand-50 text-brand-700 dark:bg-brand-900/30 dark:text-brand-300'
                    : 'text-gray-700 dark:text-gray-300'
                ">
                {{ t('web.secrets.expiresIn', { duration: option.label }) }}
              </button>
            </div>
          </Transition>
        </div>

        <!-- Passphrase Chip with Dropdown -->
        <div class="relative">
          <button
            type="button"
            :disabled="isSubmitting"
            @click="togglePassphraseInput"
            class="inline-flex items-center gap-1.5 rounded-md px-2.5 py-1 text-xs
              font-medium ring-1 ring-inset transition-all
              focus:outline-none focus:ring-2
              disabled:opacity-50 disabled:cursor-not-allowed"
            :class="
              passphraseValidationError
                ? 'bg-red-50 text-red-700 ring-red-600/20 hover:bg-red-100 focus:ring-red-500 dark:bg-red-900/30 dark:text-red-300 dark:ring-red-400/30'
                : hasPassphrase
                  ? 'bg-brand-50 text-brand-700 ring-brand-600/20 hover:bg-brand-100 focus:ring-brand-500 dark:bg-brand-900/30 dark:text-brand-300 dark:ring-brand-400/30'
                  : 'bg-gray-50 text-gray-600 ring-gray-500/20 hover:bg-gray-100 focus:ring-brand-500 dark:bg-gray-700 dark:text-gray-300 dark:ring-gray-500/30'
            ">
            <OIcon
              collection="mdi"
              :name="hasPassphrase ? 'key' : 'key-outline'"
              class="size-3.5"
              aria-hidden="true" />
            <span>{{ passphraseDisplay }}</span>
            <OIcon
              v-if="passphraseValidationError"
              collection="heroicons"
              name="exclamation-triangle"
              class="size-3 text-red-600 dark:text-red-400"
              aria-hidden="true" />
            <OIcon
              v-else-if="hasPassphrase && isPassphraseValid"
              collection="heroicons"
              name="check"
              class="size-3 text-brand-600 dark:text-brand-400"
              aria-hidden="true" />
          </button>

          <!-- Passphrase Dropdown -->
          <Transition
            enter-active-class="transition ease-out duration-100"
            enter-from-class="transform opacity-0 scale-95"
            enter-to-class="transform opacity-100 scale-100"
            leave-active-class="transition ease-in duration-75"
            leave-from-class="transform opacity-100 scale-100"
            leave-to-class="transform opacity-0 scale-95">
            <div
              v-if="showPassphraseInput"
              class="absolute left-0 top-full z-[60] mt-1 w-72 origin-top-left
                rounded-md bg-white p-3 shadow-lg ring-1 ring-black/5
                dark:bg-gray-800 dark:ring-gray-700">
              <div class="relative">
                <input
                  ref="passphraseInputRef"
                  :type="passphraseVisible ? 'text' : 'password'"
                  :value="currentPassphrase"
                  :disabled="isSubmitting"
                  autocomplete="one-time-code"
                  class="w-full rounded-md border bg-white py-2 pl-3 pr-16
                    text-sm text-gray-900 placeholder:text-gray-400
                    focus:outline-none focus:ring-2
                    dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-500"
                  :class="
                    passphraseValidationError
                      ? 'border-red-400 focus:border-red-500 focus:ring-red-500/20 dark:border-red-500'
                      : 'border-gray-300 focus:border-brand-500 focus:ring-brand-500/20 dark:border-gray-600 dark:focus:border-brand-400'
                  "
                  :placeholder="t('web.secrets.enterPassphrase')"
                  @input="updatePassphrase"
                  @keydown.enter="showPassphraseInput = false" />
                <div class="absolute inset-y-0 right-0 flex items-center gap-0.5 pr-1.5">
                  <button
                    v-if="currentPassphrase"
                    type="button"
                    @click="clearPassphrase"
                    class="p-1 text-gray-400 hover:text-gray-600 dark:hover:text-gray-300"
                    :aria-label="t('web.COMMON.clear')">
                    <OIcon
                      collection="heroicons"
                      name="x-mark"
                      class="size-4" />
                  </button>
                  <button
                    type="button"
                    @click="togglePassphraseVisibility"
                    class="p-1 text-gray-400 hover:text-gray-600 dark:hover:text-gray-300"
                    :aria-label="passphraseVisible ? 'Hide passphrase' : 'Show passphrase'">
                    <OIcon
                      collection="heroicons"
                      :name="passphraseVisible ? 'eye-slash' : 'eye'"
                      class="size-4" />
                  </button>
                </div>
              </div>
              <!-- Validation feedback -->
              <p
                v-if="passphraseValidationError"
                class="mt-1.5 text-xs text-red-500 dark:text-red-400">
                {{ passphraseValidationError }}
              </p>
              <p
                v-else-if="minPassphraseLength > 0 && !currentPassphrase"
                class="mt-1.5 text-xs text-gray-500 dark:text-gray-400">
                {{ t('web.secrets.passphraseMinimumLength', { length: minPassphraseLength }) }}
              </p>
            </div>
          </Transition>
        </div>

        <!-- Stay on Page Chip (Workspace Mode Toggle) -->
        <button
          type="button"
          :disabled="isSubmitting"
          @click="concealedReceiptStore.toggleWorkspaceMode()"
          :title="t('web.secrets.workspace_mode_description')"
          class="inline-flex items-center gap-1.5 rounded-md px-2.5 py-1 text-xs
            font-medium ring-1 ring-inset transition-all
            focus:outline-none focus:ring-2 focus:ring-brand-500
            disabled:opacity-50 disabled:cursor-not-allowed"
          :class="
            concealedReceiptStore.workspaceMode
              ? 'bg-brand-50 text-brand-700 ring-brand-600/20 hover:bg-brand-100 dark:bg-brand-900/30 dark:text-brand-300 dark:ring-brand-400/30'
              : 'bg-gray-50 text-gray-600 ring-gray-500/20 hover:bg-gray-100 dark:bg-gray-700 dark:text-gray-300 dark:ring-gray-500/30'
          ">
          <OIcon
            collection="mdi"
            :name="concealedReceiptStore.workspaceMode ? 'pin' : 'pin-off'"
            class="size-3.5"
            aria-hidden="true" />
          <span>{{ t('web.secrets.workspace_mode') }}</span>
          <OIcon
            v-if="concealedReceiptStore.workspaceMode"
            collection="heroicons"
            name="check"
            class="size-3 text-brand-600 dark:text-brand-400"
            aria-hidden="true" />
        </button>
      </div>
    </div>
  </div>

  <!-- Click outside handler for dropdowns -->
  <Teleport to="body">
    <div
      v-if="showTtlDropdown || showPassphraseInput"
      class="fixed inset-0 z-40"
      @click="closeDropdowns" ></div>
  </Teleport>
</template>
