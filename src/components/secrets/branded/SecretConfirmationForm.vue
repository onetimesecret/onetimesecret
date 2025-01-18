<script setup lang="ts">
import { Secret, SecretDetails, brandSettingschema } from '@/schemas/models';
import { useProductIdentity } from '@/stores/identityStore';
import { ref, computed } from 'vue';
import BaseSecretDisplay from './BaseSecretDisplay.vue';


interface Props {
  secretKey: string;
  record: Secret | null;
  details: SecretDetails | null;
  domainId: string;
  isSubmitting: boolean;
  error: unknown;
}

const props = defineProps<Props>();

const emit = defineEmits(['user-confirmed']);
// const useSecret = useSecret();
const passphrase = ref('');

const submitForm = async () => {
  emit('user-confirmed', passphrase);
};

const productIdentity = useProductIdentity();
const brandSettings = productIdentity.brand; // Not reactive
const defaultBranding = brandSettingschema.parse({});
const safeBrandSettings = computed(() =>
  brandSettings ? brandSettingschema.parse(brandSettings) : defaultBranding
);

const hasImageError = ref(false);

const cornerStyle = computed(() => {
  switch (brandSettings?.corner_style) {
    case 'rounded': return 'rounded-lg';
    case 'pill': return 'rounded-full';
    case 'square': return 'rounded-none';
    default: return 'rounded-lg';
  }
});

const handleImageError = () => {
  hasImageError.value = true;
};

// Prepare the standardized path to the logo image.
// Note that the file extension needs to be present but is otherwise not used.
const logoImage = ref<string>(`/imagine/${props.domainId}/logo.png`);
</script>

<template>
  <BaseSecretDisplay default-title="You have a message"
                     :domain-branding="safeBrandSettings"
                     :instructions="brandSettings?.instructions_pre_reveal">
    <template #logo>
      <div class="relative mx-auto sm:mx-0">
        <div :class="[cornerStyle, 'size-14 sm:size-16 overflow-hidden']">
          <!-- Background container with matching corner style -->
          <div :class="[
              cornerStyle,
              'absolute inset-0 flex items-center justify-center bg-gray-100 dark:bg-gray-700',
              { 'hidden': logoImage && !hasImageError }
            ]">
            <!-- Default lock icon -->
            <svg v-if="!logoImage || hasImageError"
                 class="size-8 text-gray-400 dark:text-gray-500"
                 viewBox="0 0 24 24"
                 fill="none"
                 stroke="currentColor"
                 aria-hidden="true">
              <path stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
            </svg>
          </div>

          <!-- Logo -->
          <img v-if="logoImage && !hasImageError"
               :src="logoImage"
               alt="Brand logo"
               class="size-full object-contain"
               :class="cornerStyle"
               @error="handleImageError" />
        </div>
      </div>
    </template>

    <template #content>
      <div class="flex items-center text-gray-400 dark:text-gray-500"
           role="status"
           aria-label="Content status">
        <svg class="mr-2 size-5"
             viewBox="0 0 24 24"
             fill="none"
             stroke="currentColor"
             aria-hidden="true">
          <path stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M13.875 18.825A10.05 10.05 0 0112 19c-4.478 0-8.268-2.943-9.543-7A9.97 9.97 0 014.02 8.971m5.858.908a3 3 0 114.243 4.243M9.878 9.878l4.242 4.242M9.88 9.88l-3.29-3.29m7.532 7.532l3.29 3.29M3 3l3.59 3.59m0 0A9.953 9.953 0 0112 5c4.478 0 8.268 2.943 9.543 7a10.025 10.025 0 01-4.132 5.411m0 0L21 21" />
        </svg>
        <span class="text-sm">Content hidden</span>
      </div>
    </template>

    <template #action-button>
      <form @submit.prevent="submitForm"
            aria-label="Secret access form">
        <!-- Error Message -->
        <div v-if="error"
             class="mb-4 rounded-md bg-red-50 p-4 text-sm text-red-700 dark:bg-red-900/50 dark:text-red-200"
             role="alert">
          {{ error }}
        </div>

        <!-- Passphrase Input -->
        <div v-if="record?.has_passphrase"
             class="mb-4 space-y-2">
          <label :for="'passphrase-' + secretKey"
                 class="sr-only">
            {{ $t('web.COMMON.enter_passphrase_here') }}
          </label>
          <input v-model="passphrase"
                 :id="'passphrase-' + secretKey"
                 type="password"
                 name="passphrase"
                 :class="{
              'rounded-lg': brandSettings?.corner_style === 'rounded',
              'rounded-2xl': brandSettings?.corner_style === 'pill',
              'rounded-none': brandSettings?.corner_style === 'square',
              'w-full border border-gray-300 px-4 py-2 focus:outline-none focus:ring-2 focus:ring-offset-2 dark:border-gray-600 dark:bg-gray-700 dark:text-white': true
            }"
                 autocomplete="current-password"
                 :aria-label="$t('web.COMMON.enter_passphrase_here')"
                 :placeholder="$t('web.COMMON.enter_passphrase_here')"
                 aria-required="true" />
        </div>

        <!-- Submit Button -->
        <button type="submit"
                :disabled="isSubmitting"
                :class="{
            'rounded-lg': brandSettings?.corner_style === 'rounded',
            'rounded-full': brandSettings?.corner_style === 'pill',
            'rounded-none': brandSettings?.corner_style === 'square',
            [`font-${brandSettings?.font_family}`]: true,
            'w-full py-3 text-base font-medium transition-colors disabled:cursor-not-allowed disabled:opacity-50 sm:text-lg': true
          }"
                :style="{
            backgroundColor: brandSettings?.primary_color ?? '#dc4a22',
            color: brandSettings?.button_text_light ? '#ffffff' : '#222222',
          }"
                class="focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2"
                aria-live="polite">
          <span class="sr-only">{{ isSubmitting ? 'Submitting...' : 'Click to continue' }}</span>
          {{ isSubmitting ? $t('web.COMMON.submitting') : $t('web.COMMON.click_to_continue') }}
        </button>
      </form>
    </template>
  </BaseSecretDisplay>
</template>

<style>
.line-clamp-6 {
  display: -webkit-box;
  -webkit-line-clamp: 3;
  -webkit-box-orient: vertical;
  overflow: hidden;
}

/* Ensure focus outline is visible in all color schemes */
:focus {
  outline: 2px solid currentColor;
  outline-offset: 2px;
}
</style>
