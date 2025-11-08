<!-- src/components/auth/AuthMethodSelector.vue -->

<script setup lang="ts">
import { ref, computed } from 'vue';
import { isMagicLinksEnabled } from '@/utils/features';
import SignInForm from './SignInForm.vue';
import MagicLinkForm from './MagicLinkForm.vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();

export interface Props {
  locale?: string;
}

withDefaults(defineProps<Props>(), {
  locale: 'en',
});

type AuthMethod = 'password' | 'magicLink';

// Check which methods are enabled
const magicLinksEnabled = isMagicLinksEnabled();

// Default to password method
const selectedMethod = ref<AuthMethod>('password');

// Available methods based on feature flags
const availableMethods = computed(() => {
  const methods: Array<{ key: AuthMethod; label: string }> = [
    { key: 'password', label: 'web.auth.methods.password' },
  ];

  if (magicLinksEnabled) {
    methods.push({ key: 'magicLink', label: 'web.auth.methods.magicLink' });
  }

  return methods;
});

const showTabs = computed(() => availableMethods.value.length > 1);

function selectMethod(method: AuthMethod) {
  selectedMethod.value = method;
}
</script>

<template>
  <div>
    <!-- Method tabs (only show if multiple methods available) -->
    <div
      v-if="showTabs"
      class="mb-6">
      <nav
        class="flex space-x-2 rounded-lg border border-gray-200 bg-gray-50 p-1 dark:border-gray-700 dark:bg-gray-800"
        aria-label="Auth methods">
        <button
          v-for="method in availableMethods"
          :key="method.key"
          @click="selectMethod(method.key)"
          :class="[
            'flex-1 rounded-md px-3 py-2 text-sm font-medium transition-all',
            selectedMethod === method.key
              ? 'bg-white text-brand-700 shadow-sm dark:bg-gray-700 dark:text-brand-400'
              : 'text-gray-600 hover:text-gray-900 dark:text-gray-400 dark:hover:text-gray-200',
          ]"
          :aria-current="selectedMethod === method.key ? 'page' : undefined">
          {{ t(method.label) }}
        </button>
      </nav>
    </div>

    <!-- Render selected auth method -->
    <SignInForm
      v-if="selectedMethod === 'password'"
      :locale="locale" />
    <MagicLinkForm v-else-if="selectedMethod === 'magicLink'" />
  </div>
</template>
